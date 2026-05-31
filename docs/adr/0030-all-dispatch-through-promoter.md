# ADR-0030: All implementer dispatch routes through the promoter (no direct bypass)

- **Status:** Accepted — design ratified 2026-05-31. **Implementation staged** (platform repo first, then fleet propagation + integration re-point). Until the re-plumb lands, the as-built direct-dispatch paths described in ADR-0026/0017/0023/0025 remain in effect; this ADR is the governing decision for dispatch routing going forward.
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, autonomy, governance

> **Format:** MADR 4.x. Single-decision ADR. Makes the promoter the single dispatch authority; the natural endpoint of the scheduler/worker separation begun in [ADR-0029](0029-promoter-owns-nit-adjacency.md). Amends [ADR-0017](0017-async-orchestration.md), [ADR-0020](0020-fleet-orchestration.md), [ADR-0026](0026-agentic-implementer.md), [ADR-0023](0023-origin-based-autonomy-boundary.md), [ADR-0025](0025-owner-guard-on-platform-opened-pickup.md), [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — see *Impacted ADRs*.

## Context and Problem Statement

Today five signals dispatch the implementer **directly**, skipping the promoter:

- `severity:critical` (agent-applied critical)
- `source:sentry` (Sentry production error)
- `source:cloudwatch` (intended per ADR-0023 — but never wired into the implementer trigger; an inconsistency)
- `ready-for-implementer` applied by a human/maintainer
- the OWNER opening a `bug`/`defect`/`feature-request` (ADR-0025 owner-guarded `opened` path)

The promoter handles everything else, with a `FLEET_MAX_DISPATCH` throttle, dedup, an oscillation/fix-and-revert guard, and a Tier-2 eligibility judgment.

The direct paths bypass all of that. The sharpest consequence: **they have no throttle.** ADR-0017 explicitly names "a Sentry error storm filing 14 redundant issues" as a failure mode the orchestration should prevent — yet the `source:sentry` bypass sails straight past `FLEET_MAX_DISPATCH`, so a flap or a batch of criticals can spawn unbounded concurrent implementer runs (cost + self-collision). The paths also duplicate trigger logic across the implementer workflow and leave the CloudWatch inconsistency unresolved.

Should every dispatch route through the single scheduler instead of five parallel front doors?

## Decision Drivers

- **Single dispatch authority.** The promoter schedules; the implementer executes. One front door (the endpoint of ADR-0029's separation).
- **Throttle + dedup must cover urgent work too.** The Sentry-storm failure mode is real and currently unguarded.
- **Don't regress urgent work.** Criticals and production errors must still dispatch *immediately* and *deterministically* — no LLM veto, no waiting for the next cron window.
- **Resolve the CloudWatch inconsistency** as part of the model, not as a one-off patch.

## Considered Options

- **Option A:** Keep the direct bypasses; just wire `source:cloudwatch` into the implementer trigger to match the spec.
- **Option B:** Route everything through the promoter. The trusted-origin signals dispatch an **event-triggered, project-scoped** promoter run that auto-promotes the trigger and fills the cycle.

## Decision Outcome

Chosen option: **Option B.** The promoter becomes the **single dispatch authority**. The implementer's *only* trigger is `ready-for-implementer` (applied by the promoter). Every signal that used to dispatch the implementer directly now dispatches the **promoter** instead, in a project-scoped event mode, which:

1. **Auto-promotes the triggering issue unconditionally** — no "well-specified?" judgment, no "when in doubt, don't promote." Trusted origin in, deterministic promotion out. This preserves immediate, reliable pickup for criticals/Sentry/CloudWatch.
2. **Then runs its normal eligibility scan** for that project, filling the remaining `FLEET_MAX_DISPATCH` capacity with other eligible work. The Tier-2 judgment applies **only** to this cycle-fill, never to the triggering issue.

**Two invariants** (these are what keep the bypass's virtues):

- **Event-triggered, not cron-gated.** A trusted-origin event dispatches the promoter *now* (via `workflow_dispatch`/`repository_dispatch`, which bypass the window gate exactly as manual dispatch does today). Urgent work is not delayed to the next window.
- **Deterministic auto-promote of the trigger.** The LLM judgment never gates the issue that caused the run — only the extra work it scans for.

Option A is rejected: it leaves the throttle gap and the five-front-door duplication in place.

## Consequences

### Positive

- The `FLEET_MAX_DISPATCH` throttle and dedup now cover the work that most needs them — closing ADR-0017's named Sentry-storm gap.
- One dispatch authority; the implementer workflow loses its tangle of auto-pickup triggers and keeps a single `ready-for-implementer` entry.
- The CloudWatch inconsistency dissolves — CloudWatch becomes a promoter trigger like Sentry; nothing special to wire into the implementer.
- Opportunistic cycle-fill: an urgent event also drains other eligible work for that project in the same run.

### Negative

- The LLM-driven promoter becomes the **single front door** for all dispatch, including the most urgent — a single point of failure. Mitigated: the per-event run is a small, focused "promote issue N + scan one project" task (far lighter than a full fleet scan); the deterministic auto-promote means the LLM cannot veto the trigger; and centralizing makes dispatch health observable in one place.
- More moving parts in the promoter (an event-triggered, project-scoped mode beside the scheduled fleet scan).

### Neutral

- Human-approved work (`ready-for-implementer` / owner-opened) is *already* a promotion decision; routing it through the promoter to "auto-promote" is redundant there — its only added value is the cycle-fill. Acceptable.
- The auto-merge **machine-origin** check (ADR-0023) is unchanged — that governs *merge*, not *dispatch*.

## Impacted ADRs (consolidated, so consistency lives in one place)

| ADR | What changes |
|---|---|
| [ADR-0026](0026-agentic-implementer.md) | **Dispatch gating** bullet: the implementer engages only on `ready-for-implementer` (from the promoter). The `source:sentry`/`source:cloudwatch`/`severity:critical` auto-pickup labels are removed from the *implementer* trigger; they trigger the *promoter*. |
| [ADR-0017](0017-async-orchestration.md) | The promoter gains an **event-triggered, project-scoped** mode. The "human-filed pickup via `issues: opened` → implementer" re-routes to `opened` → promoter. The window-gate bypass for manual/event dispatch is unchanged. |
| [ADR-0020](0020-fleet-orchestration.md) | The fleet promoter adds an event-triggered, single-project invocation alongside the scheduled fleet-wide scan. |
| [ADR-0023](0023-origin-based-autonomy-boundary.md) | Machine-detected work (`source:sentry`/`source:cloudwatch`) routes through the promoter (auto-promoted), not direct implementer pickup. The machine-origin **merge** check is unchanged. |
| [ADR-0025](0025-owner-guard-on-platform-opened-pickup.md) | The `author_association == 'OWNER'` guard moves from the `opened` → *implementer* path to the `opened` → *promoter* path (same OWNER condition, new dispatch target). |
| [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) | Sentry-bug pickup is now a promoter trigger, not a direct implementer trigger. |

## Implementation notes (staged rollout — pending separate go-ahead)

1. **`triage-scan.yml`** — add event triggers (`repository_dispatch` for Sentry/CloudWatch; `issues: labeled`/`opened` for the label/owner paths) and a project-scoped **"auto-promote issue N, then fill this project's cycle"** mode beside the scheduled fleet scan. Carry the OWNER guard (ADR-0025) on the `opened` path here.
2. **`claude-implementer.yml`** — remove the auto-pickup direct triggers (`source:sentry`, `severity:critical`, `source:cloudwatch`, owner-opened). Keep `ready-for-implementer` (non-bot) and the promoter's `workflow_dispatch`. (Mode B fix-iteration and Mode C cleanup-sweep unchanged.)
3. **Integrations** — re-point the Sentry (and CloudWatch) GitHub automations to fire a `repository_dispatch` at the promoter instead of label→implementer.
4. **Fleet propagation** — `claude-implementer.yml` is copied per repo (the ADR-0018 distribution gap), so steps 2 must propagate to all 8 fleet repos.
5. **Loop diagram** — collapse the bypass edges; all entry points feed the promoter; the implementer has one inbound edge.

**Rollout:** platform repo first, validate one event cycle end-to-end, then propagate to the app repos and re-point integrations. Keep the direct paths until each repo's promoter path is validated to avoid a dispatch gap.

## Links

- [ADR-0029](0029-promoter-owns-nit-adjacency.md) — promoter owns workload selection; this completes that by making it own *all* dispatch.
- [ADR-0017](0017-async-orchestration.md) · [ADR-0020](0020-fleet-orchestration.md) — the promoter/orchestration this extends.
- [ADR-0026](0026-agentic-implementer.md) · [ADR-0023](0023-origin-based-autonomy-boundary.md) · [ADR-0025](0025-owner-guard-on-platform-opened-pickup.md) · [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — amended (see table).
- [ADR-0018](0018-workflow-distribution.md) — the per-repo copy gap that makes step 4 an 8× propagation.
