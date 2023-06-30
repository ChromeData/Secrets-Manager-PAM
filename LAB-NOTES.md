# Lab Notes, 05 Secrets Manager as a PAM Control Plane

Running log. Errors, dead ends, fixes, and things that surprised me.
Dated entries, newest at the bottom. This file is the proof the lab was real.

---

## Format

```
### YYYY-MM-DD, what I was trying to do

**Expected:**
**Got:**
**Cause:**
**Fix:**
```

---

## Known traps (found while building, confirm when you run it)

### Rotation fails immediately with an invoke permission error

Secrets Manager has to be allowed to call the function. Without
`aws_lambda_permission.allow_secretsmanager`, `rotate-secret` returns an error
that talks about the *secret*, not the missing Lambda permission, so it sends you
looking in the wrong file. Already wired in `rotation.tf`, noted because it's
the most common first-run failure.

### `enable_rotation = true` with no function ARN

Leaves the secret in a state where the console shows rotation on and every
rotation attempt fails silently. Rotation is only enabled here because the
function exists and `depends_on` forces the ordering.

### Terraform wants to revert the password on every plan after a rotation

Rotation changes the value outside Terraform, so the next plan sees drift and
offers to "fix" it, by writing the stale seed value back over a live credential.
`ignore_secret_changes = true` prevents it. Without it this eventually causes an
outage during an unrelated apply.

### Data events cost money

The advanced event selector bills per event. Fine for a lab. Worth measuring
before enabling account-wide, put the number in the comparison doc when you
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

### 2026-08-11, wiring rotation to the secret

**Expected:** `terraform validate` to pass once the rotation Lambda existed.

**Got:**

```
Error: Cycle: module.db_secret.var.name (expand), module.db_secret.var.replica (expand),
module.db_secret.var.description (expand), module.db_secret.var.create (expand),
module.db_secret.var.kms_key_id (expand), ... module.db_secret.output.secret_arn (expand),
aws_iam_role_policy.rotation, aws_lambda_function.rotation,
aws_lambda_permission.allow_secretsmanager, module.db_secret (expand)
```

**Cause:** I scoped the rotation role's policy to `module.db_secret.secret_arn`, which
felt like good practice. But the secret needs the function's ARN to enable rotation,
the function needs its role policy, and the policy was reaching back for the secret.
Three-way cycle.

**Fix:** Built the ARN by hand from account + region + secret name, with a trailing
`-*` for the six random characters AWS appends. Same scoping, no edge back into the
module. Worth noting the scoping is *not* looser: the wildcard only covers the random
suffix, not other secrets.

---

### 2026-08-12, real apply against LocalStack

Ran the configuration against LocalStack community, which implements Secrets
Manager, KMS and IAM locally. The secret, the customer managed key, its key
policy and both roles all created, and retrieval works end to end:

```
secret:      lab05/database/app
KmsKeyId:    arn:aws:kms:us-east-1:000000000000:key/8c3d268f-...
RotationEnabled: true

get-secret-value -> {'engine':'postgres','host':'lab-placeholder.local',
                     'password':'fP5A...','port':5432,'username':'lab_app_user'}
```

The `kms:ViaService` condition is present on the deployed key policy:

```
AllowConsumerDecryptViaSecretsManagerOnly ->
  {"StringEquals": {"kms:ViaService": "secretsmanager.us-east-1.amazonaws.com"}}
```

That is the control that stops the consumer role carrying ciphertext somewhere
else and unwrapping it, and it has no clean CyberArk equivalent. Worth pointing
at directly in the comparison doc rather than describing.

**What would not run, and it is the important half.** A full apply hangs:
CloudTrail is a LocalStack Pro feature. So `terraform/audit.tf` is unexercised,
and that file carries this lab's central finding, that secret reads are
invisible until you turn on data events and pay per event. It stays unverified
until a real AWS run. Applied the rest with `-target`.

Rotation is enabled on the secret but I did not trigger one. LocalStack
community's Lambda execution is not reliable enough for the four step protocol,
and a green result there would not mean anything.

LocalStack also does not evaluate resource policy at request time, so
`prove-denied` remains a real AWS test. The honest position: the access model is
built and deployed, the retrieval path is proven, the audit and enforcement
claims are not yet.

Full output in `findings/localstack-apply-run.txt`.

---

### 2026-08-11, resource policy through the module

**Expected:** three statements (allow read, allow rotate, deny everyone else) via the
module's `policy_statements`.

**Got:**

```
Error: Invalid value for input variable
  on main.tf line 141, in module "db_secret":
The given value is not suitable for module.db_secret.var.policy_statements
declared at .terraform\modules\db_secret\variables.tf:81,1-29: all map
elements must have the same type.
```

**Cause:** The module types `policy_statements` as a map, so every statement needs an
identical attribute set. A `Deny` with `not_principals` can't match the shape of a
conditional `Allow`.

**Fix:** Set `create_policy = false` and wrote the policy directly with
`aws_iam_policy_document` + `aws_secretsmanager_secret_policy` (see `policy.tf`).
Ended up clearer anyway: the whole access model is one readable block instead of a
typed map fighting the schema.

**Takeaway:** a module that makes the common case easy can make the correct case
impossible. Dropping to the resource was the right call, not a workaround.
