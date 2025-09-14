# The secret itself, its encryption key, and the one role allowed to read it.
#
# Built on terraform-aws-modules/secrets-manager (Apache-2.0, Anton Babenko).
# The module creates the secret; the access model below is this lab's work.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Encryption key
#
# The AWS-managed key (aws/secretsmanager) works, but it cannot carry its own
# key policy. A customer-managed key can - which means decrypt permission
# becomes a second, independent gate in front of the secret. Losing control of
# the secret policy is then not enough to read the value. In vault terms this
# is the difference between one lock and two locks keyed differently.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "secrets" {
  description             = "${var.name_prefix} - encrypts the lab secret"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowConsumerDecryptViaSecretsManagerOnly"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.consumer.arn }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          # Decrypt is granted only when the call arrives *through* Secrets
          # Manager. The role cannot take the ciphertext elsewhere and unwrap it.
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      {
        Sid       = "AllowRotationFunctionUse"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.rotation.arn }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ---------------------------------------------------------------------------
# The consuming workload
#
# In PAM language this is the application identity that "checks out" the
# credential. It gets exactly one action on exactly one secret.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "consumer" {
  name = "${var.name_prefix}-secret-consumer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Purpose = "pam-cloud-lab" }
}

resource "aws_iam_role_policy" "consumer_read" {
  name = "read-lab-secret"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = module.db_secret.secret_arn
    }]
  })
}

# ---------------------------------------------------------------------------
# The secret
#
# Two things make this least-privilege rather than merely private:
#
#   1. The resource policy names the consumer role explicitly and denies
#      everyone else, so an over-broad IAM policy elsewhere in the account
#      still cannot read it. Identity policy and resource policy must BOTH
#      allow. That intersection is the control.
#   2. block_public_policy refuses any future policy that would open it up.
# ---------------------------------------------------------------------------
module "db_secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.3"

  name        = var.secret_name
  description = "Application DB credential - PAM control-plane lab"

  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = var.recovery_window_in_days

  # Seed value. Rotation replaces the password on first run; username persists.
  create_random_password = false
  secret_string = jsonencode({
    username = "lab_app_user"
    password = random_password.seed.result
    engine   = "postgres"
    host     = "lab-placeholder.local"
    port     = 5432
  })

  # The resource policy is attached separately, in policy.tf. The module's
  # policy_statements variable is a typed map that requires every statement to
  # carry an identical set of attributes, which a Deny/NotPrincipal statement
  # cannot satisfy alongside a conditional Allow. Writing the policy directly
  # is clearer and keeps the access model in one readable block.
  create_policy = false

  # Rotation is wired to the function defined in rotation.tf.
  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_rules = {
    automatically_after_days = var.rotation_days
  }

  # Rotation changes the value outside Terraform. Without this, every plan
  # after a rotation shows a spurious diff and someone eventually "fixes" it
  # by applying the stale value back over a live credential.
  ignore_secret_changes = true

  depends_on = [aws_lambda_permission.allow_secretsmanager]
}

resource "random_password" "seed" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
