---
paths:
  - ".github/workflows/**"
  - "scripts/**"
---

# CI workflows, scripts & the autonomous loop

## Workflow authoring

- **Don't pin first-party reusable workflows** (`jaetill/agentic-dev-environment/...`) to a SHA — they ride `@main` behind the hardened upstream so platform fixes propagate (ADR-0048/ADR-0034); pinning is for third-party actions only. Forward explicit minimal secrets to reusables, never `secrets: inherit`.
- **Sweep operations log loudly on zero results.** When a fleet sweep (auto-merger, dep-watcher, etc.) processes 0 items, that may be legitimate (queue empty) or a silent failure (filter broken). Emit a `::warning::` so the next reader knows to verify (PR #360 instrumented the auto-merger's sweep; the pattern carries over).
- When you retire a fleet-specific term, sweep the operational files here for stale references in the same PR — `terminology-check.sh` scans `.github/workflows`, `scripts`, `plugins/ai-team/agents`, and the `*.tf` trees.

## The autonomous loop

This repo runs an **autonomous agent loop on GitHub Actions cron** — *not* Cowork scheduled tasks. To check whether the "overnight" or "0900" run fired, use `gh run list`, never the Cowork scheduler.

- **What runs it:** [`triage-scan.yml`](../../.github/workflows/triage-scan.yml) (scheduled scan + fleet-wide promoter that dispatches implementers across every portfolio repo, plus the fleet auto-merger that squash-merges qualifying implementer fix PRs per ADR-0021 — `vars.AUTONOMOUS_MERGE=off` pauses it) and [`claude-implementer.yml`](../../.github/workflows/claude-implementer.yml) (picks up labelled or dispatched issues). [`ci-health.yml`](../../.github/workflows/ci-health.yml) watches every fleet repo's non-PR workflows and files platform issues on failure.
- **When it runs:** autonomous work *starts* only inside two America/Chicago windows — `overnight` (01:00–04:00 daily) and `work-hours` (09:00–12:00 Mon–Fri); all other time is quiet for triage, promotion, and dispatch. Exception: the **merge sweep is un-windowed** (merge-when-green, ADR-0044 §3) — a green, ungated PR merges any time; held PRs carry `hold:<reason>` labels. Design in [ADR-0017](../../docs/adr/0017-async-orchestration.md) and [ADR-0020](../../docs/adr/0020-fleet-orchestration.md).
- **How to check it:** `gh run list --workflow=triage-scan.yml`. A scheduled run showing `success` with its `triage` job *skipped* is the cron firing outside the window — correct behaviour, not a failure.
- **Full detail:** [docs/runbooks/autonomous-loop.md](../../docs/runbooks/autonomous-loop.md) — windows, DST handling, manual triggering, routing, known gaps.
