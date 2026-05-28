# Ops Cockpit — Phase 1b handoff

**Status:** Paused 2026-05-28 mid-Phase-1b. Dashboard live at `https://jaetill.grafana.net/d/ops-cockpit`, version 27 (saved via API). v25–v27 added a single supervisor panel for the triage job's actual conclusion; the rest of the Phase 1b scope below is still pending.

Use this doc to resume. The companion memory note is [`reference_grafana_cockpit_patterns`](#) — it has the workflow and gotchas; this doc has the project-specific state.

## Where the design landed

The original ADR-0022 panel spec was an *operator* view (Discovered / Promoted / In-flight / Merged funnel). During build Jason course-corrected to a *supervisor* view — what someone overseeing the autonomous loop actually wants to see:

- **Fleet at a glance** — per-repo health, by-severity breakdown
- **Trends** — same axes over time
- **Team liveness** — is triage-scan running, is ci-health touching all repos, are process-flaw issues being filed *and* addressed

Implication: graphs/charts primary, tables for drill-down only.

## What's actually built (dashboard v24)

| Panel | id | Type | Query scope | Notes |
|---|---|---|---|---|
| Platform open issues | 3 | stat | `agentic-dev-environment` | `timeFrom: 5y` override |
| High/critical (platform) | 4 | stat | platform | `timeFrom: 5y` |
| Process-flaw open | 5 | stat | platform | `timeFrom: 5y` |
| Platform activity (7d) | 6 | stat | platform | no override (7d intentional) |
| Human TODOs | 2 | table | platform | drill-down |
| Loop runs — triage-scan heartbeat | 7 | table | `Workflow_Runs` on `triage-scan.yml` | drill-down |
| Open issues per repo (8 panels) | 100-107 | stat | one per fleet repo | row of 8 stats at y=23 |
| Latest triage-scan: triage job | 8 | stat | Infinity → `/actions/runs/${latest_triage_run_id}/jobs`, filtered to `name=triage` | added v25 in response to the 2026-05-26..28 silent-loop incident; surfaces the `triage` job conclusion (red `skipped` when the cron drifted out of window, green `ran` when the window caught a fire). Uses templating variable `latest_triage_run_id` (Infinity query, `refresh: 1`, hardcoded `current` as render-endpoint fallback) |

Total 15 panels.

## What's not built yet (the original Phase 1b scope plus the supervisor pivot)

1. **Row 5 — Workflow state timeline / team-liveness view.** Show triage-scan / claude-implementer / ci-health activity across all 8 repos. The current Loop runs panel only shows triage-scan on the platform repo. Pattern: 8 small panels (one per repo), each showing the latest ci-health conclusion and timestamp, OR a state-timeline if the data shape allows.
2. **Trends row.** Time series of issues opened / closed per repo, optionally faceted by severity. Hard part: computing issue-counts-over-time from a flat issue list. Defer to Phase 1c unless a clean transform path appears.
3. **Per-repo severity breakdown.** Currently the per-repo stats are total open. Stacked horizontal bar chart with one bar per repo, stacked by severity tier, would answer "which repo has the most high-severity work" in one glance. **Caveat:** during Phase 1b we discovered that field overrides break multi-series stat panels — bar chart with similar overrides will likely have the same problem. Plan: 8 separate stat panels per severity per repo (heavy) OR a table with one row per repo and severity columns (works, but Jason wants graphs not tables — accept as a follow-up).

## How to resume

1. **Open Claude in Chrome on the dashboard.** `https://jaetill.grafana.net/d/ops-cockpit`. The Chrome+API workflow in [`reference_grafana_cockpit_patterns`](#) is much faster than JSON Model editor.
2. **Check current state.** `GET /api/dashboards/uid/ops-cockpit` returns v1-schema dashboard. If `meta.version` is still 24, nothing changed since pause; if higher, someone (Jason) edited via UI — diff before proceeding.
3. **Build Row 5 first.** It's the most-asked-for and the most tractable. Use the 8-single-panel pattern (proven on row 4). Each panel: query `Workflow_Runs` for one repo, filter to ci-health, show latest conclusion as colored stat. Layout: row of 8 at next available y.
4. **Verify each change via render endpoint.** `GET /render/d-solo/ops-cockpit?panelId=N&width=400&height=200` returns a server-side PNG. Screenshot it via Claude in Chrome's `computer` tool. Do NOT rely on Grafana's UI to render in the automation tab — panels often don't mount.
5. **When all panels render correctly,** fetch the dashboard JSON, save it to `dashboard.tf` as the `config_json`. Convert from v1 (API) to whatever the Terraform Grafana provider expects (it accepts both).
6. **Ship Phase 1b PR.** ADR-0022 already covers the design. Issue #98 (cockpit hygiene cleanup) bundles in naturally — encoding-corruption fix on backend.tf/main.tf comments, runbook forward reference, in-code rotation warning, missing newline. All in one PR.

## Gotchas — read before resuming

- **Dashboard time range filters everything.** Default "Last 7 days" makes the GitHub plugin only return issues updated/created in that window. Panels showing current state need `timeFrom: "5y"` override. Rows 1 and 4 have this; new panels need it too if they want current state.
- **Field overrides reliably break multi-series stat panels** on this Grafana version. `byFrameRefID` matcher + displayName → "No data." `displayName: "${__series.name}"` → "No data." The workaround that always works: one panel per series, panel title is the label.
- **GitHub search ANDs `repo:` qualifiers.** Multi-repo aggregation in a single query is impossible. Use N queries (one per repo) + transformations, or N panels.
- **The Grafana Cloud free-tier service-account token can't write data sources.** The data source was created in the UI and imported to TF state (UID `ffnagb7t8j5s0e`); `main.tf` has `lifecycle.ignore_changes` to prevent the read-only token from 403-ing on update. PAT rotation requires UI (documented in README's "Rotate credentials" section).

## Status of associated work

- **ADR-0022:** merged in PR #90.
- **PR #90 reviewer findings:** mediums #91 (secrets in TF state) and security-review-M1 accepted with mitigation; #92, #93 (PAT rotation) closed by README update; #94 (no CI for IaC) and #98 (hygiene bundle) open as follow-ups.
- **Plugin install / SA token / PAT:** all set up correctly. PAT is the `gh` CLI's OAuth token (`gho_...`); switching to a dedicated classic PAT (`repo` + `read:user`) is recommended security hygiene but not blocking. README amendment for this is part of #98.
- **infra/ops-cockpit/ TF files:** still at v24-of-dashboard. v25-v27 (the triage-job stat) are live in Grafana but NOT yet exported to `dashboard.tf`. A `tofu apply` here would revert the panel. Export is a Phase 1b follow-up — bundle with the rest of the Phase 1b panel work.

## Triage-job stat panel (v25-v27, 2026-05-28)

Why: GitHub Actions cron delivered every fire outside the America/Chicago windows for 2026-05-26..28, so the `triage` job inside each run skipped — but the Loop runs table read green at the run-conclusion level. PR #99 shifted the cron bands earlier to absorb the drift, and this panel makes the silent-skip case visible.

How:
- Templating variable `latest_triage_run_id` — Infinity, `refresh: 1`, queries `https://api.github.com/repos/jaetill/agentic-dev-environment/actions/workflows/triage-scan.yml/runs?per_page=1&event=schedule`, selector `workflow_runs[].id → __value`. `current` is hardcoded as a fallback so the render endpoint still works (server-side renderer does not refresh variables).
- Panel 8 — stat, Infinity query against `/actions/runs/${latest_triage_run_id}/jobs`, transformations `filterByValue name=triage` then `organize` to rename `conclusion → "triage job"`. Value mappings turn `skipped/failure/cancelled` red and `success` green. `colorMode: background`, `textMode: value`.

Gotchas observed during build:
- `textMode: value_and_name` rendered a blank value box. Switched to `textMode: value`.
- The Grafana GitHub data source plugin does NOT have a Jobs query type — `Workflow_Runs` exposes only run-level fields. Job-level data requires Infinity hitting the REST API directly.
- Infinity computed columns with arithmetic expressions returned `null` against the `parser: backend` mode — left for a Phase 1c look if computed in-panel becomes necessary.
- `agentic-dev-environment` is a public repo so unauthenticated Infinity calls work within GitHub's 60/h anon rate limit; if rate limiting becomes a problem, configure Infinity with the same fine-grained PAT used by the GitHub data source.

## Side note for the resuming agent

Jason mentioned he may shift to the ProjectionLab finance sync (spec at `docs/verification/projectionlab-finance-sync-implementation-spec.md`, from 2026-05-17). That's a separate project — don't conflate the two. If Jason returns to the cockpit, this doc has what you need.
