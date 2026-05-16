terraform {
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
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Env       = "dev"
      ManagedBy = "OpenTofu"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_api_key
}
