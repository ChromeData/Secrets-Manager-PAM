output "secret_arn" {
  description = "ARN of the lab secret."
  value       = module.db_secret.secret_arn
}

output "secret_name" {
  description = "Name of the lab secret, for use with the CLI."
  value       = var.secret_name
}

output "consumer_role_arn" {
  description = "The only application role permitted to read the secret."
  value       = aws_iam_role.consumer.arn
}

output "rotation_function_name" {
  description = "Rotation Lambda. Use with 'make rotate-now'."
  value       = aws_lambda_function.rotation.function_name
}

output "kms_key_arn" {
  description = "Customer-managed key wrapping the secret."
  value       = aws_kms_key.secrets.arn
}

output "trail_log_group" {
  description = "CloudWatch log group carrying GetSecretValue data events."
  value       = aws_cloudwatch_log_group.trail.name
}

output "audit_query" {
  description = "Ready-to-run command that answers 'who read this secret?'"
  value       = <<-EOT
    aws logs filter-log-events \
      --log-group-name ${aws_cloudwatch_log_group.trail.name} \
      --filter-pattern '{ $.eventName = "GetSecretValue" }' \
      --query 'events[].message' --output text
  EOT
}
