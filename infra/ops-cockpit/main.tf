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
  # back into Terraform state.
  #
  # SECURITY — NOT a secret-in-state exposure (re: #91, security-review of PR #90).
  # var.github_token is never written to the state file: this data source was
  # created in the Grafana UI and IMPORTED (not `apply`-created), and the
  # `ignore_changes = [secure_json_data_encoded]` below means TF never sends the
  # token, so the attribute stays empty in state. Likewise var.grafana_api_key
  # is only the Grafana provider `auth` (providers.tf) — provider config is not
  # persisted to state. Verified against s3://jaetill-tfstate/ops-cockpit (serial
  # 25): secure_json_data_encoded is empty and no token-prefixed value appears.
  # If this ever moves to an `apply`-created data source, the token WOULD land in
  # state — at that point switch the backend to SSE-KMS (or source via SSM) first.
  secure_json_data_encoded = jsonencode({
    accessToken = var.github_token
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
