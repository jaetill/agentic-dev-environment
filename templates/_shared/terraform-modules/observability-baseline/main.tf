# observability-baseline — Per-env observability infrastructure.
# Per ADR-0009 — CloudWatch Log Groups (with retention), X-Ray sampling rules,
# AWS Budgets, Grafana CloudWatch + X-Ray data sources.
#
# Note: Grafana data source resources require the `grafana/grafana` provider
# configured at the root level (calling project's providers.tf).

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    grafana = {
      source                = "grafana/grafana"
      version               = "~> 3.0"
      configuration_aliases = [grafana]
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Per-env log retention defaults per ADR-0009 §1
  retention_default_by_env = {
    dev     = 7
    staging = 30
    prod    = 90
  }
  log_retention_days = coalesce(var.log_retention_days_override, lookup(local.retention_default_by_env, var.env, 7))

  # Per-env X-Ray sampling rate per ADR-0009 §3
  sampling_rate_by_env = {
    dev     = 1.0  # 100% in dev for full observability while developing
    staging = 0.5  # 50% in staging
    prod    = 0.1  # 10% in prod (cost-aware)
  }
  xray_sampling_rate = coalesce(var.xray_sampling_rate_override, lookup(local.sampling_rate_by_env, var.env, 0.1))

  # Per-env AWS Budgets defaults per ADR-0007 §6
  budget_default_by_env = {
    dev     = 25
    staging = 25
    prod    = 100
  }
  budget_amount = coalesce(var.budget_amount_override, lookup(local.budget_default_by_env, var.env, 25))

  tags = merge(var.tags, {
    Project   = var.project_name
    Env       = var.env
    ManagedBy = "OpenTofu"
  })
}

# ============================================================
# CloudWatch Log Groups (per service)
# ============================================================
# The lambda-base module creates its own log group; this is for additional
# project-defined log groups (custom application logs, etc.).

resource "aws_cloudwatch_log_group" "additional" {
  for_each          = toset(var.additional_log_group_names)
  name              = each.value
  retention_in_days = local.log_retention_days
  tags              = local.tags
}

# ============================================================
# X-Ray sampling rule (per env)
# ============================================================

resource "aws_xray_sampling_rule" "this" {
  rule_name      = "${var.project_name}-${var.env}"
  priority       = 100
  fixed_rate     = local.xray_sampling_rate
  reservoir_size = 1
  service_name   = "${var.project_name}-${var.env}*"
  service_type   = "*"
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  resource_arn   = "*"
  version        = 1
}

# ============================================================
# AWS Budget per env (per ADR-0007 §6)
# ============================================================

resource "aws_sns_topic" "budget_alerts" {
  count = var.budget_notification_email != null ? 1 : 0
  name  = "${var.project_name}-${var.env}-budget-alerts"
  tags  = local.tags
}

resource "aws_sns_topic_subscription" "budget_email" {
  count     = var.budget_notification_email != null ? 1 : 0
  topic_arn = aws_sns_topic.budget_alerts[0].arn
  protocol  = "email"
  endpoint  = var.budget_notification_email
}

resource "aws_budgets_budget" "this" {
  name              = "${var.project_name}-${var.env}"
  budget_type       = "COST"
  limit_amount      = tostring(local.budget_amount)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  # Filter to this project/env's resources via cost allocation tags
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_name}", "user:Env$${var.env}"]
  }

  # Alert thresholds per ADR-0007 §6: 50% inform, 80% alert, 100% page
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_email != null ? [var.budget_notification_email] : []
    subscriber_sns_topic_arns  = var.budget_notification_email != null ? [aws_sns_topic.budget_alerts[0].arn] : []
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_email != null ? [var.budget_notification_email] : []
    subscriber_sns_topic_arns  = var.budget_notification_email != null ? [aws_sns_topic.budget_alerts[0].arn] : []
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_email != null ? [var.budget_notification_email] : []
    subscriber_sns_topic_arns  = var.budget_notification_email != null ? [aws_sns_topic.budget_alerts[0].arn] : []
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_email != null ? [var.budget_notification_email] : []
    subscriber_sns_topic_arns  = var.budget_notification_email != null ? [aws_sns_topic.budget_alerts[0].arn] : []
  }
}

# ============================================================
# Grafana data sources (queries CloudWatch + X-Ray cross-account per ADR-0009 §5)
# ============================================================

resource "grafana_data_source" "cloudwatch" {
  count    = var.grafana_enabled ? 1 : 0
  provider = grafana

  type        = "cloudwatch"
  name        = "${var.project_name}-${var.env}-cloudwatch"
  is_default  = false

  json_data_encoded = jsonencode({
    authType      = "default"
    defaultRegion = data.aws_region.current.name
    assumeRoleArn = var.grafana_assume_role_arn
  })
}

resource "grafana_data_source" "xray" {
  count    = var.grafana_enabled ? 1 : 0
  provider = grafana

  type        = "grafana-x-ray-datasource"
  name        = "${var.project_name}-${var.env}-xray"
  is_default  = false

  json_data_encoded = jsonencode({
    authType      = "default"
    defaultRegion = data.aws_region.current.name
    assumeRoleArn = var.grafana_assume_role_arn
  })
}

# Default folder for this project's dashboards
resource "grafana_folder" "project" {
  count    = var.grafana_enabled ? 1 : 0
  provider = grafana
  title    = "${var.project_name}-${var.env}"
}

# Starter "Service Overview" dashboard per ADR-0009 §5
resource "grafana_dashboard" "service_overview" {
  count    = var.grafana_enabled ? 1 : 0
  provider = grafana
  folder   = grafana_folder.project[0].id

  config_json = jsonencode({
    title       = "${var.project_name} ${var.env} — Service Overview"
    description = "Auto-generated by observability-baseline module per ADR-0009"
    tags        = [var.project_name, var.env]
    timezone    = "browser"
    refresh     = "1m"
    schemaVersion = 30
    panels = [
      {
        id    = 1
        title = "Request rate (per minute)"
        type  = "timeseries"
        gridPos = { x = 0, y = 0, w = 12, h = 8 }
        targets = [{
          datasource = { type = "cloudwatch", uid = grafana_data_source.cloudwatch[0].uid }
          namespace  = "AWS/ApiGateway"
          metricName = "Count"
          statistic  = "Sum"
          dimensions = { ApiId = "*" }
          period     = "60"
        }]
      },
      {
        id    = 2
        title = "5xx error rate"
        type  = "timeseries"
        gridPos = { x = 12, y = 0, w = 12, h = 8 }
        targets = [{
          datasource = { type = "cloudwatch", uid = grafana_data_source.cloudwatch[0].uid }
          namespace  = "AWS/ApiGateway"
          metricName = "5XXError"
          statistic  = "Sum"
          dimensions = { ApiId = "*" }
          period     = "60"
        }]
      },
      {
        id    = 3
        title = "p99 latency"
        type  = "timeseries"
        gridPos = { x = 0, y = 8, w = 12, h = 8 }
        targets = [{
          datasource = { type = "cloudwatch", uid = grafana_data_source.cloudwatch[0].uid }
          namespace  = "AWS/ApiGateway"
          metricName = "Latency"
          statistic  = "p99"
          dimensions = { ApiId = "*" }
          period     = "60"
        }]
      },
      {
        id    = 4
        title = "Lambda concurrent executions"
        type  = "timeseries"
        gridPos = { x = 12, y = 8, w = 12, h = 8 }
        targets = [{
          datasource = { type = "cloudwatch", uid = grafana_data_source.cloudwatch[0].uid }
          namespace  = "AWS/Lambda"
          metricName = "ConcurrentExecutions"
          statistic  = "Maximum"
          dimensions = { FunctionName = "${var.project_name}-${var.env}*" }
          period     = "60"
        }]
      }
    ]
  })
}
