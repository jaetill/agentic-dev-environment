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
| `triage-scan.yml` | cron (two windows) + `workflow_dispatch` | runs the **fleet promoter** (scans every portfolio repo, labels eligible agent-discovered issues `ready-for-implementer`, dispatches the target repo's `claude-implementer.yml` — ADR-0020) and the **fleet auto-merger** (squash-merges green, qualifying implementer fix PRs as the fleet App; `vars.AUTONOMOUS_MERGE=off` pauses it — ADR-0021) |
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

### Cron vs. window — why a run can "succeed" but do nothing

GitHub cron is UTC-only and cannot express a DST-aware local window. `triage-scan.yml` therefore fires on a **generous UTC band**, and a `window` job inside the workflow checks the real America/Chicago time and skips the work if it is out of window:

- `0,30 14-18 * * 1-5` — covers `work-hours` across both CDT and CST
- `0,30 6-10 * * *` — covers `overnight` across both CDT and CST

So a scheduled `triage-scan` run shows `success` even when it did no work — the `window` job ran, decided "quiet," and skipped the `triage` job. **`success` + `triage` skipped = correct out-of-window behaviour.** Real work happened only when the `triage` job itself shows `success`.

## How to check whether a window ran

1. List recent scheduled runs:

       gh run list --workflow=triage-scan.yml --limit 12 --json status,conclusion,createdAt,event

2. Convert `createdAt` (UTC) to America/Chicago. CDT = UTC−5, CST = UTC−6.
3. For a run that lands inside a window, confirm the work actually happened:

       gh run view <run-id> --json jobs --jq '.jobs[] | {name,conclusion}'

   `triage` job `success` = the scan + promoter ran. `triage` job `skipped` = out of window.

## How to trigger a run manually

`workflow_dispatch` bypasses the window check (`window=manual`, always treated as in-window):

    gh workflow run triage-scan.yml -f reason="<why>"
    gh workflow run claude-implementer.yml -f issue_number=<n>

To manually drain deferred nits on a specific fleet repo (Mode C cleanup sweep, ADR-0020):

    gh workflow run claude-implementer.yml --repo jaetill/<repo> -f mode=cleanup-sweep

## How work routes

ADR-0017 routes work by **source × type × severity**. `claude-implementer`'s `initial` job is triggered two ways:

- **Human-filed work — `issues: opened`.** When a human opens an issue carrying a type label (`bug`, `defect`, or `feature-request`), the implementer picks it up immediately — no window, no promoter. The `opened` event is itself a human action, so it triggers the workflow directly: there is no label round-trip and no `GITHUB_TOKEN` cascade problem. A human-filed **bug** goes straight to the build phase; a human-filed **feature** enters the plan-gate — the implementer posts an approach and waits for the human's `plan-approved`.
- **Agent-discovered work — promoter dispatch (ADR-0020).** The in-window fleet promoter applies `ready-for-implementer` as durable state and then dispatches `claude-implementer.yml` directly. The label-triggered `initial` job still fires for `source:sentry`, `severity:critical`, `plan-approved`, `skip-plan`, and a *human*-applied `ready-for-implementer` — but a *bot*-applied `ready-for-implementer` is deliberately ignored there (the dispatch handles it; this prevents a double-trigger).

A human-filed issue with **no** type label is not auto-picked-up — add `bug` / `feature-request`, or apply `ready-for-implementer` directly. Issues filed through the bug-report or feature-request template already carry the label. The `opened` trigger is not retroactive: an issue opened before this routing landed needs a one-time `ready-for-implementer`.

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

## Escalation

The loop is solo-operated. If a run is failing and the cause isn't obvious, check `gh run view <id> --log-failed`, then raise it with Jason. Do not disable a workflow to silence noise — file an issue.

## First seen

Created 2026-05-21, after a fresh session was asked "did the 0900 run fire," looked at Cowork scheduled tasks (the wrong place), and answered incorrectly. This runbook and the CLAUDE.md "Autonomous loop" section exist so that does not recur.
