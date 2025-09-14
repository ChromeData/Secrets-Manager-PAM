# Built on terraform-aws-modules/terraform-aws-secrets-manager (Anton Babenko).
# This file is the lab's configuration of that module, not the module itself.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Purpose = "pam-cloud-lab"
      Lab     = "05-secrets-manager-pam"
    }
  }
}

data "aws_caller_identity" "current" {}

# The consuming application's role — the ONLY principal allowed to read the secret.
# In PAM terms this is the account that "checks out" the credential.
resource "aws_iam_role" "app" {
  name = "lab05-secret-consumer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

module "db_secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.3"

  name        = "lab05/database/app"
  description = "Application DB credential — lab PAM control-plane demo"

  # KMS-encrypted with a customer-managed key (create separately or use the module's).
  recovery_window_in_days = 7

  # Least-privilege resource policy: only the consumer role, and only GetSecretValue.
  create_policy       = true
  block_public_policy = true
  policy_statements = {
    read = {
      sid = "AllowConsumerRoleReadOnly"
      principals = [{
        type        = "AWS"
        identifiers = [aws_iam_role.app.arn]
      }]
      actions   = ["secretsmanager:GetSecretValue"]
      resources = ["*"]
      # Condition: only from within the VPC / only with MFA / only in-region — pick
      # one and document why. This is where PAM thinking shows.
      conditions = [{
        test     = "StringEquals"
        variable = "aws:PrincipalTag/Purpose"
        values   = ["pam-cloud-lab"]
      }]
    }
  }

  # Automatic rotation via a Lambda (wired in rotation/). Turn on once the function
  # exists; leaving it on with no function is a common first-run failure — see notes.
  enable_rotation     = false
  rotation_lambda_arn = "" # set to module.rotation_lambda output after apply
  rotation_rules = {
    automatically_after_days = 30
  }

  ignore_secret_changes = true # rotation changes the value out-of-band; don't fight it
}
