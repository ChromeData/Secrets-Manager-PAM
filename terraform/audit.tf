# Audit trail for secret reads.
#
# This is the part people skip. Secrets Manager does NOT log GetSecretValue to
# CloudTrail by default in a way you can query per-secret without turning on
# data events. Management events tell you the secret was created and rotated.
# They do not tell you who read the value, which is the only question that
# matters after an incident.
#
# CyberArk gives you this for free - every retrieval is a vault audit record.
# On AWS you build it, and it costs money per event. That difference belongs in
# the comparison doc.

resource "aws_s3_bucket" "trail" {
  bucket        = "${var.name_prefix}-trail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.name_prefix}"
  retention_in_days = var.audit_log_retention_days
}

resource "aws_iam_role" "trail_to_cloudwatch" {
  name = "${var.name_prefix}-trail-to-cw"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "trail_to_cloudwatch" {
  name = "write-trail-events"
  role = aws_iam_role.trail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "secrets" {
  name                          = "${var.name_prefix}-secrets-trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  include_global_service_events = false
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_cloudwatch.arn

  # The data event selector. This is the line that makes secret reads visible.
  advanced_event_selector {
    name = "Secrets Manager value reads"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::SecretsManager::Secret"]
    }
  }

  depends_on = [aws_s3_bucket_policy.trail]
}

# Alarm on a burst of reads. One read is normal. Forty in a minute is either a
# broken retry loop or someone walking the vault - both worth waking up for.
resource "aws_cloudwatch_log_metric_filter" "bulk_reads" {
  name           = "${var.name_prefix}-bulk-secret-reads"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ $.eventName = \"GetSecretValue\" }"

  metric_transformation {
    name      = "SecretValueReads"
    namespace = "PamCloudLab"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "bulk_reads" {
  alarm_name          = "${var.name_prefix}-bulk-secret-reads"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 60
  threshold           = 20
  statistic           = "Sum"
  metric_name         = "SecretValueReads"
  namespace           = "PamCloudLab"
  treat_missing_data  = "notBreaching"

  alarm_description = "More than 20 secret reads in a minute - possible enumeration."
}
