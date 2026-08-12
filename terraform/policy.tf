# The resource policy — the actual access control for this lab.
#
# Read this as three rules:
#
#   1. The app role may read the secret. Optionally only via a VPC endpoint.
#   2. The rotation function may read and replace it.
#   3. Nobody else may read it. Not even an admin holding secretsmanager:*.
#
# Rule 3 is the interesting one. An IAM identity policy granting
# secretsmanager:* is an *allow*, but an explicit Deny in the resource policy
# always wins. That is why `make prove-denied` fails for your own admin
# identity. Most people assume IAM alone is the control; it is only half of it.

data "aws_iam_policy_document" "secret" {
  statement {
    sid    = "AllowConsumerRoleReadOnly"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.consumer.arn]
    }

    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]

    # Network-path restriction, applied only when a VPC endpoint was supplied.
    # Identity says who; this says from where. The closest AWS gets to the
    # network containment PSM provides.
    dynamic "condition" {
      for_each = var.allowed_source_vpce == "" ? [] : [var.allowed_source_vpce]

      content {
        test     = "StringEquals"
        variable = "aws:sourceVpce"
        values   = [condition.value]
      }
    }
  }

  statement {
    sid    = "AllowRotationFunction"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.rotation.arn]
    }

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecretVersionStage",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DenyEveryPrincipalExceptTheseTwo"
    effect = "Deny"

    # NotPrincipal + Deny is a blunt instrument and easy to get wrong. Account
    # root stays on the list deliberately: leave it off and a policy mistake
    # can lock the secret away from everyone, including you, permanently.
    not_principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.consumer.arn,
        aws_iam_role.rotation.arn,
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
    }

    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  secret_arn = module.db_secret.secret_arn
  policy     = data.aws_iam_policy_document.secret.json

  # Refuses any future policy that would make the secret publicly readable.
  block_public_policy = true
}
