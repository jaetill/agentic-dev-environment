# ADR-0022: Operations cockpit — host for the autonomous-loop dashboard

- **Status:** Accepted
- **Date:** 2026-05-25
- **Deciders:** Jason
- **Tags:** observability, grafana, ops, ai-workflows

> **Format:** MADR 4.x per `docs/adr/template.md`.

## Context and Problem Statement

The autonomous loop's status lives in a Cowork artifact (`autonomous-loop-portfolio-flow`) that only refreshes when Claude runs `gh` by hand. It went stale inside a single conversation — built 2026-05-24, already a day old by 2026-05-25.

We want a **permanent, self-refreshing operations cockpit** that shows, in one pane, with no Claude or human in the refresh path: GitHub Actions / loop run health, fleet issue & PR flow, Sentry errors, and human-generated TODOs. **Where should it live?**

## Decision Drivers

- **Self-refreshing, zero-touch.** The refresh path must not include Claude or a manual step. This is the core ask.
- **One pane, three sources.** GitHub Actions runs + fleet issue/PR flow, Sentry, and human TODOs — together.
- **Minimal *maintenance tail*, not just minimal build.** Solo operator; momentum reliably dies in the last 20% (`docs/personality.md`). An ops tool carrying its own service code will rot — the build cost is a one-off, the maintenance cost is forever.
- **Built-in alerting.** The incident that triggered this — "I saw no notifications overnight" — is an *alerting* gap. A dashboard you must remember to open does not fix it.
- **Platform consistency.** Prefer extending an ADR-blessed tool over standing up a bespoke service. Grafana is already adopted — ADR-0009 (observability), ADR-0013 (Grafana/CloudWatch pull).
- **Auth.** `jaetill-portal` is a public launcher; the cockpit is private and must be gated.
- **Portfolio value.** Output should be an employer-legible skill, not generic glue code.

**Settled inputs (decided 2026-05-25):** Human TODOs are stored as **GitHub issues carrying a `human-todo` label** — no new datastore; the dashboard reads them like any other issue query.

## Considered Options

- **Option A: Grafana Cloud dashboard** — extend the existing Grafana stack with the GitHub data source plugin.
- **Option B: Portal admin page** — an auth-gated `/admin` route in `jaetill-portal`, backed by a new aggregation Lambda.
- **Option C: Standalone admin app** — its own deployed app on its own URL.
- **Option D: Cowork artifact** — the status quo; self-refresh via MCP connectors.

## Decision Outcome

**Accepted: Option A — Grafana Cloud** (accepted 2026-05-25).

Grafana pulls GitHub Actions runs, fleet issue/PR flow, and the `human-todo` issues **natively on the free tier with zero custom code**; it provides **built-in alerting** that closes the gap that triggered this ADR; and it **extends a tool the platform already adopted** (ADR-0009, ADR-0013), so it carries almost no maintenance tail. The one honest cost — less bespoke visual control than a hand-built page — is acceptable for an ops cockpit, where function beats form.

Option D is eliminated on the facts: there is **no GitHub MCP connector** in the registry, so a Cowork artifact cannot self-refresh GitHub Actions data — Claude would stay in the loop. Options B and C work but each adds a bespoke, permanently-maintained service for a tool that needs none.

## Consequences

### Positive

- Self-refreshing by construction — Grafana panels poll on an interval; nothing to trigger.
- Alerting included — "loop didn't fire in the overnight window", "new P0", "PR stuck in review" become notifications, not things to notice.
- Near-zero maintenance tail — no service code, no deploy pipeline, no secrets rotation beyond two API tokens.
- Builds on plumbing already laid (the Grafana/CloudWatch pull, ADR-0013) — incremental, not greenfield.
- Portfolio-legible: "stood up a Grafana observability cockpit over GitHub Actions, Sentry, and CloudWatch, alerting included, provisioned as code" is a clean SRE-flavoured line.

### Negative

- Less visual control than a hand-built page. The cockpit will look like Grafana — stat panels, tables, state-timelines — not the artisanal 4-stage flow of the current artifact.
- The **native Sentry data source is a paid Grafana Enterprise plugin** (it was free until ~2021; it is not now). The free Sentry path is a workaround — see Implementation notes.
- One API token (a read-only GitHub PAT) lives in Grafana's encrypted data-source config — one more secret surface, though small and read-only. The free-mirror Sentry decision means no second token.

### Neutral

- The cockpit lives behind the Grafana Cloud login rather than inside the portal. `jaetill-portal` keeps a tile that deep-links to it — the portal stays the launcher, Grafana is the cockpit behind it.
- The current Cowork artifact is retired once the Grafana dashboard is authoritative.
- Grafana is a new tool in Jason's working set — a cost (learning curve) and a benefit (it is the learning vehicle / portfolio piece).

## Pros and Cons of the Options

| Option | GitHub runs | Sentry | TODOs | Self-refresh, no Claude | Build effort | Maintenance tail |
|---|---|---|---|---|---|---|
| **A — Grafana** (chosen) | ✅ free native plugin | ⚠️ free via `source:sentry` issues + CloudWatch; native plugin is paid | ✅ free native plugin | ✅ yes | Low — config only | **Very low** |
| **B — Portal page** | ❌ needs a Lambda calling the GitHub API | ❌ needs a Lambda calling the Sentry API | ✅ via the same Lambda | ✅ yes | **High** — Lambda, frontend, IaC, secrets | High — a permanent service |
| **C — Standalone app** | ❌ same as B | ❌ same as B | ✅ same as B | ✅ yes | **Highest** — B, minus the portal's reusable auth | High |
| **D — Cowork artifact** | ❌ no GitHub MCP connector exists | ✅ via the Sentry MCP connector | ✅ via GitHub issues, but see GitHub column | ❌ partial — GitHub leg still needs Claude | Low | Low |

### Option A: Grafana Cloud

- ✅ The GitHub data source plugin queries 20+ resource types — workflow runs, issues, PRs, releases — with built-in API-rate-limit caching, on the Grafana Cloud free tier.
- ✅ Alerting and scheduled refresh are first-class; no code.
- ✅ Extends an already-adopted, already-provisioned tool.
- ❌ Panel-based layout; not pixel-control. Native Sentry data source costs money.

### Option B: Portal admin page

- ✅ Total visual control; reuses the portal's existing passkey auth.
- ✅ A more impressive single "I built this" artifact.
- ❌ A new Lambda (GitHub API + Sentry API + aggregation + caching), a frontend page, Terraform, and SSM secrets — a permanently-maintained service for a read-only tool. The long tail lands squarely in Jason's last-20% dead zone.

### Option C: Standalone admin app

- ✅ Keeps the public portal's codebase untouched.
- ❌ Everything in B, and you rebuild auth + deploy from scratch instead of reusing the portal's. Strictly more work than B for no functional gain.

### Option D: Cowork artifact (status quo)

- ✅ Lightest to build; Sentry refreshes live via the Sentry MCP connector.
- ❌ No GitHub MCP connector exists — the GitHub Actions leg cannot self-refresh, which fails the core requirement. Also not a "permanent" home independent of Cowork.

## Implementation notes

Phased so the core value lands in Phase 1 — before the last-20% risk sets in.

**Phase 1 — GitHub leg + core dashboard (the 80%)**

Everything from here is authored as Terraform (Grafana provider) — no click-ops.

- Create a fine-grained GitHub PAT, read-only, scoped to the 8 fleet repos: Actions, Issues, Pull requests, Contents, Metadata. (A GitHub App is the alternative; PAT is fine for a solo setup.)
- Declare the GitHub data source as a `grafana_data_source` resource; the PAT is supplied as a Terraform variable / secret, never committed.
- Build panels: four stat panels (discovered / promoted / in-flight / merged-7d); a state-timeline or table of recent `triage-scan`, `claude-implementer`, `ci-health` runs ("did the loop fire"); a per-project flow table; a `human-todo` table; a "needs you" table (open `incident:p0` + `source:sentry` issues, held implementer PRs).
- Set dashboard auto-refresh (5–15 min) and a default time range.

**Phase 2 — CloudWatch + Sentry legs**

- CloudWatch: add Lambda error/invocation panels from the existing data source (ADR-0013).
- Sentry: **decided — the GitHub-issue mirror is the Sentry leg.** The loop already mirrors Sentry P0s into GitHub issues (`source:sentry`); the free GitHub data source surfaces them in the "needs you" panel. No Sentry data source (paid or free) is installed. Live Sentry error rates are explicitly out of scope unless the mirror proves insufficient.

**Phase 3 — Alerting (closes the gap that triggered this ADR)**

- Alert rules: no non-skipped `triage` job in the overnight window; a new `incident:p0` / `source:sentry` issue; an implementer PR in-flight beyond N days; a `ci-health` failure.
- Wire a contact point (email to start).

**Phase 4 — Portal integration + cutover**

- Add a `jaetill-portal` tile deep-linking to the Grafana dashboard.
- Retire the `autonomous-loop-portfolio-flow` Cowork artifact once the Grafana cockpit is authoritative.

**Decisions (resolved 2026-05-25)**

- Sentry leg → **GitHub-issue mirror only.** No Sentry data source installed.
- Provisioning → **Terraform from the start**, via the Grafana provider; consistent with ADR-0007. No click-ops phase.
- `human-todo` issues → **platform repo only** (default — it is the ops repo; one known place to file a TODO). The GitHub data source can widen to fleet-wide later without rework.

## Links

- ADR-0009 — observability baseline (Grafana adopted).
- ADR-0013 — Grafana/CloudWatch pull integration (the stack this extends).
- ADR-0007 — IaC; Phase 4 provisioning follows it.
- ADR-0020 / ADR-0021 — the autonomous loop this cockpit observes.
- GitHub data source for Grafana: `https://grafana.com/grafana/plugins/grafana-github-datasource/` — free on Grafana Cloud; workflow-run, issue, and PR queries with rate-limit caching.
- Sentry data source for Grafana: `https://grafana.com/grafana/plugins/grafana-sentry-datasource/` — paid Enterprise plugin; informs the Phase 2 Sentry-leg choice.
