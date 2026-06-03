# Ops Cockpit dashboard. Per ADR-0022.
#
# The dashboard definition lives in the sibling file dashboard.json, exported
# from the live Grafana stack (jaetill.grafana.net, dashboard UID ops-cockpit).
# That file is the Terraform-managed source of truth: the dashboard is edited
# live during iteration (Chrome + /api/dashboards/db), then re-exported to
# dashboard.json so `tofu apply` REPRODUCES the live dashboard instead of
# reverting it. Phases 1a (placeholder) and 1b (inline panels) are retired —
# the panel set is now large enough (80 panels) that an external JSON file is
# cleaner than an inline jsonencode(...).
#
# Re-export procedure (also in HANDOFF.md):
#   1. GET /api/dashboards/uid/ops-cockpit  -> {dashboard, meta} (v1 schema).
#   2. From .dashboard, delete `id` and `version` (the grafana_dashboard
#      provider manages both); keep `uid = "ops-cockpit"`, title, panels, etc.
#   3. Write that object to dashboard.json (UTF-8, no BOM).
# The JSON embeds datasource UIDs ffnagb7t8j5s0e (fleet-github, grafana-github-
# datasource) and grafanacloud-infinity (Infinity, panel 8 job-level query).
# Both are stable; keep them. The templating var `latest_triage_run_id` must be
# preserved (the server-side render endpoint does not refresh variables).

resource "grafana_dashboard" "cockpit" {
  folder      = grafana_folder.ops_cockpit.id
  config_json = file("${path.module}/dashboard.json")

  # config_json embeds the fleet-github datasource UID, so the dashboard must
  # apply after that data source exists. There is no Terraform reference inside
  # the JSON to create the dependency implicitly, so make it explicit.
  depends_on = [grafana_data_source.github]
}

output "dashboard_url" {
  description = "Cockpit dashboard URL — open this in a browser once applied."
  value       = "${var.grafana_url}/d/ops-cockpit"
}
