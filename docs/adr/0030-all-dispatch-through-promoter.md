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

**Dispatch topology — one central promoter, project-scoped.** The promoter stays single and platform-central; it is *not* copied per repo. App repos forward their trusted-origin events to it with a thin `repository_dispatch` stub (repo + issue + reason); the central promoter then runs **scoped to that one project** — promoting the trigger and filling only that project's slice, without a full fleet scan. This is what makes the `FLEET_MAX_DISPATCH` throttle real: only a single central actor can count in-flight work across the whole fleet, so a multi-repo storm is actually capped. Per-repo promoters were rejected — they would re-create the per-repo-copy drift (cf. [ADR-0018](0018-workflow-distribution.md)) *and* fragment the cap into per-repo limits, defeating the throttle.

**Mechanism — deterministic dispatch, then LLM fill.** The trigger's auto-promote is a **deterministic** step (apply `ready-for-implementer`, throttle-check fleet-wide in-flight work, dispatch) — no LLM on the critical path of urgent dispatch. The cycle-fill is the existing LLM promoter scoped to that project, **staged after** the deterministic relocation (see rollout): urgent work becomes throttled-and-reliable first; opportunistic fill follows.

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

## Implementation notes (staged rollout)

**Status (2026-05-31): Phase 1 shipped + live-validated** on the platform repo — a `severity:critical` test issue exercised both the throttle-hold path (held at 6/6) and, after the throttle was corrected, the dispatch path (dispatched at 0/6). The validation fixed one bug: the throttle counts **active implementer runs** (`in_progress`/`queued`), not open PRs (open PRs are the awaiting-merge backlog and would chronically hold urgent dispatch). Loop-safety confirmed: a bot-applied `ready-for-implementer` does not re-trigger event-dispatch.

**Phase 1 — platform repo (shipped + validated):**

1. **`triage-scan.yml`** — add `issues: [opened, labeled]` + `repository_dispatch: [implementer-event]` triggers and a deterministic, project-scoped **`event-dispatch`** job: on a trusted-origin event it applies `ready-for-implementer`, **throttle-checks fleet-wide in-flight work against `FLEET_MAX_DISPATCH`** (fail-open for urgent work so a transient error never drops a critical), and dispatches the implementer via `workflow_dispatch`. The ADR-0025 OWNER guard sits on the `opened` path here. No LLM on this path (deterministic).
2. **`claude-implementer.yml`** — the `initial` (non-IaC) job loses the bypass triggers (`source:sentry`, `severity:critical`, owner-opened, human `ready-for-implementer`); it keeps only the feature-continuation labels (`plan-approved`, `skip-plan`). The promoter's `workflow_dispatch` (`manual-dispatch` job) and Modes B/C are unchanged.

**Phase 2+ (follow-ups):**

3. **LLM cycle-fill** — after Phase 1 is validated, the `event-dispatch` job kicks the existing promoter (project-scoped) to opportunistically fill remaining capacity. Deferred so urgent dispatch is reliable first.
4. **IaC path** — `initial-iac` is left on its current triggers for now; routing `scope:iac` dispatch through the promoter is a separate, low-volume follow-up.
5. **Integrations** — re-point the Sentry/CloudWatch GitHub automations to fire `repository_dispatch` at the promoter instead of label→implementer.
6. **Fleet propagation — BLOCKED on a credential (needs Jason).** Each app repo needs a thin `repository_dispatch` forwarder (trusted-origin event → `implementer-event` at the platform promoter, model B), then its `claude-implementer.yml` `initial` trim. **Blocker found 2026-05-31:** the app repos have *no* credential that can `repository_dispatch` cross-repo to the platform — only the platform repo holds `FLEET_APP_ID`/`FLEET_APP_PRIVATE_KEY`, and a repo's scoped `GITHUB_TOKEN` can't dispatch to another repo. Provision a credential in each of the 7 app repos (preferably a **fine-grained PAT scoped to `repository_dispatch` on `agentic-dev-environment` only** — safer than replicating the powerful fleet app key everywhere), then the forwarder + trim can land. Until then the app repos stay on their **current working bypass model** — *do not trim them without a working forwarder*, because the scheduled promoter does not promote `severity:critical`/`source:sentry` (they "auto-pickup"), so trim-without-forwarder = a dispatch gap.
7. **Loop diagram** — collapse the bypass edges; all entry points feed the promoter.

**Rollout:** platform repo first (Phase 1), validate one live event end-to-end, then the fill, the integrations, and the app-repo propagation. Each app repo keeps its direct paths until its forwarder is validated, so there's never a dispatch gap.

## Links

- [ADR-0029](0029-promoter-owns-nit-adjacency.md) — promoter owns workload selection; this completes that by making it own *all* dispatch.
- [ADR-0017](0017-async-orchestration.md) · [ADR-0020](0020-fleet-orchestration.md) — the promoter/orchestration this extends.
- [ADR-0026](0026-agentic-implementer.md) · [ADR-0023](0023-origin-based-autonomy-boundary.md) · [ADR-0025](0025-owner-guard-on-platform-opened-pickup.md) · [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — amended (see table).
- [ADR-0018](0018-workflow-distribution.md) — the per-repo copy gap that makes step 4 an 8× propagation.
