# Secrets Manager vs. CyberArk/Conjur — a PAM engineer's evaluation

> This is the deliverable of Lab 05. Fill each verdict from your own testing, not
> from vendor docs. The value of this document is that it's written by someone who
> operates PAM, comparing honestly.

## Framing

AWS Secrets Manager and a dedicated PAM/vault platform solve overlapping but not
identical problems. Secrets Manager is a cloud-native secret store with rotation.
CyberArk/Conjur is a privileged-access platform: vaulting, session isolation,
credential brokering, dual control, and audit as a first-class product. Comparing
them one-to-one flatters neither; comparing them capability-by-capability is useful.

## Control-by-control

### Access policy granularity
- **CyberArk/Conjur:** _(your notes — policy model, RBAC, host identities)_
- **Secrets Manager:** IAM identity policy + resource policy + KMS key policy +
  condition keys. Three layers that must agree.
- **Verdict:** _____

### Rotation
- **CyberArk:** CPM plugins per platform.
- **Secrets Manager:** rotation Lambda; managed rotation for RDS/Redshift/DocDB.
- **Verdict:** _____ (Test: does rotation break the consumer? How is the old
  version retained during the rotation window?)

### Audit of secret access
- **CyberArk:** vault audit + PSM session recording.
- **Secrets Manager:** CloudTrail data events on `GetSecretValue`. Note: data
  events are **off by default and cost extra** — a real gap to document.
- **Verdict:** _____

### Dual control / break-glass
- **CyberArk:** native dual control, ticketing integration.
- **Secrets Manager:** no native concept; you'd approximate with SCPs, approval
  workflows, or a separate break-glass account.
- **Verdict:** _____ (This is likely where the dedicated platform clearly wins —
  say so.)

### Session isolation
- **CyberArk:** PSM proxies the session; the human never holds the credential.
- **Secrets Manager:** none. The consumer gets the plaintext secret.
- **Verdict:** _____ (Different category of product. Worth stating plainly.)

## Overall

_Two paragraphs: when is Secrets Manager sufficient, and when would you still
mandate a PAM platform? An interviewer will quote this back to you — make it a
position you can defend._
