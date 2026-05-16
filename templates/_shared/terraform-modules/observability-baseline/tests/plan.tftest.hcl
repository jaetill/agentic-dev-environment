# Native `terraform test` for observability-baseline — plan-only, fast.
# Run: cd templates/_shared/terraform-modules/observability-baseline && tofu test

variables {
  project_name = "test-project"
  env          = "dev"
  grafana_enabled = false   # Avoid needing the grafana provider in plan tests
}

mock_provider "aws" {}
mock_provider "grafana" {}

run "applies_dev_retention_default" {
  command = plan
  assert {
    condition     = output.log_retention_days == 7
    error_message = "dev should default to 7-day retention per ADR-0009 §1"
  }
}

run "applies_staging_retention_default" {
  command = plan
  variables {
    env = "staging"
  }
  assert {
    condition     = output.log_retention_days == 30
    error_message = "staging should default to 30-day retention per ADR-0009 §1"
  }
}

run "applies_prod_retention_default" {
  command = plan
  variables {
    env = "prod"
  }
  assert {
    condition     = output.log_retention_days == 90
    error_message = "prod should default to 90-day retention per ADR-0009 §1"
  }
}

run "retention_override_takes_precedence" {
  command = plan
  variables {
    log_retention_days_override = 14
  }
  assert {
    condition     = output.log_retention_days == 14
    error_message = "log_retention_days_override should override the per-env default"
  }
}

run "applies_dev_xray_sampling_default" {
  command = plan
  assert {
    condition     = output.xray_sampling_rate == 1.0
    error_message = "dev should default to 100% X-Ray sampling per ADR-0009 §3"
  }
}

run "applies_prod_xray_sampling_default" {
  command = plan
  variables {
    env = "prod"
  }
  assert {
    condition     = output.xray_sampling_rate == 0.1
    error_message = "prod should default to 10% X-Ray sampling per ADR-0009 §3"
  }
}

run "applies_dev_budget_default" {
  command = plan
  assert {
    condition     = output.budget_amount_usd == 25
    error_message = "dev should default to $25/mo budget per ADR-0007 §6"
  }
}

run "applies_prod_budget_default" {
  command = plan
  variables {
    env = "prod"
  }
  assert {
    condition     = output.budget_amount_usd == 100
    error_message = "prod should default to $100/mo budget per ADR-0007 §6"
  }
}

run "creates_four_budget_alert_thresholds" {
  command = plan
  assert {
    # Module creates: 50%, 80%, 100% actual, 100% forecasted
    condition     = length(aws_budgets_budget.this.notification) == 4
    error_message = "Budget should have 4 notifications per ADR-0007 §6 (50%, 80%, 100% actual, 100% forecasted)"
  }
}

run "rejects_invalid_env" {
  command = plan
  variables {
    env = "production"
  }
  expect_failures = [var.env]
}

run "creates_additional_log_groups" {
  command = plan
  variables {
    additional_log_group_names = [
      "/myproject/custom-log-1",
      "/myproject/custom-log-2",
    ]
  }
  assert {
    condition     = length(aws_cloudwatch_log_group.additional) == 2
    error_message = "additional_log_group_names should produce one log group per element"
  }
}

run "skips_grafana_when_disabled" {
  command = plan
  variables {
    grafana_enabled = false
  }
  assert {
    condition     = length(grafana_data_source.cloudwatch) == 0
    error_message = "grafana_enabled = false should skip Grafana data source creation"
  }
}
