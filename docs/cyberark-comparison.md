# Secrets Manager vs. a Real Vault

An honest control-by-control read on whether AWS Secrets Manager replaces
CyberArk/Idira, written from the vault side rather than the cloud side.

**The short version:** Secrets Manager is a good *secrets store*. A vault is a
*privileged access system*. Those overlap about 60%, and the missing 40% is
everything that exists because a human might be the one holding the credential.

> Verdicts below come from building the lab in this repo and from operating
> CyberArk. Where a verdict depends on your environment, it says so. Re-test
> before quoting any of it in an architecture review.

---

## Scorecard

| Capability | CyberArk / Idira | AWS Secrets Manager | Verdict |
|---|---|---|---|
| **Credential storage** | Vault, encrypted per-object | Encrypted with KMS, CMK optional | **Tie.** Both fine. Use a customer-managed key or you lose the second gate. |
| **Access policy granularity** | Safe membership + per-account authorizations | IAM policy ∩ resource policy ∩ KMS key policy | **AWS wins on precision.** Three independent layers that must all allow. More expressive than safe membership. Also easier to get subtly wrong. |
| **Rotation** | CPM plugins, large connector library | Rotation Lambda you write | **CyberArk wins on coverage.** CPM ships plugins for hundreds of targets. AWS gives you four function stubs and a shrug. Parity for one app, not for an estate. |
| **Audit of retrieval** | Every fetch is a vault record, on by default | CloudTrail **data events**, off by default, billed per event | **CyberArk wins, decisively.** See below - this is the single biggest gap. |
| **Session isolation / proxying** | PSM: no credential ever reaches the human | Nothing equivalent | **No contest.** AWS has no PSM analogue. Out of scope for the product. |
| **Session recording** | PSM keystroke + video recording | Nothing equivalent | **No contest.** |
| **Dual control / approval** | Built-in workflow | Build it yourself | **CyberArk wins.** See below. |
| **Break-glass** | Native, with its own approval path | IAM role + your own alarms | **CyberArk wins on ceremony**, AWS is fine mechanically. |
| **Cross-account sharing** | Vault-to-vault, awkward | Resource policy + KMS grant | **AWS wins clearly.** This is genuinely easy on AWS and genuinely painful on CyberArk. |
| **Discovery of unmanaged accounts** | Native account discovery | Nothing native | **CyberArk wins.** AWS will not tell you which credentials you forgot to onboard. |
| **Cost model** | Licensed per managed account | ~$0.40/secret/month + API + data-event charges | **Depends.** AWS is far cheaper at 50 secrets, and the data-event bill bites at scale. |
| **Human checkout** | The core use case | Not a use case | **Different products.** |

---

## The three gaps that actually matter

### 1. Retrieval auditing is off by default and costs money

This is the finding worth leading with, because most "we replaced our vault with
Secrets Manager" write-ups miss it entirely.

CloudTrail **management** events record that a secret was created, updated, and
rotated. They do **not** record `GetSecretValue`. Reading a secret value is a
*data* event, and data events are off unless you turn them on and pay per event.

So the default posture is: you can prove the secret exists and rotates, and you
cannot answer "who read this credential last Tuesday." In a vault, that question
is answered by design, on day one, at no extra cost.

`terraform/audit.tf` in this repo turns it on. The relevant part is the advanced
event selector scoped to `AWS::SecretsManager::Secret`. Note what it took: a
CloudTrail, an S3 bucket with a policy, a log group, a role, and a metric filter.
Five resources to get a capability that is the vault's opening move.

**If you take one thing to an architecture review, take this one.** Ask whether
data events are on. The answer is usually no, and the person who owns the secret
usually does not know.

### 2. Nothing stands between a human and the credential

CyberArk's PSM exists because a credential a human can see is a credential a
human can keep. The human connects through a proxy, the proxy holds the secret,
and the session is recorded.

Secrets Manager has no equivalent, and this is not a defect - it is not that kind
of product. But it means the substitution only works for **machine** identities.
The moment a person needs privileged access to the target, Secrets Manager hands
them the password and the audit trail ends at "they read it."

The practical rule: Secrets Manager for app-to-app credentials, a vault for
anything a person touches. Most teams that "replaced CyberArk" replaced the
app-to-app half and quietly kept the vault for humans.

### 3. Dual control has to be built

Vault-side, requiring two approvals before a credential is released is a
checkbox. On AWS you assemble it: an approval step, something to hold the request,
something to grant time-boxed access, and something to revoke it after.

It is buildable and people do build it. But "buildable" and "a control you can
point an auditor at on day one" are different claims, and the gap between them is
usually a quarter of engineering time nobody budgeted.

---

## Where AWS is genuinely better

Being fair costs nothing and makes the rest credible.

- **Policy expressiveness.** The intersection of identity policy, resource policy,
  and KMS key policy is more precise than safe membership. The `kms:ViaService`
  condition in `main.tf` - decrypt permitted only when the call arrives through
  Secrets Manager - has no clean CyberArk equivalent.
- **Cross-account sharing.** A resource policy plus a KMS grant, and you are done.
  Anyone who has federated CyberArk vaults across business units knows the
  contrast.
- **No infrastructure.** No vault servers, no CPM servers, no PSM farm, no DR
  pair. For a small estate this outweighs most of the gaps above.
- **Cost at small scale.** Fifty secrets is roughly $20/month. Compare to a
  license.

---

## The recommendation

| Situation | Use |
|---|---|
| App-to-app credentials, cloud-native workloads | **Secrets Manager.** Turn on data events. |
| Any credential a human checks out | **Vault.** Session isolation is the requirement. |
| Regulated estate needing recorded sessions | **Vault.** Not a close call. |
| Small team, no existing vault, machine identities only | **Secrets Manager.** Do not buy a vault for this. |
| Existing CyberArk estate, adding cloud workloads | **Both.** Conjur for the cloud half - see [Lab 01](https://github.com/ChromeData/Conjur-Terraform-AWS). |

The question "should we replace CyberArk with Secrets Manager" is usually the
wrong question. The right one is "which half of what CyberArk does for us is
actually machine-to-machine," because that half moves cheaply and the other half
does not move at all.

---

## Reproducing this

```bash
make apply
make prove-denied        # resource policy beats an over-broad identity policy
make rotate-now          # four-step rotation, current credential never breaks
make audit               # the read you just did, from CloudTrail data events
make destroy
```

`make prove-denied` is the one to run in front of someone. Your own admin
identity has `secretsmanager:*` and still cannot read the secret, because the
resource policy denies every principal that is not the app role. That
intersection is the control, and it is the thing most people assume IAM alone
gives them.
