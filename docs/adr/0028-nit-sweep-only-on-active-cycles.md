# ADR-0028: Nit cleanup-sweep only on cycles that already do real work

- **Status:** Accepted
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, signal-to-noise

> **Format:** MADR 4.x. Single-decision ADR. Refines the spare-capacity sweep in [ADR-0020](0020-fleet-orchestration.md) and the deferral policy in [ADR-0016](0016-finding-lifecycle-calibration-deferral.md).

## Context and Problem Statement

`deferred-until-adjacent` nits drain two ways: bundled into a real PR when the implementer already touches that directory (ADR-0016 "While here"), and via the promoter's **spare-capacity sweep** — when the promoter dispatches fewer than `FLEET_MAX_DISPATCH` real promotions, it spends each leftover slot dispatching a cleanup-only run (ADR-0020).

As written, the sweep fires on *any* cycle with spare capacity — **including a cycle with zero real promotions** (all six slots idle → all six become nit-only cleanup runs). That has two costs: it works nits when no real code is moving (against ADR-0016's "only when adjacent work touches it" principle), and nit-only runs have been a source of the implementer **colliding with itself** — multiple in-flight nit PRs / fix-and-revert churn on the same low-value changes.

Should the sweep run on cycles with no real work?

## Decision Drivers

- **Nothing exploitable is ever a nit.** Per the security-reviewer rubric, a finding with a realistic attack path is `Critical`/`High` (and auto-picks-up, never deferred); only no-attack-path hardening lands at `Low`. So deferring a nit-only cycle delays no real security fix.
- **Reduce self-collision churn.** Fewer nit-only runs means fewer concurrent nit-touching PRs and less fix-and-revert thrash.
- **Keep nits flowing when the loop is already active.** Spare capacity on a real-work cycle should still drain nits — that's productive use of a warm cycle.

## Considered Options

- **Option A:** Keep firing the sweep whenever there's spare capacity (status quo).
- **Option B:** Gate the sweep on "≥1 real promotion dispatched this cycle"; no nit-only cycles.

## Decision Outcome

Chosen option: **Option B.** The spare-capacity sweep runs only when the promoter has already dispatched at least one real promotion this cycle *and* has leftover capacity under `FLEET_MAX_DISPATCH`. On a cycle with zero real promotions, no sweep fires; the nits wait for a cycle that has real work (or get bundled via adjacency when a real fix touches their directory). Manual `mode=cleanup-sweep` dispatch is unaffected — a human can still drain nits on demand.

## Consequences

### Positive

- Nits are only worked when the loop is already doing real work — matching ADR-0016's intent and cutting nit-only self-collision churn.
- No exploitable fix is delayed (exploitable ⇒ High+ ⇒ auto-pickup, never a nit).

### Negative

- On a stretch of cycles with no promotable real work but open nits, those nits sit longer. Mitigated by the quarterly sweep + 180-day re-triage (ADR-0016) and by manual `cleanup-sweep` dispatch.

### Neutral

- A residual self-collision path remains: on an active cycle, a real dispatch and a sweep can target the same repo. Bounded by "never the same repo twice" within the sweep and the implementer's pre-flight rebase; a tighter "don't sweep a repo getting a real dispatch this cycle" guard is a possible follow-up, not in scope here.

## Pros and Cons of the Options

### Option A: sweep on any spare capacity

- ✅ Pro: Maximises use of idle runs to drain backlog.
- ❌ Con: Works nits with no real code moving; nit-only runs drive self-collision churn.

### Option B: sweep only on active cycles (chosen)

- ✅ Pro: Ties nit-work to real-work cycles; less churn; delays no real fix.
- ❌ Con: Idle-but-not-empty cycles don't drain nits (mitigated by quarterly sweep + manual dispatch).

## Implementation notes

- Workflow: `.github/workflows/triage-scan.yml` — the SPARE-CAPACITY SWEEP instruction in the triage-bot prompt now requires ≥1 real promotion this cycle.
- Loop diagram: `docs/diagrams/autonomous-loop-flow.md` — the nit path shows adjacency bundling on real work + the active-cycle-gated sweep.

## Links

- [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — the deferral/"While here" policy this refines.
- [ADR-0020](0020-fleet-orchestration.md) — the spare-capacity sweep this gates.
- [ADR-0026](0026-agentic-implementer.md) — the implementer modes (A bundling, C cleanup-sweep).
