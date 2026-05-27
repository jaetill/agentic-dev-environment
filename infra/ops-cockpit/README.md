# Ops Cockpit — Terraform

Grafana Cloud dashboard for the autonomous loop. Decision and rationale: [ADR-0022](../../docs/adr/0022-ops-cockpit-dashboard-host.md).

## What this is

A self-refreshing operations cockpit — loop run health, fleet issue/PR flow, and human TODOs in one Grafana dashboard, with no Claude or human in the refresh path. It replaces the hand-refreshed `autonomous-loop-portfolio-flow` Cowork artifact.

One data source does all of Phase 1: the free `grafana-github-datasource` plugin. The Sentry signal arrives as `source:sentry` GitHub issues (ADR-0022 free-mirror decision) — no Sentry data source is installed.

## Prerequisites (one-time — these need Jason)

Terraform cannot do these four; they need your GitHub and Grafana accounts.

### 1. GitHub fine-grained PAT (read-only)

github.com → Settings → Developer settings → Fine-grained tokens → Generate new token.

- **Resource owner:** `jaetill`
- **Repository access:** Only select repositories → the 8 fleet repos (agentic-dev-environment, game-night-pwa, meal-planner, ai-teacher, jaetill-portal, splendor, draft, carto).
- **Repository permissions:** Actions → Read-only · Issues → Read-only · Pull requests → Read-only · Contents → Read-only · Metadata → Read-only (auto). **Nothing else — no write, no admin.**
- Set an expiry and a calendar reminder to rotate.

### 2. Grafana service-account token

Grafana Cloud → Administration → Users and access → Service accounts → Add service account.

- **Role:** Admin. Editor is not enough — `tofu apply` will 403 on `datasources:create`. On Grafana Cloud free tier, even Admin service-account tokens can be missing `datasources:create` / `datasources:write` (verify via `/api/access-control/user/permissions`). If they are, create the data source manually in the UI (see step 4) and `tofu import` it into state; the resource block below uses `lifecycle { ignore_changes }` on the fields the token can't write through.
- Add a token on that service account; copy it.

### 3. Grafana stack URL

`https://<your-stack>.grafana.net` — visible in your Grafana Cloud portal.

### 4. Install the GitHub data source plugin

Grafana Cloud → Administration → Plugins and data → Plugins → search "GitHub" → install **GitHub** (the data source, by Grafana Labs — *not* the "GitHub" Integration, which is a different product surfaced under Connections → Add new connection). One-time; required before `tofu apply` can create the data source.

If the service-account token can't create data sources (see step 2 caveat), also create the data source itself here: Connections → Data sources → Add data source → GitHub → name it `fleet-github`, paste the PAT from step 1, Save & test → copy the UID from the URL, then `tofu import grafana_data_source.github <uid>` to bring it under TF management.

### 5. Create the `human-todo` label

In the platform repo, so the cockpit has TODOs to read. You file a TODO by opening an issue with this label.

```
gh label create human-todo --repo jaetill/agentic-dev-environment --color FFA500 --description "Human-authored TODO surfaced on the ops cockpit"
```

## Configure & apply

Set the three inputs as environment variables (PowerShell) — keeps the two secrets off disk in this public repo:

```powershell
$env:TF_VAR_grafana_url     = "https://<stack>.grafana.net"
$env:TF_VAR_grafana_api_key = "<grafana service-account token>"
$env:TF_VAR_github_token    = "<fine-grained read-only PAT>"
```

Then:

```powershell
tofu init
tofu apply
```

State lives at `s3://jaetill-tfstate/ops-cockpit/terraform.tfstate` (lock table `terraform-state-lock`, `us-east-2`).

To verify the pipeline **before** the GitHub plugin is installed, apply just the folder + dashboard:

```powershell
tofu apply -target=grafana_folder.ops_cockpit -target=grafana_dashboard.cockpit
```

`tofu apply` prints `dashboard_url` — open it to see the cockpit.

## Dashboard panel spec (Phase 1b)

The dashboard currently renders one placeholder text panel. Phase 1b replaces it with:

| Panel | Type | GitHub query |
|---|---|---|
| Discovered / Promoted / In-flight / Merged-7d | stat row | Issues by label, PRs by author |
| Loop runs — triage-scan / claude-implementer / ci-health | table or state-timeline | Workflow Runs |
| Per-project flow | table | Issues + PRs grouped by repo |
| Human TODOs | table | Issues, label `human-todo`, platform repo |
| Needs you | table | open `incident:p0` + `source:sentry` issues, held implementer PRs |

**Build workflow.** With the data source live, build one GitHub-datasource panel in the Grafana UI to confirm the exact query JSON the plugin emits, copy that JSON into `dashboard.tf`, and re-apply. The UI is used only to discover the query schema — the dashboard itself stays Terraform-managed (ADR-0022, "Terraform from the start").

## Files

| File | Purpose |
|---|---|
| `backend.tf` | S3 remote state |
| `providers.tf` | Grafana provider + auth |
| `variables.tf` | Inputs (1 URL, 2 secrets) |
| `main.tf` | GitHub data source + folder |
| `dashboard.tf` | The dashboard (Phase 1a placeholder → Phase 1b panels) |
| `terraform.tfvars.example` | Documents the inputs; real `*.tfvars` is gitignored |
