# Lab 05 — AWS Secrets Manager as a PAM Control Plane

**Can AWS's built-in secrets service replace a CyberArk vault? I built it
properly, then judged it from the vault side. Answer: for machines yes, for
people no — and the audit trail is off by default.**

| | |
|---|---|
| **Domains** | CyberArk/Idira · AWS |
| **Built on** | [terraform-aws-modules/secrets-manager](https://github.com/terraform-aws-modules/secrets-manager/aws) (Apache-2.0, Anton Babenko) |
| **Cost** | < $1 · **Runtime** ~4 hours |
| **Status** | 🟡 Built, not yet run |

---

## The point

Everyone compares these two from the AWS side. The useful version comes from
someone who has actually run a vault, because the gaps only look obvious if you
know what a vault does for free.

**[`docs/cyberark-comparison.md`](./docs/cyberark-comparison.md) is the
deliverable.** The Terraform exists to make that document honest.

## What I built

**Three-layer access model.** To read the secret you must pass an IAM policy, a
resource policy, *and* a KMS key policy. All three must allow. That intersection
is the control — not any one of them.

**A deny that beats admin.** The resource policy explicitly denies every
principal except the app role and the rotation function. Your own account admin
holds `secretsmanager:*` and still gets refused. `make prove-denied` demonstrates
it in about four seconds, and it's the single best thing to show someone.

**A working rotation function** ([`rotation/index.py`](./rotation/index.py)) —
the real four-step AWS protocol: create, set, test, finish. If any step throws,
the current credential is untouched and still works. That's the same guarantee
CyberArk's CPM gives you on a failed change, and the `testSecret` step is the one
people skip on their way to rotating themselves into an outage.

**Decrypt that only works through the front door.** The KMS key grants the app
role `Decrypt` only under `kms:ViaService = secretsmanager`. The role can't take
the ciphertext somewhere else and unwrap it. There's no clean CyberArk equivalent
for this one — it's a point in AWS's favour.

**Retrieval auditing, which is the actual finding.** CloudTrail does *not* log
`GetSecretValue` by default — reading a secret is a "data event", off unless you
enable it and pay per event. So the default posture can't answer "who read this
credential last Tuesday." A vault answers that on day one for free.
[`terraform/audit.tf`](./terraform/audit.tf) turns it on. It took five resources.

## What I didn't build

The secret resource comes from Anton Babenko's module. The access model,
rotation handler, KMS conditions, audit wiring, and the comparison are mine.

---

## Running it

```bash
make apply
make prove-denied        # your admin identity is refused — the deny works
make read-as-consumer    # the app role succeeds
make rotate-now          # forces rotation, waits for AWSPENDING to clear
make audit               # pulls your read back out of CloudTrail
make destroy
```

Needs the AWS CLI, `jq`, and Terraform ≥ 1.9. `make validate` checks syntax
without touching AWS.

## Findings

`findings/` is empty until I run it. [LAB-NOTES.md](./LAB-NOTES.md) is the log —
errors, dead ends, fixes.

## License

Lab code: MIT ([LICENSE](./LICENSE)). Upstream module stays Apache-2.0 and is
credited above.
