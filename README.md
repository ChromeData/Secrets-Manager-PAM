# Lab 05 — AWS Secrets Manager as a PAM Control Plane

**Deploy AWS Secrets Manager with least-privilege resource policies, automatic
rotation, and audit logging — then write it up as a CyberArk engineer evaluating
the cloud-native alternative to a vault.**

| | |
|---|---|
| **Domains** | CyberArk/Idira · AWS · Linux |
| **Built on** | [terraform-aws-modules/terraform-aws-secrets-manager](https://github.com/terraform-aws-modules/terraform-aws-secrets-manager) (Apache-2.0, by Anton Babenko / terraform-aws-modules) · [terraform-aws-lambda](https://github.com/terraform-aws-modules/terraform-aws-lambda) |
| **Runtime** | ~4 hours · < $1 |
| **Status** | 🟡 In progress |

---

## Why this lab exists

You know how CyberArk manages a credential: access policy, rotation policy, audit
trail. AWS Secrets Manager claims to do the same thing natively. The valuable
artifact almost nobody produces is a **side-by-side evaluation written by someone
who actually operates PAM** — where the cloud-native version is equivalent, where
it's weaker, and where you'd still reach for a dedicated vault.

This is your signature piece. It's the one lab on this list that only makes sense
coming from a CyberArk person.

## What I built

- Secrets Manager secrets provisioned via Anton Babenko's module, each with a
  **resource policy scoped by principal and condition keys** (least privilege at
  the secret, not just the IAM layer).
- An **automatic rotation Lambda** (built with `terraform-aws-lambda`) so the
  secret rotates without a human touching it.
- **CloudTrail data events** on secret reads, so every `GetSecretValue` is audited.
- **`docs/cyberark-comparison.md`** — the deliverable: a control-by-control mapping
  of Secrets Manager against CyberArk/Conjur (access policy ↔ resource policy,
  CPM rotation ↔ rotation Lambda, PSM audit ↔ CloudTrail), with an honest verdict
  on each.

## What I did not build

The Terraform module and the Lambda module are Anton Babenko's / the
terraform-aws-modules org's. My work is the least-privilege policy design, the
rotation function logic, the audit wiring, and the comparative analysis.

---

## Running it

```bash
make init
make plan
make apply
make rotate-now     # force a rotation, watch it succeed in CloudTrail
make audit          # pull the last N GetSecretValue events
make destroy
```

## The deliverable

`docs/cyberark-comparison.md` is the point. Suggested table:

| PAM capability | CyberArk/Conjur | AWS Secrets Manager | Verdict |
|----------------|-----------------|---------------------|---------|
| Access policy granularity | | resource policy + IAM + condition keys | |
| Rotation | CPM plugins | rotation Lambda | |
| Audit of secret access | PSM / vault audit | CloudTrail data events | |
| Break-glass / dual control | | | |
| Cross-account sharing | | resource policy + KMS grant | |

Fill the verdict column from experience, not marketing. That column is what a
hiring manager reads.

## What broke

See [LAB-NOTES.md](./LAB-NOTES.md).
