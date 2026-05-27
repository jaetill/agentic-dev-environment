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

# Auth: both values are sensitive and supplied via TF_VAR_* env vars so
# they stay out of this (public) repo and out of the state file.
#   $env:TF_VAR_grafana_url     = "https://<stack>.grafana.net"
#   $env:TF_VAR_grafana_api_key = "<grafana service-account token>"
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_api_key
}
