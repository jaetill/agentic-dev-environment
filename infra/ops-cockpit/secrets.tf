# Provider-auth secrets in AWS Secrets Manager. Per ADR-0022 / issue #91.
#
# WHY: #91 (security-review) flagged that the two provider-auth values
# (the Grafana service-account token and the GitHub read-only PAT) were
# supplied as `TF_VAR_*` and therefore captured in Terraform state. The
# real exposure is small -- the S3 backend is encrypted and the values
# are provider-auth, not application data -- but Secrets Manager is the
# hygienic home for them.
#
# THE INVARIANT THIS FILE PRESERVES -- value never in state:
#   We create the secret CONTAINER (aws_secretsmanager_secret) in Terraform
#   but DELIBERATELY do NOT create an aws_secretsmanager_secret_version with
#   a literal value. Putting the plaintext into a *_secret_version would
#   write it straight into config and state -- the exact thing #91 is about.
#   Instead the value is populated OUT OF BAND (aws secretsmanager
#   put-secret-value, run by Jason -- see SECRETS-MANAGER-MIGRATION.md) and
#   READ BACK at plan time via a read-only data source. The data source's
#   value flows into provider/data-source auth but is not persisted by any
#   resource here.
#
# APPLY SEQUENCING (chicken-and-egg): the data sources below fail if the
# secret has no version yet, so this whole file cannot be applied in one
# shot on a fresh secret. The exact ordered bootstrap is in
# SECRETS-MANAGER-MIGRATION.md. Do not `tofu apply` blind.

# ---------------------------------------------------------------------------
# AWS provider. Region matches the rest of the fleet (us-east-2), same as the
# S3 state backend. This provider MUST be configured before the
# aws_secretsmanager_secret_version data sources below can resolve -- Terraform
# does that automatically (data sources depend on their provider), so no
# explicit depends_on is needed; this comment is the only thing required.
provider "aws" {
  region = "us-east-2"
}

# NOTE: the aws required_providers declaration lives in providers.tf — a module
# may declare required_providers only once (this previously duplicated it here
# and broke `tofu`/`terraform` with "Duplicate required providers configuration").

# ---------------------------------------------------------------------------
# Secret CONTAINERS only. No *_secret_version here on purpose (see header).
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "grafana_api_key" {
  name        = "ops-cockpit/grafana-api-key"
  description = "Grafana Cloud service-account token used by the ops-cockpit Grafana provider. Value populated out-of-band (put-secret-value), never via Terraform -- see SECRETS-MANAGER-MIGRATION.md (#91)."

  tags = {
    Project   = "ops-cockpit"
    ManagedBy = "terraform"
    Purpose   = "grafana-provider-auth"
  }
}

resource "aws_secretsmanager_secret" "github_token" {
  name        = "ops-cockpit/github-token"
  description = "Fine-grained read-only GitHub PAT consumed by the ops-cockpit fleet-github Grafana data source. Value populated out-of-band (put-secret-value), never via Terraform -- see SECRETS-MANAGER-MIGRATION.md (#91)."

  tags = {
    Project   = "ops-cockpit"
    ManagedBy = "terraform"
    Purpose   = "grafana-github-datasource-pat"
  }
}

# ---------------------------------------------------------------------------
# Read-only reads of the CURRENT secret value at plan time. These do NOT
# write the value anywhere -- they only feed it into provider/data-source auth.
# Each fails until the secret has at least one version (out-of-band bootstrap).
# ---------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "grafana_api_key" {
  secret_id = aws_secretsmanager_secret.grafana_api_key.id
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = aws_secretsmanager_secret.github_token.id
}

# Intermediate locals so the repointed auth has a single, sensitive-marked
# reference. `sensitive = true` keeps these out of plan output / logs.
locals {
  grafana_api_key = sensitive(data.aws_secretsmanager_secret_version.grafana_api_key.secret_string)
  github_token    = sensitive(data.aws_secretsmanager_secret_version.github_token.secret_string)
}
