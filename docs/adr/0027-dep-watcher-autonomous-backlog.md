# ADR-0027: dep-watcher routes all proposed work to the implementer backlog (no human gate)

- **Status:** Accepted
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, autonomy, dependencies, governance

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. Refines [ADR-0026](0026-agentic-implementer.md) (the implementer) and applies [ADR-0023](0023-origin-based-autonomy-boundary.md)'s "autonomously ship machine-detected work" principle to dependency maintenance.

## Context and Problem Statement

The `dep-watcher` agent reviews Dependabot/Renovate PRs: it auto-merges safe patch/minor/CVE updates and files severity-labelled findings for the rest. Routine findings (`severity:medium+`) already reach the implementer autonomously via the in-window promoter ([ADR-0017](0017-async-orchestration.md)). But two paths still park work on a human:

1. **Tier-2 escalation** (major version bumps): the spec says "draft an ADR, **wait for human acceptance**, then merge."
2. **Dead/unmaintained package**: "file a finding recommending replacement; **don't merge without architect review**."

And a weekly informational digest (`dep-watch` label) is filed for the human to read.

A deprecation or EOL is, by definition, a maintenance signal: loss of future support means future unpatched vulnerabilities, so it *should* be fixed — a human does not need to say so. Parking such work on a human is the bottleneck the autonomous team exists to remove. Should dep-watcher gate any of its work on a human?

## Decision Drivers

- **Machine-detected maintenance is exactly what ADR-0023 says to ship autonomously.** A dep bump, CVE patch, or EOL upgrade is detected by tooling, not requested by a person.
- **Deprecation implies security risk over time.** Fixing it is the default-correct action; requiring human sign-off adds latency, not safety.
- **The implementer pipeline already provides the safety net.** Dep PRs are test-gated; the review battery runs; the scope cap bounces over-large work to the architect; branch isolation prevents corruption. The human checkpoint at *dep-watch* time is redundant with these.
- **Preserve the genuinely-architectural gate.** Adding a *new* external dependency or accepting a non-permissive license is ADR-0003's gated category for supply-chain/legal reasons — that gate is universal to the implementer pipeline, not a dep-watcher decision.

## Considered Options

- **Option A:** Keep the Tier-2 "draft ADR, wait for human" and dead-package architect-review gates.
- **Option B:** dep-watcher routes **all** proposed work to the implementer backlog; the human gets an information-only digest; no dep-watcher human gate.

## Decision Outcome

Chosen option: **Option B.** dep-watcher never waits on a human. Every actionable item it cannot auto-merge is filed as an **implementer-bound issue** (`severity:*` + `ready-for-implementer`) so it enters the implementer backlog directly:

- Major version bumps, EOL/deprecation upgrades, dead-package replacements → filed to the backlog with an impact summary; the implementer does the migration (or, if it exceeds the scope cap, bounces it to the architect — the implementer's gate, not dep-watcher's).
- The weekly dependency report remains a **non-gating information sink** for the human — context, never a checkpoint.
- A genuinely **new external dependency** or a **non-permissive license change** is routed to the backlog tagged `requires-adr:new-external-dep`, so [ADR-0003](0003-ci-cd.md)'s universal gate applies in the implementer pipeline. This is the one residual human touch, and it is ADR-0003 acting fleet-wide, not a dep-watcher-specific gate.

Option A is the bottleneck this removes.

## Consequences

### Positive

- Dependency maintenance — bumps, CVE patches, EOL/deprecation upgrades, dead-package replacements — flows to the implementer with no human in the loop.
- The "machine-detected → ship autonomously" principle (ADR-0023) now covers the dependency surface uniformly.
- The human's only dep-watcher interface is the digest: information, not work.

### Negative

- Autonomous major version upgrades can introduce breaking changes. Accepted: the dep PR is test-gated, the review battery runs, the scope cap bounces over-large migrations to the architect, and branch isolation contains failures. A wasted/blocked run is cheap.

### Neutral

- New-dependency and license decisions still surface `requires-adr` in the implementer pipeline (ADR-0003). If that residual human touch is later deemed unwanted for dep-originated work, it is a one-label change.

## Pros and Cons of the Options

### Option A: keep the human gates

- ✅ Pro: A human reviews every major/dead-package change before it lands.
- ❌ Con: Parks security-relevant maintenance on a human; deprecation fixes wait on sign-off that adds latency, not safety.

### Option B: all work to the implementer backlog (chosen)

- ✅ Pro: No human bottleneck on machine-detected maintenance; consistent with ADR-0023.
- ✅ Pro: Safety is provided by the implementer pipeline's existing gates, not a redundant human checkpoint.
- ❌ Con: Autonomous major upgrades carry breakage risk (mitigated above).

## Implementation notes

- Agent spec: `plugins/ai-team/agents/dep-watcher.md` — Tier-2 escalation and dead-package anomaly route to the implementer backlog (`ready-for-implementer`) instead of waiting on a human ADR; the new-dep/license case carries `requires-adr:new-external-dep`.
- Loop diagram: `docs/diagrams/autonomous-loop-flow.md` — dep-watch findings flow into the severity routing; the weekly digest is a non-gating information sink.

## Links

- [ADR-0023](0023-origin-based-autonomy-boundary.md) — autonomously ship machine-detected work; this applies it to dependencies.
- [ADR-0026](0026-agentic-implementer.md) — the implementer and its scope cap, the safety net for autonomous dep work.
- [ADR-0017](0017-async-orchestration.md) — the promoter that moves severity-labelled findings into the backlog.
- [ADR-0003](0003-ci-cd.md) — the universal new-external-dependency / license ADR gate that still applies in the implementer pipeline.
- [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — finding severity/deferral calibration dep-watcher uses.
