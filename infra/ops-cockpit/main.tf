# Ops Cockpit -- data source + folder. Per ADR-0022.
#
# The GitHub data source (free plugin `grafana-github-datasource`) is the
# single data source for Phase 1: it serves loop run health, fleet
# issue/PR flow, and the human-todo issues. No Sentry data source is
# installed -- the Sentry signal arrives as `source:sentry` GitHub issues
# (ADR-0022, free-mirror decision).
#
# PREREQUISITE: the GitHub data source plugin must be installed on the
# Grafana stack before `tofu apply` can create this resource. See README.

resource "grafana_data_source" "github" {
  type = "grafana-github-datasource"
  name = "fleet-github"

  # Non-secret config. `selectedAuthType` selects personal-access-token auth.
  # NOTE: confirm this jsonData key on the first `tofu plan` -- the plugin's
  # data source settings page is the authoritative source for the exact
  # field name(s). If it is rejected, check the plugin docs for the v-current
  # config schema. The Terraform resource schema itself is correct.
  json_data_encoded = jsonencode({
    selectedAuthType = "personal-access-token"
  })

  # The PAT. Grafana stores secureJsonData encrypted and never renders it
  # back into Terraform state. The source of the PAT now comes from AWS
  # Secrets Manager (ops-cockpit/github-token) via local.github_token (#91)
  # rather than var.github_token -- the value is read at plan time and never
  # written into a *_secret_version, so it stays out of Terraform state on
  # both ends. See secrets.tf and SECRETS-MANAGER-MIGRATION.md.
  secure_json_data_encoded = jsonencode({
    accessToken = local.github_token
  })

  # The Grafana Cloud free-tier service-account token lacks `datasources:write`
  # and `datasources:create` regardless of role label -- verified via
  # `/api/access-control/user/permissions`. The data source was created
  # manually in the UI and imported into state (current UID: `tofu state show grafana_data_source.github`).
  # Ignore drift on the two fields the read-only token can't write through:
  #   - json_data_encoded: Grafana auto-adds `pdcInjected` (Private Data Connect)
  #   - secure_json_data_encoded: Grafana stores the PAT opaquely; TF can't read it back
  # Phase 1b panels reference the data source by name (`fleet-github`), not by
  # any field TF would mutate, so this is safe.
  # WARNING: rotating var.github_token and running `tofu apply` will silently no-op.
  # See README.md "## Rotate credentials" for the three rotation paths (UI is recommended).
  lifecycle {
    ignore_changes = [
      json_data_encoded,
      secure_json_data_encoded,
    ]
  }
}

# Folder that holds the ops cockpit dashboard.
resource "grafana_folder" "ops_cockpit" {
  title = "Ops Cockpit"
}
