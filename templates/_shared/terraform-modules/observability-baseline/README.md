# Module: observability-baseline

Per-env observability infrastructure per [ADR-0009](../../../../docs/adr/0009-observability.md).

## What it creates

- **CloudWatch Log Groups** for any project-specified additional log group names, with env-appropriate retention (7d/30d/90d for dev/staging/prod per ADR-0009 §1)
- **X-Ray sampling rule** with per-env defaults (100% / 50% / 10% for dev/staging/prod)
- **AWS Budget** with 4 alert thresholds (50% inform, 80% alert, 100% actual, 100% forecasted) per ADR-0007 §6
- **SNS topic + email subscription** for budget alerts (optional)
- **Grafana CloudWatch + X-Ray data sources** (cross-account; requires `bootstrap-grafana.sh` already run)
- **Grafana folder** for the project's dashboards
- **Starter "Service Overview" Grafana dashboard** with 4 panels: request rate, 5xx error rate, p99 latency, Lambda concurrent executions (per ADR-0009 §5)

## Usage

```hcl
module "observability" {
  source = "git::https://github.com/<you>/agentic-dev-environment.git//templates/_shared/terraform-modules/observability-baseline?ref=modules/v1.0.0"

  providers = {
    grafana = grafana
  }

  project_name = var.project_name
  env          = var.env

  budget_notification_email = "alerts@example.com"

  grafana_assume_role_arn = "arn:aws:iam::123456789012:role/grafana-cloud-cross-account"
}
```

The calling project must configure both `aws` and `grafana` providers in its root `providers.tf`:

```hcl
provider "aws" {
  region = var.aws_region
}

provider "grafana" {
  url  = var.grafana_url      # e.g., https://your-org.grafana.net
  auth = var.grafana_api_key  # from 1Password
}
```

## Inputs (key)

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | string | (required) | |
| `env` | string | (required) | dev / staging / prod |
| `log_retention_days_override` | number | `null` | Override per-env default (7/30/90) |
| `additional_log_group_names` | list(string) | `[]` | Project-specific log groups |
| `xray_sampling_rate_override` | number | `null` | Override per-env default (1.0/0.5/0.1) |
| `budget_amount_override` | number | `null` | Override per-env default ($25/$25/$100) |
| `budget_notification_email` | string | `null` | Optional alert recipient |
| `grafana_enabled` | bool | `true` | Set false to skip Grafana resources |
| `grafana_assume_role_arn` | string | `null` | IAM role Grafana Cloud assumes (from `bootstrap-grafana.sh`) |
| `tags` | map(string) | `{}` | Tags |

## Outputs (key)

| Output | Description |
|---|---|
| `log_retention_days` | Effective retention applied |
| `xray_sampling_rate` | Effective sampling rate |
| `budget_arn` | AWS Budget ARN |
| `grafana_cloudwatch_data_source_uid` | For referencing in additional dashboards |
| `service_overview_dashboard_uid` | UID of the auto-generated dashboard |

## Defaults summary

| Concern | dev | staging | prod | Source |
|---|---|---|---|---|
| Log retention | 7d | 30d | 90d | ADR-0009 §1 |
| X-Ray sampling rate | 100% | 50% | 10% | ADR-0009 §3 |
| Monthly budget | $25 | $25 | $100 | ADR-0007 §6 |
| Budget alert thresholds | 50%, 80%, 100% actual, 100% forecasted | same | same | ADR-0007 §6 |

## Bootstrap dependency

The Grafana data sources use `grafana_assume_role_arn` to query CloudWatch cross-account. That role is created by `scripts/bootstrap-grafana.sh` (one-time per AWS account). If you haven't run it, set `grafana_enabled = false` until you do.

## What's NOT in this module

- **Per-service Lambda log groups** — those are created by the `lambda-base` module's own resources.
- **CloudWatch Alarms** — Grafana Alerting is the primary alerting per ADR-0009 §6. CloudWatch Alarms for AWS-billing-tier alerts are in this budget config.
- **Custom dashboards beyond Service Overview** — projects extend by referencing `grafana_data_source.cloudwatch[0].uid` from this module's outputs.

## Notes

- **Budget cost-filter tags** — the budget filters by `Project` + `Env` resource tags, so tagging discipline matters. Both `lambda-base` and this module apply those tags automatically; project-specific resources should too.
- **First budget month.** AWS Budgets requires a `time_period_start` in the past to start tracking. The module sets it to `2026-01-01`; for projects starting later, override if you want; the budget tracks from the start month forward regardless.
- **Grafana provider configuration_alias.** This module declares `configuration_aliases = [grafana]` so the calling project can pass its grafana provider through `providers = { grafana = grafana }`. This is how Terraform handles passing-providers-to-modules.
