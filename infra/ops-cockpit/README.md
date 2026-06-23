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

### 5. Add a GitHub token to the `grafanacloud-infinity` data source

Panel 8 (triage-job stat) and the `latest_triage_run_id` templating variable use the built-in `grafanacloud-infinity` datasource to call `api.github.com`. Without authentication those calls count against GitHub's **60 req/hour unauthenticated limit** — shared with all Grafana Cloud tenants on the same egress IP. Contention can trigger 403s and blank out panel 8, eliminating the primary silent-loop signal (issue #158).

Mitigation: add the same fine-grained read-only PAT (step 1) as a secure HTTP header on the Infinity datasource so its calls use the **5,000 req/hour authenticated limit**. The token is stored encrypted in Grafana Cloud — it does not appear in `dashboard.json` or Terraform state.

Steps:
1. Grafana Cloud → Connections → Data sources → `grafanacloud-infinity`.
2. Settings → **Secure HTTP headers** → **Add**.
3. Header name: `Authorization` · Value: `token <PAT-from-step-1>`.
4. **Save & test**.

This setup is a one-time step, but the header value must be re-entered whenever the PAT is rotated — see 'Rotate credentials' below. The header survives dashboard edits and Terraform applies because it is stored at the data source layer.

### 6. Create the `human-todo` label

In the platform repo, so the cockpit has TODOs to read. You file a TODO by opening an issue with this label.

```
gh label create human-todo --repo jaetill/agentic-dev-environment --color FFA500 --description "Human-authored TODO surfaced on the ops cockpit"
```

## Secrets — where they live (#91)

| Secret | Storage | How Terraform reads it |
|---|---|---|
| Grafana service-account token | **AWS Secrets Manager** `ops-cockpit/grafana-api-key` | `data.aws_secretsmanager_secret_version` (read-only, plan time); value never in TF state. See `secrets.tf`. |
| GitHub read-only PAT | **AWS Secrets Manager** `ops-cockpit/github-token` | same pattern; feeds the `fleet-github` data source `accessToken`. |
| Grafana stack URL | **env var** `TF_VAR_grafana_url` | non-secret; still a plain `var`. |

The two tokens moved out of `TF_VAR_*` (which captured them in state) into
Secrets Manager for #91. The value is **never** written into a Terraform
`*_secret_version` — Terraform owns only the empty container and reads the
out-of-band-populated value. First-time setup and the required ordered
bootstrap apply are in [`SECRETS-MANAGER-MIGRATION.md`](SECRETS-MANAGER-MIGRATION.md).

## Configure & apply

Set the non-secret stack URL as an environment variable (PowerShell):

```powershell
$env:TF_VAR_grafana_url = "https://<stack>.grafana.net"
```

The two tokens come from AWS Secrets Manager (above) — **not** env vars. On a
fresh setup the secrets must be bootstrapped before a full apply will succeed;
follow [`SECRETS-MANAGER-MIGRATION.md`](SECRETS-MANAGER-MIGRATION.md). Once the
secrets carry values:

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

## Rotate credentials

The PAT in step 1 has an expiry. When you rotate it, `tofu apply` with the new `TF_VAR_github_token` value **will silently no-op** — `main.tf` has `lifecycle { ignore_changes = [secure_json_data_encoded] }` to keep the read-only Grafana SA token from 403-ing on update (see step 2 caveat), and that block also blocks the rotated value from flowing through.

Three rotation paths for `fleet-github`, in increasing order of effort:

1. **UI rotation (recommended for now).** Grafana Cloud → Connections → Data sources → `fleet-github` → edit → paste new PAT into the Access Token field → Save & test. Done. State will drift by one field (`secure_json_data_encoded`); ignore — that's the design.
2. **Direct API.** `curl -X PUT -H "Authorization: Bearer <SA token>" -H "Content-Type: application/json" -d '{"secureJsonData":{"accessToken":"<new PAT>"}}' https://jaetill.grafana.net/api/datasources/uid/<uid>`. Same caveat as step 2 of prereqs — if the SA token lacks `datasources:write` you'll get 403 and have to fall back to UI.
3. **Re-import.** Only if the data source needs to be rebuilt from scratch. `tofu state rm grafana_data_source.github`, recreate in UI (or anywhere with `datasources:create`), `tofu import grafana_data_source.github <new uid>`. Heavyweight; reserve for when the resource itself is broken, not for routine rotation.

**Also required — every rotation:** update the `grafanacloud-infinity` header. Grafana Cloud → Connections → Data sources → `grafanacloud-infinity` → Settings → **Secure HTTP headers** → edit the `Authorization` row → paste `token <new-PAT>` → **Save & test**. Skipping this step leaves panel 8 (triage-job stat) authenticating with a stale token, silently re-exposing the shared-egress-IP 403 risk (issue #158). Verify: panel 8 should render a green/red value (not blank) after saving.

**Also required — every rotation:** update the `infinity-github-auth` datasource (UID `afo51rbbobke8a`, added in PR #233, used by all 8 issue-flow bar panels). It is **UI-managed and absent from Terraform**, so `tofu apply` will not touch it. Grafana Cloud → Connections → Data sources → `infinity-github-auth` → Settings → **Auth** → **Bearer Token** → paste the new PAT → **Save & test**. Skipping this leaves all 8 issue-flow bars dark on rotation (expired PAT → 401 from GitHub GraphQL). Verify: the issue-flow bar panels return data (not blank) after saving. **If this datasource is ever deleted and recreated** (its UID is environment-specific), the new UID must be patched into `dashboard.json` everywhere `afo51rbbobke8a` appears — there is otherwise no Terraform link to update it automatically (#234).

The Grafana SA token (step 2 of prereqs) rotates without TF involvement — it's read by the provider from the env var each apply, so a fresh value just works.

## Files

| File | Purpose |
|---|---|
| `backend.tf` | S3 remote state |
| `providers.tf` | Grafana provider + auth (auth from Secrets Manager) |
| `secrets.tf` | AWS provider + Secrets Manager containers + read-only value reads (#91) |
| `variables.tf` | Inputs (URL only; the two token vars are deprecated, see #91) |
| `main.tf` | GitHub data source + folder |
| `dashboard.tf` | The dashboard (Phase 1a placeholder → Phase 1b panels) |
| `terraform.tfvars.example` | Documents the inputs; real `*.tfvars` is gitignored |
| `SECRETS-MANAGER-MIGRATION.md` | Ordered bootstrap apply + rollback for the #91 secrets move |
