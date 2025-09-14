variable "region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource this lab creates, so teardown is easy to verify."
  type        = string
  default     = "lab05"
}

variable "secret_name" {
  description = "Path-style name of the secret. Slashes are how you get a folder-like hierarchy."
  type        = string
  default     = "lab05/database/app"
}

variable "rotation_days" {
  description = "How often the credential rotates automatically."
  type        = number
  default     = 30

  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "rotation_days must be between 1 and 365."
  }
}

variable "recovery_window_in_days" {
  description = <<-EOT
    Days AWS keeps a deleted secret recoverable. 0 deletes immediately.
    Kept at 7 so a bad teardown is survivable - the same reasoning behind
    Key Vault soft-delete and a CyberArk safe retention policy.
  EOT
  type        = number
  default     = 7
}

variable "allowed_source_vpce" {
  description = <<-EOT
    Optional VPC endpoint ID. When set, the secret's resource policy will only
    permit reads arriving through this endpoint - network-path restriction on
    top of identity, which is the closest AWS gets to CyberArk session isolation.
    Leave empty to skip the condition.
  EOT
  type        = string
  default     = ""
}

variable "audit_log_retention_days" {
  description = "CloudWatch retention for the CloudTrail log group carrying secret-read events."
  type        = number
  default     = 14
}
