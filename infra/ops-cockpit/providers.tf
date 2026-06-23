# Grafana provider — manages the ops cockpit's data source, folder, and
# dashboard in Grafana Cloud. Per ADR-0022.
#
# Version pinned to match the platform's observability-baseline module
# (templates/_shared/terraform-modules/observability-baseline).

terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# Auth (#91): the service-account token now lives in AWS Secrets Manager
# (ops-cockpit/grafana-api-key) and is read at plan time -- the value never
# enters Terraform config or state via a *_secret_version. See secrets.tf
# and SECRETS-MANAGER-MIGRATION.md for the value-never-in-state pattern and
# the required ordered bootstrap apply.
#   - url  still comes from TF_VAR_grafana_url (non-secret stack URL).
#   - auth now reads local.grafana_api_key (Secrets Manager), NOT var.grafana_api_key.
provider "grafana" {
  url  = var.grafana_url
  auth = local.grafana_api_key
}
