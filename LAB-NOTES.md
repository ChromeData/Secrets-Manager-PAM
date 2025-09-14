# Lab Notes — Secrets Manager as PAM Control Plane

> Running log, newest first.

## Known traps (pre-seeded)

### enable_rotation = true with no Lambda ARN

Turning on rotation before the rotation Lambda exists fails the apply. Apply the
function first, wire its ARN into `rotation_lambda_arn`, then flip `enable_rotation`.

### CloudTrail data events are off by default

`GetSecretValue` will NOT appear in CloudTrail unless you enable data events for
Secrets Manager (extra cost). Discovering the audit gap is itself a finding for the
comparison doc.

### recovery_window blocks quick re-runs

A deleted secret sits in a 7-day recovery window; re-creating with the same name
fails until it's purged. Use `--force-delete-without-recovery` in the lab, and note
that this is the opposite of what you'd do in production.

## YYYY-MM-DD — <first real entry>

**Goal:** · **What happened:** · **Why:** · **Fix:** · **Time lost:**

## Open questions
- [ ] Does rotation cause a brief window where the consumer gets a stale secret?
- [ ] Cost of enabling data events at realistic read volume?
