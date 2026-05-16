# Test wrapper that consumes the lambda-base module.
# Used by Terratest in tests/integration/lambda_base_test.go.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      TestRun = var.function_name
    }
  }
}

module "under_test" {
  source = "../../.."   # -> templates/_shared/terraform-modules/lambda-base

  function_name           = var.function_name
  env                     = var.env
  handler                 = var.handler
  runtime                 = var.runtime
  deployment_package_path = var.deployment_package_path
  release_version         = var.release_version
}

variable "function_name" { type = string }
variable "env" { type = string }
variable "handler" { type = string }
variable "runtime" { type = string }
variable "deployment_package_path" { type = string }
variable "release_version" { type = string }

output "function_name" { value = module.under_test.function_name }
output "log_group_name" { value = module.under_test.log_group_name }
output "api_gateway_url" { value = module.under_test.api_gateway_url }
