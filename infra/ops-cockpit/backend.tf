# Remote state per platform Standard 08 / ADR-0007.
#
# The ops cockpit is a fleet-level singleton -- no env dimension -- so the
# state key is a flat `ops-cockpit/` prefix rather than the usual
# <project>/<env>/ pattern.
#
# Backend bucket bootstrapped 2026-05-10 (same as game-night-pwa et al.).

terraform {
  required_version = ">= 1.6, < 2.0"

  backend "s3" {
    bucket         = "jaetill-tfstate"
    key            = "ops-cockpit/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
