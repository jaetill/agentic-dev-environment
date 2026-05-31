# ADR-0029: The promoter owns nit-adjacency selection; the implementer validates and executes

- **Status:** Accepted
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, signal-to-noise

> **Format:** MADR 4.x. Single-decision ADR. Supersedes the implementer-side "While here" adjacency *discovery* in [ADR-0016](0016-finding-lifecycle-calibration-deferral.md); keeps that ADR's deferral concept and caps.

## Context and Problem Statement

`deferred-until-adjacent` nits are bundled into a real PR when the implementer is already working that area. Under [ADR-0016](0016-finding-lifecycle-calibration-deferral.md), the **implementer** discovers them itself: while working issue X, it scans open deferred nits citing files in the same directory and bundles up to a cap into its PR.

That makes the worker also a scheduler — the implementer picks its own work off the queue. The promoter is meant to manage the implementer's workload; selection belongs there, not in the agent doing the writing. A naive fix — having the promoter *promote* the nit separately — would dispatch a second run opening a second PR on the same file, re-creating the self-collision [ADR-0028](0028-nit-sweep-only-on-active-cycles.md) just reduced.

How do we move adjacency selection to the promoter without creating a colliding second PR?

## Decision Drivers

- **Scheduler owns the workload; worker executes.** The implementer should stop hunting the queue.
- **No second PR on the same file.** A bundled nit must land in the *same* PR as the real work.
- **The bundling safety check needs the code.** Only the implementer sees the actual diff; the promoter sees the issue's *claimed* file, which can be stale or wrong.
- **A mis-selected nit must not be lost or cause churn.**

## Decision Outcome

Chosen option: **promoter selects into the same dispatch; implementer validates and executes.**

- **Promoter** (`triage-scan.yml`): when it promotes a real finding that cites file `F`, it also collects open `deferred-until-adjacent` nits citing **the same file `F`** (cap: `min(floor(total/2), 4)` per parent, mirroring ADR-0016) and passes them *in the same dispatch* via a new `bundle_issues` input. It never dispatches a nit on its own, so no extra `FLEET_MAX_DISPATCH` slot is consumed — a bundled nit rides **free**. Matching is **same-file** (tighter than ADR-0016's same-directory).
- **Implementer**: no longer discovers nits *for the fix-PR adjacency bundle*. It works the parent issue, then for each `bundle_issues` nit **confirms the nit's cited file is one its change actually touched**; it bundles the matches into its single PR's "While here" section and **drops** the rest. On a drop, if it can determine the nit's *actual current* location from the code (e.g., a stale/renamed path), it **edits the nit issue to correct the cited file:line** so the promoter won't re-mispredict it; otherwise it leaves a one-line note. Dropped nits stay open and `deferred-until-adjacent`.

## Consequences

### Positive

- Clean separation: the promoter manages workload; the implementer stops picking off the queue.
- Bundled nits ride free — no `FLEET_MAX_DISPATCH` slot, no second PR, no added collision surface.
- Same-file matching is more precise than same-directory; fewer spurious bundles.
- Drop-and-correct stops the same mis-prediction from repeating.

### Negative

- The promoter matches on the issue's *claimed* file, so some selections will be dropped at the implementer (the change landed elsewhere). Cost is the implementer's evaluation, not a wasted run; drop-and-correct and same-file matching keep it low.
- Human-filed work picked up directly (the implementer's `initial` job, not via the promoter) no longer bundles nits — those drain via promoter-bundled agent findings, the active-cycle sweep (ADR-0028), and the quarterly sweep.

### Neutral

- The dropped-nit backstop is unchanged: a nit never organically touched is still caught by the quarterly sweep / 180-day re-triage (ADR-0016).

### Sidecar removal (resolved)

- The implementer's Mode-A **sidecar cleanup PR** — a standalone nit-drain it opened on *every* dispatch, independent of the promoter and the ADR-0028 active-cycle gate — is **removed**. Standalone nit-draining is now exclusively the promoter's **Mode-C cleanup-sweep** (gated to active cycles, ADR-0028). The implementer no longer drains the queue off its own initiative at all: in Mode A it touches only its parent issue plus the promoter-supplied adjacent nits. This supersedes the two-PR (fix + sidecar) behaviour of ADR-0020.
- **Tradeoff:** non-adjacent nits in untouched code drain more slowly — via Mode-C and the quarterly sweep — which matches ADR-0016's deferred-until-adjacent intent (don't fix nits in isolation). Mode-C is now the *sole* standalone release valve, so its cadence and the quarterly sweep / 180-day re-triage are the levers if nits accumulate.

## Pros and Cons of the Options

### Implementer self-discovers (ADR-0016 status quo)

- ✅ Pro: The agent has the diff, so adjacency is exact.
- ❌ Con: The worker also schedules — it picks its own queue, which is the coupling this removes.

### Promoter promotes the nit as a separate dispatch

- ✅ Pro: Pure scheduler ownership.
- ❌ Con: Second PR on the same file → self-collision. Rejected.

### Promoter selects into the same dispatch; implementer validates (chosen)

- ✅ Pro: Scheduler owns selection; one PR; nits ride free; implementer keeps only the code-level safety check.
- ❌ Con: Promoter's claimed-file match isn't perfect; mitigated by validate-and-drop + drop-and-correct.

## Implementation notes

- `triage-scan.yml` — promoter Pass 2 gathers same-file deferred nits and passes `-f bundle_issues=<n,…>`.
- `claude-implementer.yml` — new `bundle_issues` workflow_dispatch input; the dispatch job passes it to the implementer prompt.
- `plugins/ai-team/agents/implementer.md` — Mode A: remove self-driven "While here" discovery; add "bundle the supplied nits after confirming same-file against your actual diff; drop + correct the rest."
- Loop diagram: `docs/diagrams/autonomous-loop-flow.md` — the adjacency edge now originates from promoter selection, same-file.

## Links

- [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — deferral policy + caps this refines (moves *discovery* from implementer to promoter).
- [ADR-0020](0020-fleet-orchestration.md) — the promoter/dispatch this extends.
- [ADR-0026](0026-agentic-implementer.md) — the implementer; its "While here" bundling now executes promoter-selected nits.
- [ADR-0028](0028-nit-sweep-only-on-active-cycles.md) — the active-cycle sweep; this complements it on the bundling path.
