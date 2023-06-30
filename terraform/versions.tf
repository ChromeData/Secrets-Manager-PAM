terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "use_localstack" {
  description = <<-EOT
    Point the provider at a local LocalStack endpoint instead of real AWS.

    LocalStack implements Secrets Manager, KMS, IAM and Lambda, so the secret,
    the key policy, the rotation function and an actual rotation all run
    locally at zero cost. What it does not do is enforce resource policy at
    request time, so the prove-denied test still needs real AWS.
  EOT
  type        = bool
  default     = false
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Purpose = "pam-cloud-lab"
      Lab     = "05-secrets-manager-pam"
    }
  }

  skip_credentials_validation = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  skip_metadata_api_check     = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      iam            = "http://localhost:4566"
      sts            = "http://localhost:4566"
      kms            = "http://localhost:4566"
      secretsmanager = "http://localhost:4566"
      lambda         = "http://localhost:4566"
      s3             = "http://localhost:4566"
      cloudtrail     = "http://localhost:4566"
      cloudwatchlogs = "http://localhost:4566"
    }
  }
}
