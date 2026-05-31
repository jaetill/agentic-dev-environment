# ADR-0017: Async orchestration — scheduling, concurrency, and work routing for the autonomous team

- **Status:** Accepted — sub-decisions 3 (routing) & 4 (feature handling) amended by [ADR-0023](0023-origin-based-autonomy-boundary.md)
- **Date:** 2026-05-20
- **Deciders:** Jason Tilley (with AI architectural review)
- **Tags:** ai-workflows, ci-cd, orchestration, concurrency

> **Amended by [ADR-0030](0030-all-dispatch-through-promoter.md):** dispatch routing changed — all implementer dispatch now goes through the promoter (no direct bypass). See the *Impacted ADRs* table in ADR-0030 for the specific change to this ADR.

> **Format:** MADR 4.x with the platform's three extensions. This is a **bundled-sub-decision** ADR — five tightly-coupled decisions about how autonomous work is scheduled, serialized, and routed.

## Context and Problem Statement

ADR-0011 defined the agent roster and ADR-0016 defined how findings are calibrated and deferred. Neither defined *when* autonomous work runs, *how* concurrent work is kept from conflicting, or *how* a work item is routed from "filed" to "implemented." Today `claude-implementer.yml` fires on any `issues: labeled` event with no schedule and no source-awareness; `triage-bot` has no scheduled run at all (`grep schedule:` across every workflow returns nothing); there is no CODEOWNERS file.

As the platform takes on more autonomous work — and as a second contributor (an external collaborator who will fork the public repo) starts using it — the unmanaged model produces predictable failures: an implementer PR racing a human's in-progress edit, a Sentry error storm filing 14 redundant issues, the human opening their laptop to a pile of surprise merges. How should autonomous work be scheduled, serialized, and routed so that multiple actors (human, agents, external contributor) can operate without conflict or surprise?

## Decision Drivers

- **Conflict resilience.** Multiple actors must work without corrupting each other's work.
- **Predictability.** The human must know when autonomous work happens — no surprises.
- **Speed for requested work.** Work the human explicitly asks for must move fast; only autonomously-discovered work should be batched.
- **Signal calibration.** Single-shot Sentry errors must not trigger fix-loops; clustered patterns should.
- **Solo-dev pragmatism.** Cost is not a constraint (Claude Max subscription); the external contributor uses their own tokens via a fork. Throughput limits exist to bound surprise, not spend.
- **Don't over-build.** Mechanisms must solve a real failure mode, not a theoretical one.

## Considered Options

This is a bundle of five sub-decisions:

- **Sub-decision 1 — Concurrency model:** how do we keep concurrent work from conflicting?
- **Sub-decision 2 — Scheduling:** when does autonomous work run?
- **Sub-decision 3 — Work routing:** how is a work item routed from filed to implemented?
- **Sub-decision 4 — Feature handling:** do features and bugs get the same handling?
- **Sub-decision 5 — Promotion authority:** who marks an issue ready for the implementer?

## Decision Outcome

We chose the bundle:

- **Sub-decision 1 → Optimistic concurrency** (branch isolation + PR-based integration). Each actor works on its own branch; conflicts surface and resolve at merge. No session beacon.
- **Sub-decision 2 → Time windows.** Autonomously-discovered work runs only in `work-hours` (Mon–Fri 09:00–12:00 America/Chicago, while Jason is at work) and `overnight` (daily 01:00–04:00, while Jason is asleep). All other time is quiet.
- **Sub-decision 3 → Route by source × type × severity.** Human-filed work bypasses both the window and the promoter. Only agent-discovered work is window-gated.
- **Sub-decision 4 → Plan-gate for human-filed features; bugs skip it.** The implementer posts its intended approach on a feature issue and waits for the human's approval before writing code; bug fixes proceed directly.
- **Sub-decision 5 → triage-bot is the promoter** for agent-discovered work; human-filed issues are pre-promoted by the act of filing.

> **Sub-decisions 3 and 4 amended by [ADR-0023](0023-origin-based-autonomy-boundary.md) (2026-05-25).** The routing axis is now **origin**, not `source × type × severity`: human-submitted work (feature request, bug, or issue) is human-gated; machine-detected work (Sentry, CloudWatch, agent findings) runs autonomously through commit. The feature plan-gate is **retained** for human-origin features. What changes: human-filed **bugs no longer skip to an autonomous merge** — they take a human-merge checkpoint, because a bug report from an outside person is still a human request against the product. Sub-decisions 1, 2, and 5 are unaffected.

The bundle is internally consistent because the governing principle — *the window exists for surprise control, and human-requested work is never a surprise* — ties sub-decisions 2, 3, and 5 together, while sub-decision 1 (optimistic concurrency) is what makes it safe to skip a session beacon, and sub-decision 4 places the one human checkpoint exactly where human judgment is most valuable (a feature's approach).

The detailed implementation companion is [`PLAN_async_orchestration_architecture.md`](../../PLAN_async_orchestration_architecture.md) — rollout phases, workflow snippets, label conventions. That PLAN is consumed once all phases land.

## Consequences

### Positive

- The human leaves for work; the implementer clears the agent-discovered queue 09:00–12:00 and overnight; afternoons/evenings stay quiet, so the human returns to a settled queue and a fresh session.
- A human-filed idea is picked up within minutes regardless of clock — requested work never waits for a window.
- The external contributor forks, runs their own sessions, files cross-fork PRs; conflicts (if any) are ordinary git merges, and every external merge is human-approved.
- Sentry storms produce one issue per cluster, not one per event (after the debouncing phase lands).
- No new infrastructure: optimistic concurrency is git's native model; time windows are cron; concurrency groups are a GitHub Actions primitive.

### Negative

- The two windows (`work-hours` 09:00–12:00, `overnight` 01:00–04:00) mean a Medium agent-discovered issue filed at 13:00 waits until that night's 01:00 `overnight` window for pickup. Accepted: the human explicitly wants afternoons/evenings quiet, and Critical/High bypass the window anyway.
- The feature plan-gate adds one round-trip (post approach → await approval) before a feature is built. Accepted: the expensive mistake for a feature is building the wrong thing; a plan comment is cheap to review.
- Optimistic concurrency means a wasted implementer run is possible — two runs touching the same files, the second aborts at its rebase pre-flight. Accepted: a wasted run is cheap; branch isolation guarantees no corruption.

### Neutral

- A session beacon (detect when the human is interactively active and pause async agents) was designed and deliberately deferred — branch isolation makes it non-load-bearing. It can be added later if a real overlap conflict ever occurs; the design is recorded in the PLAN.
- The `work-hours` definition is a repo-level constant; changing it is a one-line workflow edit.

## Pros and Cons of the Options

### Sub-decision 1: Concurrency model

| Option | Pros | Cons |
|---|---|---|
| **Optimistic — branch isolation** (chosen) | Git's native model; zero new infra; conflicts are ordinary merges; already partly practiced (implementer uses `impl/` branches + a rebase pre-flight) | A wasted run is possible when two runs touch the same files |
| Pessimistic — session beacon / lease | Avoids even *starting* a run that would conflict | New coordination state (repo variable or DynamoDB TTL item); solves a problem branches already solve; time windows already cover most overlap |

Optimistic concurrency is the correct default for version-controlled work — locking is reserved for high-cost, unrecoverable conflicts, which a git merge conflict is not.

### Sub-decision 2: Scheduling

| Option | Pros | Cons |
|---|---|---|
| **Time windows** (chosen) | Predictable; human controls when surprise-work happens; cron is trivial | A window-edge issue waits for the next window |
| Always-on reactive | Lowest latency | Surprise merges at any hour; no quiet period |
| Pure overnight-only | Maximal quiet | Slow; nothing moves during the day |

### Sub-decision 3: Work routing

| Option | Pros | Cons |
|---|---|---|
| **Route by source × type × severity** (chosen) | Human-requested work is fast; autonomous work is batched; matches the surprise-control principle | Requires a source signal (issue author / `source:` label) and a type signal (`feature-request` / `bug`) |
| Severity-only routing (status quo) | Simple | Conflates "how bad a bug is" with "what kind of work this is"; a feature has no severity |

### Sub-decision 4: Feature handling

| Option | Pros | Cons |
|---|---|---|
| **Plan-gate features, not bugs** (chosen) | Human judgment lands on the approach — the high-value call — without babysitting execution | One round-trip before a feature is built |
| No gate, auto-merge all | Fastest | No human checkpoint on feature direction; risk of building the wrong thing |
| No gate, human merges | Human sees the result | Human reviews after the work is done, when changing the approach is expensive |

### Sub-decision 5: Promotion authority

| Option | Pros | Cons |
|---|---|---|
| **triage-bot promotes agent-discovered work** (chosen) | One scheduled actor already scanning issues; no separate workflow; promotion respects the window naturally | Promotion is a reasoning judgment — must run at triage-bot's Tier 2 (Sonnet), not Tier 1 |
| Dedicated promoter workflow | Single responsibility | Another workflow to maintain for no added capability |
| Human-only promotion | Maximum control | The human becomes the bottleneck the autonomous team exists to remove |

Human-filed issues are exempt from promotion entirely — filing the issue *is* the triage.

## Implementation notes

- Implementation companion: [`PLAN_async_orchestration_architecture.md`](../../PLAN_async_orchestration_architecture.md) — rollout phases A–E, workflow snippets, label conventions. Consumed when all phases land.
- Affected workflows: `.github/workflows/claude-implementer.yml` (window/source gate), new `.github/workflows/triage-scan.yml` (scheduled scan).
- Affected agents: `plugins/ai-team/agents/implementer.md` (routing table + feature plan-gate), `plugins/ai-team/agents/triage-bot.md` (promoter logic, scheduled trigger).
- New: `CODEOWNERS` at repo root (reviewer routing; branch-protection rules are a repo-settings change applied separately by the human).
- Concurrency: `claude-implementer.yml` already carries a per-issue concurrency group with `cancel-in-progress: false`; branch isolation (`impl/<slug>-<issue>` branches) and a rebase pre-flight are already in `implementer.md`. Sub-decision 1 ratifies that existing design rather than replacing it.
- Label conventions: routing uses the existing `feature-request` vs `bug`/`defect` labels (no new `type:*` taxonomy introduced) and the existing `ready-for-implementer` gate.
- Human-filed pickup: `claude-implementer.yml` triggers on `issues: opened` for human-authored issues (author type `User`, not `Bot`) carrying `bug`/`defect`/`feature-request`. This is the concrete realization of "pre-promoted by the act of filing" — the `opened` event is itself a human action, so it triggers the implementer directly, with no promoter and no label round-trip (which also sidesteps the `GITHUB_TOKEN` no-cascade rule). Agent-filed issues are excluded from this path and still flow through the in-window promoter.

## Links

- [PLAN_async_orchestration_architecture.md](../../PLAN_async_orchestration_architecture.md) — the implementation companion.
- [GitHub Actions concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency) — `cancel-in-progress: false` for sequential/stateful work.
- [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) — researched; an interactive-parallelism feature, deliberately not part of this async-orchestration design.
- [ADR-0011 — AI workflows](0011-ai-workflows.md) — the agent roster this ADR schedules and routes.
- [ADR-0016 — finding lifecycle](0016-finding-lifecycle-calibration-deferral.md) — calibration + deferral; this ADR extends it with promotion authority.
