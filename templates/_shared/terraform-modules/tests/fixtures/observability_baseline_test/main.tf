# Test wrapper for observability-baseline.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      TestRun = var.project_name
    }
  }
}

# Grafana provider — configured but not used when grafana_enabled = false
provider "grafana" {
  url  = "https://example.grafana.test"
  auth = "fake-key-not-used-in-test"
}

module "under_test" {
  source = "../../.."   # -> templates/_shared/terraform-modules/observability-baseline

  providers = {
    grafana = grafana
  }

  project_name               = var.project_name
  env                        = var.env
  grafana_enabled            = var.grafana_enabled
  additional_log_group_names = var.additional_log_group_names
}

variable "project_name" { type = string }
variable "env" { type = string }
variable "grafana_enabled" {
  type    = bool
  default = false
}
variable "additional_log_group_names" {
  type    = list(string)
  default = []
}

output "log_retention_days" { value = module.under_test.log_retention_days }
output "xray_sampling_rate" { value = module.under_test.xray_sampling_rate }
output "budget_amount_usd" { value = module.under_test.budget_amount_usd }
