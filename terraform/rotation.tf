# The rotation function - the AWS equivalent of a CyberArk CPM plugin.
#
# CPM logs into the target, changes the credential, verifies it, and updates the
# vault. This does the same four things, just split into four Lambda invocations
# so a failure at any point leaves the current credential working. Handler code
# is in ../rotation/index.py.

data "archive_file" "rotation" {
  type        = "zip"
  source_dir  = "${path.module}/../rotation"
  output_path = "${path.module}/.build/rotation.zip"
}

resource "aws_iam_role" "rotation" {
  name = "${var.name_prefix}-rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Scoped to this secret only. A rotation function with secretsmanager:* across
# the account is a single credential away from being the most privileged thing
# you own - it can read and overwrite every secret you have.
resource "aws_iam_role_policy" "rotation" {
  name = "rotate-lab-secret"
  role = aws_iam_role.rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        # Built by hand rather than read from module.db_secret.secret_arn.
        # Referencing the module output here creates a dependency cycle: the
        # secret needs the function's ARN for rotation, the function needs this
        # policy, and this policy would need the secret. `terraform validate`
        # catches it as "Cycle:". The trailing -* covers the six random
        # characters AWS appends to every Secrets Manager ARN.
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_name}-*"
      },
      {
        # GetRandomPassword takes no resource, so it cannot be scoped further.
        Effect   = "Allow"
        Action   = "secretsmanager:GetRandomPassword"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.rotation.arn}:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "rotation" {
  name              = "/aws/lambda/${var.name_prefix}-rotation"
  retention_in_days = var.audit_log_retention_days
}

resource "aws_lambda_function" "rotation" {
  function_name = "${var.name_prefix}-rotation"
  role          = aws_iam_role.rotation.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.rotation.output_path
  source_code_hash = data.archive_file.rotation.output_base64sha256

  environment {
    variables = {
      PASSWORD_LENGTH = "32"
    }
  }

  depends_on = [
    aws_iam_role_policy.rotation,
    aws_cloudwatch_log_group.rotation,
  ]
}

# Secrets Manager must be allowed to invoke the function, otherwise rotation
# fails with an opaque permissions error that does not name this as the cause.
resource "aws_lambda_permission" "allow_secretsmanager" {
  statement_id   = "AllowSecretsManagerInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rotation.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}
