# Ops Cockpit dashboard. Per ADR-0022.
#
# Phase 1a (this file as written): a placeholder text panel so the full
# Terraform pipeline — provider auth, S3 backend, folder, dashboard — is
# applyable and verifiable end to end BEFORE any data-bound panels exist.
# Text panels need no data source, so this applies even before the GitHub
# plugin is installed (see README for the -target apply).
#
# Phase 1b: replace the text panel with the real panels (see README,
# "Dashboard panel spec"). Each GitHub-datasource panel's query JSON is
# confirmed against the live data source first, then committed here — the
# dashboard stays 100% Terraform-managed.

resource "grafana_dashboard" "cockpit" {
  folder = grafana_folder.ops_cockpit.id

  config_json = jsonencode({
    uid           = "ops-cockpit"
    title         = "Ops Cockpit — autonomous loop"
    description   = "Fleet loop health, issue/PR flow, and human TODOs. Managed by Terraform per ADR-0022."
    tags          = ["ops", "autonomous-loop"]
    timezone      = "browser"
    schemaVersion = 30
    refresh       = "5m"
    time          = { from = "now-7d", to = "now" }
    panels = [
      {
        id      = 1
        type    = "text"
        title   = "Ops Cockpit — Phase 1a scaffold"
        gridPos = { x = 0, y = 0, w = 24, h = 10 }
        options = {
          mode    = "markdown"
          content = <<-EOT
            ## Scaffold applied — pipeline verified

            Provider auth, S3 state backend, the **fleet-github** data
            source, this folder, and this dashboard are all Terraform-managed.

            **Phase 1b** replaces this panel with:

            - Stat row — Discovered / Promoted / In-flight / Merged-7d
            - Loop runs — recent triage-scan / claude-implementer / ci-health
            - Per-project flow table
            - Human TODOs (`human-todo` issues)
            - Needs you — open P0 / `source:sentry` issues + held PRs
          EOT
        }
      }
    ]
  })
}

output "dashboard_url" {
  description = "Cockpit dashboard URL — open this in a browser once applied."
  value       = "${var.grafana_url}/d/ops-cockpit"
}
