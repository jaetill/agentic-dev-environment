variable "grafana_url" {
  type        = string
  description = "Grafana Cloud stack URL, e.g. https://<stack>.grafana.net"
}

# DEPRECATED (#91): grafana_api_key and github_token are no longer wired into
# the providers / data sources. Their values now come from AWS Secrets Manager
# (ops-cockpit/grafana-api-key, ops-cockpit/github-token) via the data sources
# in secrets.tf -- see SECRETS-MANAGER-MIGRATION.md. The variables are kept
# (with default = null) so any stale `TF_VAR_*` env var or tfvars line does not
# error during the migration window. Remove them once the migration is
# confirmed and the env vars are retired; if removed, also sweep README.md and
# terraform.tfvars.example.

variable "grafana_api_key" {
  type        = string
  description = "DEPRECATED (#91): moved to AWS Secrets Manager (ops-cockpit/grafana-api-key). No longer wired into the grafana provider. Kept only to avoid erroring on a stale TF_VAR_grafana_api_key during migration."
  sensitive   = true
  default     = null
}

variable "github_token" {
  type        = string
  description = "DEPRECATED (#91): moved to AWS Secrets Manager (ops-cockpit/github-token). No longer wired into the fleet-github data source. Kept only to avoid erroring on a stale TF_VAR_github_token during migration."
  sensitive   = true
  default     = null
}
