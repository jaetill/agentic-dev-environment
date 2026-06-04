# ADR-0033: Opted-in features build by default — the plan-gate becomes opt-in

> **Superseded by [ADR-0036](0036-human-intake-model.md) (2026-06-01):** the `plan-first` opt-in plan-gate is **retired entirely**. Feature planning (the *what*) moved to human intake (formulation → `approved`); with no feature carrying `plan-first`, the in-loop PLAN PHASE, its labels (`plan-first` / `awaiting-plan-approval` / `plan-approved`), and the `initial` job that ran them are removed. This ADR's reasoning — that a mid-stream plan-approval is a redundant checkpoint because the review battery is the real gate — stands and is what justified pushing planning all the way to intake. The historical text below is preserved as the record of the intermediate (opt-in) step.

- **Status:** Superseded by [ADR-0036](0036-human-intake-model.md). (Originally Accepted — ratified by Jason 2026-05-31. Reversed the default set by [ADR-0017](0017-async-orchestration.md)'s feature plan-gate; the gate was preserved as an opt-in, now retired.)
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, autonomy

## Context and Problem Statement

[ADR-0017](0017-async-orchestration.md) gave `feature-request` issues a **plan-gate**: the implementer posts an approach, labels `awaiting-plan-approval`, and stops until a human applies `plan-approved` (or `skip-plan` to bypass). `defect`/`bug` issues skip it. The intent was for the human to approve the *approach* before code is written.

But a feature only reaches the implementer after a human already gated it in — a trusted maintainer applied `ready-for-implementer` (or the owner filed it). That opt-in is the human approving the *what*. And human-origin work is gated **again** at the end: it holds for human merge ([ADR-0023](0023-origin-based-autonomy-boundary.md)). So a human-filed feature already passes two human checkpoints — start and ship. The plan-gate is a **third** checkpoint in the middle, and its only marginal value over "just build it, the human reviews at merge" is catching a wrong *approach* before a build cycle is spent. That value mostly evaporates in practice: a feature large enough to need real approach-steering blows the implementer's scope cap (50 LOC / 3 files / 1 component) and routes to the architect anyway, so the features that actually reach the build are small ones where a forced plan review is mostly ceremony.

## Decision Drivers

- Don't make the human approve the same small feature twice (opt-in, then plan, then merge).
- The review battery — code-review, security-review, functional-test, e2e-test — is the real correctness gate; it runs on every PR regardless.
- Preserve the *ability* to steer an approach pre-build for the occasional gnarly feature.
- Increasing autonomy as trust grows is the explicit direction (Jason).

## Considered Options

- **Option A:** Keep the plan-gate as the default for all features (status quo, ADR-0017).
- **Option B:** Flip the default — features build like defects; a `plan-first` label opts *into* the plan phase.
- **Option C:** Remove the plan-gate entirely (no opt-in); steer only by writing the approach into the issue body.

## Decision Outcome

**Chosen: Option B.** A `feature-request` builds by default — it follows the same build phase as a `defect`/`bug`. The plan phase runs **only** when the issue carries a new `plan-first` label (the human opting in to review the approach before code). The existing `plan-approved` label is kept as the continuation that re-triggers the build after a `plan-first` plan phase; `skip-plan` is retired (build is now the default, so an opt-out is unnecessary).

Option C was rejected as slightly too far for now — `plan-first` is cheap insurance and keeps the steering option one label away. The pre-existing escape (the human writes the approach into the issue body, and the implementer implements *that*) still works on top of either.

The safety case: removing the *forced* plan-gate loses no correctness guarantee, because every resulting PR still passes the full review battery before it can merge, and the scope cap still bounds how far any single build can go.

## Consequences

### Positive

- One fewer forced human checkpoint per feature; the human approves once (opt-in) and ships at merge.
- Behaviour is uniform: features and defects share the build path, with the plan phase as a labelled exception.
- The steering capability is retained (`plan-first`) for the cases that warrant it.

### Negative

- The human reviews a *built* PR rather than a *plan* for in-scope features — marginally more sunk-cost-biased ("it works, ship it"), and a rejected approach wastes a build cycle. If wrong-but-working approaches start landing, that is the signal to revert the default.
- **Drift tax:** the plan-gate logic is duplicated in `implementer.md` (single-source via the plugin) and inline in each repo's `claude-implementer.yml` (copied per repo, [ADR-0018](0018-workflow-distribution.md) gap). The platform repo and the agent spec are updated here; the 7 app-repo workflow copies need the same inversion — tracked as propagation work.

### Neutral

- This is a default-direction change, not a capability removal. The plan phase machinery still exists, now keyed on `plan-first` instead of the absence of `plan-approved`/`skip-plan`.

## Pros and Cons of the Options

### Option A: keep the plan-gate default

- ✅ Pro: the human always sees the approach before code.
- ❌ Con: a third human checkpoint on work already gated at opt-in and merge; ceremony for the small features that reach the build.

### Option B: flip the default, `plan-first` opt-in (chosen)

- ✅ Pro: removes the redundant checkpoint while keeping the steering option; uniform build path.
- ❌ Con: approach review becomes opt-in, so a wrong approach is caught at merge (after a wasted build) rather than before.

### Option C: remove the plan-gate entirely

- ✅ Pro: simplest; least machinery to maintain.
- ❌ Con: no one-label steering option; the only pre-build steering is writing the approach into the issue body.

## Implementation notes

- `implementer.md` — invert the "Mode A feature plan-gate" section: build is the default for `feature-request`; the plan phase runs only with `plan-first`. Update the anti-pattern list (skipping the plan phase is no longer an anti-pattern; ignoring `plan-first` is).
- `claude-implementer.yml` (platform + 7 app copies) — Step 1 phase determination inverts: `feature-request` + `plan-first` → PLAN PHASE; otherwise BUILD PHASE. The `initial` job's continuation trigger keeps `plan-approved`, drops `skip-plan`.
- Loop diagram — the `PHASE` node flips to "feature-request **with** `plan-first`?".

## Links

- Amends [ADR-0017](0017-async-orchestration.md) — reverses the feature plan-gate default.
- Relates to [ADR-0023](0023-origin-based-autonomy-boundary.md) — the merge-time human checkpoint, the *next* candidate for the same opt-in/autonomy treatment for opted-in features.
- Constrained by the implementer scope cap and the review battery, which remain the real correctness gates.
