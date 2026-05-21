# Runbook — the autonomous agent loop

**Type:** operations overview.
**Decision records:** [ADR-0017](../adr/0017-async-orchestration.md) — scheduling & routing; [ADR-0018](../adr/0018-workflow-distribution.md) — workflow distribution.

## What the loop is

The platform runs autonomous engineering work — triage, issue promotion, implementation, review — as **GitHub Actions workflows**. It is not driven by Cowork scheduled tasks, by cron on anyone's machine, or by a long-running service. Every part of it is a workflow in `.github/workflows/`.

If someone asks "did the loop run last night / at 0900," the answer lives in **GitHub Actions run history**, not the Cowork scheduler:

    gh run list --workflow=triage-scan.yml --limit 12

## The workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `triage-scan.yml` | cron (two windows) + `workflow_dispatch` | scans telemetry for new issue patterns; runs the **promoter** pass that labels eligible agent-discovered issues `ready-for-implementer` |
| `claude-implementer.yml` | `issues: labeled` (pickup labels) + `issue_comment` + `workflow_dispatch` | picks up a labelled issue and opens an implementation PR; also runs the fix-iteration loop |
| `ci-health.yml` | cron | dependency-free watcher; files/updates an issue when non-PR workflows fail, auto-closes on recovery |
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

## How work routes (and a known gap)

ADR-0017 routes work by **source × type × severity**. `claude-implementer`'s `initial` job fires **only** when the label just added is one of: `ready-for-implementer`, `source:sentry`, `severity:critical`, `plan-approved`, `skip-plan`.

The path that is fully wired today: an **agent-discovered Medium issue** → the in-window promoter applies `ready-for-implementer` → `claude-implementer` picks it up.

### Known gap — human-filed issues have no auto-pickup

ADR-0017 says human-filed work is "pre-promoted by the act of filing" and "picked up within minutes regardless of clock." **The workflows do not implement this.** A human files an issue with `bug` / `feature-request` / `triage:*` labels — none of which are pickup labels — so:

- the promoter correctly skips it (its spec excludes human-authored issues), and
- `claude-implementer` never fires (no pickup label was added).

The issue then sits untouched until a human manually applies `ready-for-implementer` or `skip-plan`. Issue #24 is the live example. Closing this gap — a labeler on `issues: opened`, or correcting the ADR's wording — is an open decision.

### Open question — does a promoter-applied label cascade?

The promoter applies labels via `gh` authenticated with `GITHUB_TOKEN`. Labels applied by `GITHUB_TOKEN` **do not trigger** downstream workflows (GitHub's loop-prevention rule). Whether `claude-implementer` actually wakes on a promoter-applied label has not yet been observed end-to-end — verify it on the first real agent-discovered promotion.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| A newly-added or edited cron didn't fire | GitHub registers schedule changes with a delay (often ~1 h, sometimes longer) after the workflow file lands on the default branch | Wait for the next window; use `workflow_dispatch` to test immediately |
| Scheduled run `success` but nothing happened | Cron fired outside the America/Chicago window; the `window` job skipped the work | None — correct behaviour |
| `claude-implementer` run shows all jobs `skipped` | The label that was added is not a pickup label | Apply a pickup label (`ready-for-implementer`, `skip-plan`, etc.) |
| One workflow's action can't trigger another workflow | The triggering action authenticated with `GITHUB_TOKEN` | Use a GitHub App token / PAT for the cross-workflow action |

## Escalation

The loop is solo-operated. If a run is failing and the cause isn't obvious, check `gh run view <id> --log-failed`, then raise it with Jason. Do not disable a workflow to silence noise — file an issue.

## First seen

Created 2026-05-21, after a fresh session was asked "did the 0900 run fire," looked at Cowork scheduled tasks (the wrong place), and answered incorrectly. This runbook and the CLAUDE.md "Autonomous loop" section exist so that does not recur.
