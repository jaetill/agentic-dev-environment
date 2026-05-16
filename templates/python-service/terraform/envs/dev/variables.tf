variable "project_name" {
  type        = string
  description = "Project name (e.g., game-night)"
  default     = "{{project_name}}"
}

variable "aws_region" {
  type        = string
  description = "AWS region for this environment"
  default     = "{{aws_region}}"
}

variable "grafana_url" {
  type        = string
  description = "Grafana Cloud URL"
}

variable "grafana_api_key" {
  type        = string
  description = "Grafana Cloud API key"
  sensitive   = true
}
