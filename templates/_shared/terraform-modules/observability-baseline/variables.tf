variable "project_name" {
  type        = string
  description = "Project name (used in resource naming + tagging)"
}

variable "env" {
  type        = string
  description = "Environment: dev, staging, or prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod"
  }
}

variable "log_retention_days_override" {
  type        = number
  description = "Override the default per-env log retention (7/30/90 for dev/staging/prod)"
  default     = null
}

variable "additional_log_group_names" {
  type        = list(string)
  description = "Additional CloudWatch Log Group names beyond the lambda-base default"
  default     = []
}

variable "xray_sampling_rate_override" {
  type        = number
  description = "Override the default per-env X-Ray sampling rate (1.0/0.5/0.1 for dev/staging/prod)"
  default     = null
}

variable "budget_amount_override" {
  type        = number
  description = "Override the default per-env monthly budget USD ($25/$25/$100 for dev/staging/prod)"
  default     = null
}

variable "budget_notification_email" {
  type        = string
  description = "Email for budget alerts (50%, 80%, 100%, forecasted-100%). Optional."
  default     = null
}

variable "grafana_enabled" {
  type        = bool
  description = "Whether to create Grafana data sources + folder + dashboard. Requires the grafana provider configured at root."
  default     = true
}

variable "grafana_assume_role_arn" {
  type        = string
  description = "IAM role ARN that Grafana Cloud assumes for cross-account access (created by bootstrap-grafana.sh)"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all created resources"
  default     = {}
}
