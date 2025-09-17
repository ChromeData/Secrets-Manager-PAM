# Lab 05: AWS Secrets Manager as a PAM Control Plane

[![tests](https://github.com/ChromeData/Secrets-Manager-PAM/actions/workflows/tests.yml/badge.svg)](https://github.com/ChromeData/Secrets-Manager-PAM/actions/workflows/tests.yml)

**Can AWS's built in secrets service replace a CyberArk vault? I built it properly, then judged it from the vault side. Answer: for machines yes, for people no, and the audit trail is off by default.**

| | |
|---|---|
| **Domains** | CyberArk/Idira, AWS |
| **Built on** | [terraform-aws-modules/secrets-manager](https://github.com/terraform-aws-modules/terraform-aws-secrets-manager) (Anton Babenko) |
| **Cost** | Under $1. **Runtime** ~4 hours |
| **Status** | Applied for real against LocalStack. Secret, CMK and retrieval verified (output in findings/). CloudTrail audit half needs real AWS |

## Situation

Everyone compares these two from the AWS side. The useful version comes from someone who has actually run a vault, because the gaps only look obvious if you know what a vault does for free.

## Task

Deploy AWS Secrets Manager the right way, then write the honest control by control comparison almost nobody produces.

## Action

I built four things:

**A three layer access model.** To read the secret you must pass an identity policy, a resource policy, and a KMS key policy. All three must allow. That overlap is the control, not any one layer.

**A deny that beats admin.** The resource policy denies every principal except the app role and the rotation function. Your own account admin holds full secrets access and still gets refused. `make prove-denied` shows it in about four seconds.

**A working rotation function** ([rotation/index.py](./rotation/index.py)), the real four step AWS flow: create, set, test, finish. If any step fails, the current credential is untouched and still works. Same guarantee CyberArk's CPM gives you.

**Read auditing, which is the actual finding.** CloudTrail does not log secret reads by default. Reading a secret is a data event, off unless you turn it on and pay per event. So the default setup cannot answer "who read this last Tuesday." A vault answers that on day one for free. Turning it on here took five resources.

The comparison lives in [docs/cyberark-comparison.md](./docs/cyberark-comparison.md), which is the real deliverable.

## Result

**Applied for real** against LocalStack, which runs Secrets Manager, KMS and IAM locally. The secret, the customer managed key and both roles deploy, and retrieval works end to end. The `kms:ViaService` condition is confirmed present on the deployed key policy, which is the control that stops the app role carrying ciphertext elsewhere to unwrap it.

**The audit half is still unproven, and it is the important half.** CloudTrail is a LocalStack paid feature, so `terraform/audit.tf` could not run. That file carries this lab's central claim, that secret reads are invisible until you enable data events. It needs a real AWS run.

Also unproven locally: `prove-denied`, because LocalStack does not evaluate resource policy at request time. So the access model is built and deployed and the retrieval path is proven; the audit and enforcement claims are not yet. Full output in [findings/localstack-apply-run.txt](./findings/localstack-apply-run.txt).

`terraform validate` passes and CI is green. Building it caught a real dependency cycle that validate flagged. It is in the history.

## What I did not build

The secret resource comes from Anton Babenko's module. The access model, the rotation handler, the KMS rules, the audit wiring, and the comparison are mine.

## Run it

```bash
make apply
make prove-denied        # your admin is refused, the deny works
make read-as-consumer    # the app role succeeds
make rotate-now          # forces rotation
make audit               # pulls your read back out of CloudTrail
make destroy
```

Needs the AWS CLI, jq, and Terraform 1.9+.

## Findings

`findings/` is empty until I run it. [LAB-NOTES.md](./LAB-NOTES.md) is the log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). Upstream module stays Apache 2.0, credited above.
