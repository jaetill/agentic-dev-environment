# Runbook — the autonomous agent loop

**Type:** operations overview.
**Decision records:** [ADR-0017](../adr/0017-async-orchestration.md) — scheduling & routing; [ADR-0018](../adr/0018-workflow-distribution.md) — workflow distribution; [ADR-0020](../adr/0020-fleet-orchestration.md) — fleet orchestration; [ADR-0021](../adr/0021-autonomous-merge.md) — autonomous merge of fix PRs.

## What the loop is

The platform runs autonomous engineering work — triage, issue promotion, implementation, review — as **GitHub Actions workflows**. It is not driven by Cowork scheduled tasks, by cron on anyone's machine, or by a long-running service. Every part of it is a workflow in `.github/workflows/`.

If someone asks "did the loop run last night / at 0900," the answer lives in **GitHub Actions run history**, not the Cowork scheduler:

    gh run list --workflow=triage-scan.yml --limit 12

## The workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `triage-scan.yml` | cron (two windows) + `workflow_dispatch` | runs the **fleet promoter** (scans every portfolio repo, labels eligible agent-discovered issues `ready-for-implementer`, dispatches the target repo's `claude-implementer.yml` — ADR-0020) and the **fleet auto-merger** (squash-merges green, qualifying implementer fix PRs as the fleet App; un-windowed per ADR-0044 §3 — all-day cron + event-driven on this repo's gate; `vars.AUTONOMOUS_MERGE=off` pauses it — ADR-0021) |
| `claude-implementer.yml` | `issues: opened`/`labeled` + `issue_comment` + `workflow_dispatch` | picks up a human-filed or promoted issue and opens an implementation PR; also runs the fix-iteration loop |
| `ci-health.yml` | cron | fleet-wide watcher; observes every repo's non-PR workflow runs and files a consolidated platform-repo issue on failure, labelled `triage:medium` so the promoter routes it (ADR-0020) |
| `claude-pr-review.yml` | `workflow_call` (reusable) | the review gate, invoked by each project's caller stub |

`claude-implementer.yml` is **event-driven, not cron-driven** — it has no schedule. The windowing is enforced upstream: only the promoter (which *is* cron-windowed) hands it agent-discovered work.

## The windows

Autonomous work runs only inside two America/Chicago windows:

| Window | Local time | Why |
|---|---|---|
| `overnight` | 01:00–04:00 daily | Jason is asleep |
| `work-hours` | 09:00–12:00 Mon–Fri | Jason is at work |

All other time is quiet by design (ADR-0017, sub-decision 2).

**Exception — merge-when-green (ADR-0044 §3):** the auto-merge sweep is **un-windowed**. A green, ungated implementer PR merges any time: the sweep runs on an all-day cron (`15,45 * * * *`) and fires event-driven when this repo's own `pr-review` gate completes. Windows still gate triage, promotion, and dispatch — new *work* starts only in-window; finished work ships immediately. Gates that hold a green PR mark it `hold:<reason>` (`hold:adr`, `hold:compositional`, `hold:iac-unverified`, `hold:checks-escalated`), stripped on exit.

### Cron vs. window — why a run can "succeed" but do nothing

GitHub cron is UTC-only and cannot express a DST-aware local window. `triage-scan.yml` therefore fires on a **generous UTC band**, and a `window` job inside the workflow checks the real America/Chicago time and skips the work if it is out of window:

- `0,30 11-17 * * 1-5` — covers `work-hours` across both CDT and CST, shifted ~3 h earlier to absorb GitHub cron drift
- `0,30 3-9 * * *` — covers `overnight` across both CDT and CST, shifted ~3 h earlier to absorb GitHub cron drift

The "shifted ~3 h earlier" matters: GitHub Actions cron is best-effort and can delay or drop fires under load. Observed drift on this account (2026-05-26..28) was 2–3 h late with ≥75 % of slots dropped — every delivered fire landed *after* the window had closed and the `window` job skipped the work. Starting the cron band 3 h before the earliest in-window UTC slot means a delayed fire still lands inside the window.

So a scheduled `triage-scan` run shows `success` even when it did no work — the `window` job ran, decided "quiet," and skipped the `triage` job. **`success` + `triage` skipped = correct out-of-window behaviour.** Real work happened only when the `triage` job itself shows `success`.

## How to check whether a window ran

1. List recent scheduled runs:

       gh run list --workflow=triage-scan.yml --limit 12 --json status,conclusion,createdAt,event

2. Convert `createdAt` (UTC) to America/Chicago. CDT = UTC−5, CST = UTC−6.
3. For a run that lands inside a window, confirm the work actually happened:

       gh run view <run-id> --json jobs --jq '.jobs[] | {name,conclusion}'

   `triage` job `success` = the scan + promoter ran. `triage` job `skipped` = out of window.

> **Future primary check — ops cockpit (Phase 1b):** `infra/ops-cockpit/` is being built into a self-refreshing Grafana dashboard that will surface loop run health directly. Phase 1a is a placeholder only. Until Phase 1b panels ship, use `gh run list` as described above.

## How to trigger a run manually

`workflow_dispatch` bypasses the window check (`window=manual`, always treated as in-window):

    gh workflow run triage-scan.yml -f reason="<why>"
    gh workflow run claude-implementer.yml -f issue_number=<n>

To manually drain deferred nits on a specific fleet repo (Mode C cleanup sweep, ADR-0020):

    gh workflow run claude-implementer.yml --repo jaetill/<repo> -f mode=cleanup-sweep

## How work routes

All implementer dispatch flows through the **promoter** (ADR-0030) — there is no direct `issues: opened` bypass to a per-repo `initial` job anymore (that job was removed). Work reaches the implementer (the `manual-dispatch` job, via `workflow_dispatch`) by these paths:

- **Owner-opened defects — immediate.** An owner-opened `bug` / `defect` dispatches at once via the promoter's deterministic `event-dispatch` (ADR-0030 / 0025). An owner-opened `feature-request` does **not** — features are formulated at human intake and enter via `approved` (ADR-0036), never on open.
- **Machine-detected urgent work.** `source:sentry`, `source:cloudwatch`, `severity:critical` route through `event-dispatch` (platform) or the central urgent-poll (app repos), throttled to the shared fleet in-flight ceiling (`scripts/fleet-inflight.sh`).
- **Human fast-track.** A human applying `ready-for-implementer` dispatches immediately via `event-dispatch` — the intake override for an `approved` feature you want worked now.
- **Agent findings + approved features — windowed promoter (ADR-0020).** The in-window ranked promoter promotes eligible agent findings and `approved` features (the latter at the **medium** tier, ADR-0036) within the shared dispatch budget, then dispatches via `workflow_dispatch`.

There is **no in-loop plan-gate**: a feature's *what* is decided at human intake (formulation → `approved`, ADR-0036); the implementer plans the *how* itself. A human-filed issue with no type label is not auto-picked-up — a maintainer formulates/labels it first.

### Resolved — the promoter dispatches; it does not rely on a label cascade

ADR-0020 settled this. A label applied by `GITHUB_TOKEN` does not trigger downstream workflows, and a cross-repo label cascade is not reliable enough to depend on. The fleet promoter therefore applies `ready-for-implementer` as **durable state** and then explicitly dispatches `claude-implementer.yml` via `workflow_dispatch` — the dispatch is the trigger; the label records intent. A failed dispatch is visible in the triage-scan run log; a silent label is not.

The promoter runs as a GitHub App, and an App's label events *do* cascade — so each `claude-implementer.yml`'s `initial` job carries a sender guard: a bot-applied `ready-for-implementer` does not trigger `initial` (the dispatch handles it), while a human-applied one still does. The human-filed path (`issues: opened`) is unchanged and immune.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| A newly-added or edited cron didn't fire | GitHub registers schedule changes with a delay (often ~1 h, sometimes longer) after the workflow file lands on the default branch | Wait for the next window; use `workflow_dispatch` to test immediately |
| Scheduled run `success` but nothing happened | Cron fired outside the America/Chicago window; the `window` job skipped the work | None — correct behaviour |
| `claude-implementer` run shows all jobs `skipped` | The label that was added is not a pickup label | Apply a pickup label (`ready-for-implementer`, `skip-plan`, etc.) |
| One workflow's action can't trigger another workflow | The triggering action authenticated with `GITHUB_TOKEN` | Use a GitHub App token / PAT for the cross-workflow action |
| A fleet dispatch did nothing | `gh workflow run` failed — target repo missing the workflow, an undeclared input, or a bad/expired App token | Check the triage-scan run log for the non-zero `gh workflow run` exit; the promoter reports failed dispatches in its summary |
| `event-dispatch` throttle holds urgent work even though no implementer runs look active | The throttle counts **active workflow runs** (`in_progress` + `queued` on `claude-implementer.yml`), not open PRs — so it's unaffected by the open-PR backlog. Verify with `gh run list --repo jaetill/<repo> --workflow=claude-implementer.yml --json status -q '[.[] \| select(.status=="in_progress" or .status=="queued")] \| length'` | Wait for in-flight runs to complete; or, if the run count is stuck (e.g., a zombie in_progress run), cancel the stale run |
| Auto-merge sweeps all repos but merges nothing (0 PRs found) | `gh pr list --json author` uses the GraphQL API; GitHub App bot authors appear as `app/<slug>` (`app/claude`), **not** `claude[bot]` (the REST/webhook form). The filter is correct — but if the App's slug ever changes, the filter breaks silently. Verify with: `gh pr list --repo jaetill/meal-planner --state merged --json number,author -q '.[] \| {number: .number, login: .author.login}'` | If the slug changed, update the `select(.author.login == "app/<new-slug>")` filter in the auto-merge job |

## Escalation

The loop is solo-operated. If a run is failing and the cause isn't obvious, check `gh run view <id> --log-failed`, then raise it with Jason. Do not disable a workflow to silence noise — file an issue.

## First seen

Created 2026-05-21, after a fresh session was asked "did the 0900 run fire," looked at Cowork scheduled tasks (the wrong place), and answered incorrectly. This runbook and the CLAUDE.md "Autonomous loop" section exist so that does not recur.
