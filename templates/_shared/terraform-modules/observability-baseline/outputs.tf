output "log_retention_days" {
  value       = local.log_retention_days
  description = "The per-env retention setting applied"
}

output "xray_sampling_rule_arn" {
  value       = aws_xray_sampling_rule.this.arn
  description = "ARN of the X-Ray sampling rule"
}

output "xray_sampling_rate" {
  value       = local.xray_sampling_rate
  description = "Effective X-Ray sampling rate"
}

output "budget_arn" {
  value       = aws_budgets_budget.this.arn
  description = "AWS Budget ARN"
}

output "budget_amount_usd" {
  value       = local.budget_amount
  description = "Effective monthly budget in USD"
}

output "budget_alerts_topic_arn" {
  value       = var.budget_notification_email != null ? aws_sns_topic.budget_alerts[0].arn : null
  description = "SNS topic ARN for budget alerts (null if no notification email configured)"
}

output "grafana_cloudwatch_data_source_uid" {
  value       = var.grafana_enabled ? grafana_data_source.cloudwatch[0].uid : null
  description = "Grafana CloudWatch data source UID (null if grafana_enabled = false)"
}

output "grafana_xray_data_source_uid" {
  value       = var.grafana_enabled ? grafana_data_source.xray[0].uid : null
  description = "Grafana X-Ray data source UID (null if grafana_enabled = false)"
}

output "grafana_folder_id" {
  value       = var.grafana_enabled ? grafana_folder.project[0].id : null
  description = "Grafana folder ID for this project's dashboards"
}

output "service_overview_dashboard_uid" {
  value       = var.grafana_enabled ? grafana_dashboard.service_overview[0].uid : null
  description = "UID of the auto-generated Service Overview dashboard"
}
