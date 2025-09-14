# Lab Notes — 05 Secrets Manager as a PAM Control Plane

Running log. Errors, dead ends, fixes, and things that surprised me.
Dated entries, newest at the bottom. This file is the proof the lab was real.

---

## Format

```
### YYYY-MM-DD — what I was trying to do

**Expected:**
**Got:**
**Cause:**
**Fix:**
```

---

## Known traps (found while building — confirm when you run it)

### Rotation fails immediately with an invoke permission error

Secrets Manager has to be allowed to call the function. Without
`aws_lambda_permission.allow_secretsmanager`, `rotate-secret` returns an error
that talks about the *secret*, not the missing Lambda permission, so it sends you
looking in the wrong file. Already wired in `rotation.tf` — noted because it's
the most common first-run failure.

### `enable_rotation = true` with no function ARN

Leaves the secret in a state where the console shows rotation on and every
rotation attempt fails silently. Rotation is only enabled here because the
function exists and `depends_on` forces the ordering.

### Terraform wants to revert the password on every plan after a rotation

Rotation changes the value outside Terraform, so the next plan sees drift and
offers to "fix" it — by writing the stale seed value back over a live credential.
`ignore_secret_changes = true` prevents it. Without it this eventually causes an
outage during an unrelated apply.

### Data events cost money

The advanced event selector bills per event. Fine for a lab. Worth measuring
before enabling account-wide — put the number in the comparison doc when you
have it.

---

## Open questions to answer while running

- [ ] How long does a full four-step rotation actually take end to end?
- [ ] Does `prove-denied` still fail if the caller is the account root?
- [ ] What's the real per-event cost of data events over a week?
- [ ] Does the `kms:ViaService` condition block a `GenerateDataKey` path I missed?
- [ ] Measure: reads recorded in CloudTrail vs. reads actually made. Any gap?

---

## Log

_(first entry goes here on the first real run)_
