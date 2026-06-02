# ADR-0026: Agentic implementer — autonomous code authoring with bounded scope

- **Status:** Accepted — retroactively documented 2026-05-31. The implementer shipped under an informal "ADR-0013" reference that collided with [ADR-0013](0013-grafana-cloudwatch-pull.md) (Grafana/CloudWatch pull); [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) flagged the collision and deferred renumbering. This ADR gives the decision a real number and consolidates the as-built design.
- **Date:** 2026-05-31 (documenting a decision in effect since the platform's autonomous-team build-out)
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, autonomy, ci-cd

> **Amended by [ADR-0030](0030-all-dispatch-through-promoter.md):** dispatch routing changed — all implementer dispatch now goes through the promoter (no direct bypass). See the *Impacted ADRs* table in ADR-0030 for the specific change to this ADR.

> **Amendment (2026-06-01b) — scope cap recalibrated to 400 LOC / 8 files / 3 components.** The original 50 / 3 / 1 was deliberately tight for an early, less-capable author. With mature models, the slice-target behaviour below (decompose, never refuse-to-human), and the review battery + auto-merge guards as the real correctness gates, the bound was over-constraining — it forced excessive slicing of legitimately-bounded work. The numbers are a tunable blast-radius bound, not a capability statement; raising them keeps a real ceiling while cutting false over-cap churn. New values: **400 lines of production code, 8 source files, 3 components**. Owned here; cited elsewhere via reference to this ADR rather than inlined, so it can't go stale again.

> **Amendment (2026-06-01) — the scope cap is a slice target, not a refusal gate.** The cap (the size bound below) stays as the **blast-radius bound** on an autonomously-merged, agent-reviewed change — but its *response to over-cap work changes*. Originally: refuse and push back to the architect/human to decompose ("friction by design"). Now: **the implementer decomposes the problem itself**, ships the smallest coherent, independently-shippable slice, and tracks the remainder (a partial slice uses `Refs #n`, never `Closes`; a follow-up captures the rest so the loop re-dispatches the next slice). It never escalates *size* to a human. Rationale (Jason, walking the SCOPE node): mature models + plan mode can handle arbitrary complexity *if forced to work in small slices*; the cap is the forcing function, and the human-escalation dead-end was a solo-operator momentum sink. The bound itself is unchanged — capability justifies *how over-cap work is handled*, not removing the bound (an auto-merged change is reviewed only by correlated agents that also degrade at scale, and the cap also bounds a prompt-injection blast). This is the last size-bound now that the feature plan-gate is moving to human intake ([[project_intake_planning_separation]]). Reflected in `implementer.md` (Scope cap section) and `claude-implementer-reusable.yml`.

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. This is a *retroactive* record: the decision was made and shipped before it was filed. The Decision Outcome below describes the as-built implementation found in `plugins/ai-team/agents/implementer.md`, `plugins/ai-team/agents/iac-implementer.md`, and `.github/workflows/claude-implementer.yml`; the Context and Options reconstruct the frame that produced it.

## Context and Problem Statement

The platform's original AI-workflow architecture ([ADR-0011](0011-ai-workflows.md)) defined a roster of *reviewer and helper* agents — code-reviewer, security-reviewer, test-writer, e2e-tester, doc-keeper, iac-* — to amplify a human author. Every agent reviewed, tested, or documented work the **human** wrote. That left one bottleneck untouched: implementation itself. As the fleet grew, routine fixes (a reviewer's defect finding, a Sentry production error, a small feature) piled up waiting on the one human to write the code.

The decision to add an autonomous **implementer** — an agent that writes production code, not just reviews it — was made and shipped, but never filed as an ADR. It was referenced informally as "ADR-0013," a slot [ADR-0013](0013-grafana-cloudwatch-pull.md) had already taken for the Grafana/CloudWatch decision, so the reference dangled. This ADR fixes that.

The question it answers: **how can an agent author production code autonomously without breaking the platform's safety story** — the property that no single actor both writes and approves its own changes — and without letting a runaway or mistaken agent cause unbounded damage?

## Decision Drivers

- **Remove the implementation bottleneck** for routine, bounded work so the human directs rather than types.
- **Preserve the safety story.** The platform's safety rests on separation: reviewers review, an implementer implements; no agent approves its own code.
- **Bound the blast radius.** An autonomous author must not be able to make large, cross-cutting, or destructive changes unsupervised.
- **Different risk profiles need different agents.** Application code that fails CI is recoverable; a bad `tofu apply` can destroy resources or leak secrets.
- **The human stays the director.** Work enters by an explicit gate, not by the agent's own initiative.

## Considered Options

- **Option A:** Keep the human as the sole author (status quo); agents only review/test/doc.
- **Option B:** A single, unrestricted coding agent that picks up any issue and can change anything.
- **Option C:** A bounded implementer agent, kept strictly separate from the reviewers, scope-capped, with a separate IaC counterpart.

## Decision Outcome

Chosen option: **Option C.** Introduce the **implementer** agent (the "developer" role) and an **iac-implementer** counterpart, with the following as-built design:

- **Three modes.** *Mode A* — initial implementation (issue → new PR). *Mode B* — fix iteration (review feedback → push to the same PR), capped at **3 iterations** before escalating to the human. *Mode C* — cleanup sweep (dispatched, drains `deferred-until-adjacent` nits, no originating issue).
- **Scope cap.** A PR may not exceed **400 lines of production code, 8 source files, or 3 components** (recalibrated from 50 / 3 / 1, see amendment 2026-06-01b). Over the cap, the implementer **decomposes the problem itself and ships the smallest coherent slice**, tracking the remainder — it does not refuse or escalate size to a human (amended 2026-06-01; see top). (Tests and docs don't count toward the LOC cap.)
- **Hard authority limits.** Never commit to `master`; never modify IaC (`terraform/`, `*.tf`) — that is `iac-implementer`; never modify workflows unless the issue is labelled `scope:ci`; never modify ADRs/standards/agent definitions — those are the architect's; **never approve, force-merge, or admin-merge its own PR.**
- **Dispatch gating.** The implementer engages only on a trusted signal: a `ready-for-implementer` label (applied by a maintainer or the fleet promoter), or an auto-pickup label — `source:sentry`, `source:cloudwatch`, or `severity:critical`. Human-filed features take a plan-gate (defer to [ADR-0017](0017-async-orchestration.md)); `defect`/`bug` skip it.
- **IaC split.** `iac-implementer` is a separate agent with read-only AWS access and a `tofu plan`-only, no-`apply`, ≤5-resource cap, because IaC's failure modes (destroyed resources, dropped state, exposed secrets) differ fundamentally from application code.

Option B was rejected because an unrestricted author breaks the separation property and has no blast-radius bound. Option A was the bottleneck this removes.

## Consequences

### Positive

- Routine work flows without the human writing code; the human directs and approves.
- The safety story is intact: writer and approver are different agents, enforced by the workflow (the implementer cannot self-merge).
- Damage is bounded by the scope cap, the 3-iteration cap, the authority limits, and the IaC split.

### Negative

- The scope cap forces larger work into a sequence of small slices the implementer decomposes itself (amended 2026-06-01) — progress per cycle, at the cost of an issue sometimes taking several slices to fully close.
- An autonomous author plus optimistic concurrency means a wasted run is possible (two runs touching the same files; the second aborts at its rebase pre-flight). Accepted: a wasted run is cheap; branch isolation prevents corruption.

### Neutral

- The implementer's *operating* concerns — when it runs, how work is routed and serialized, the feature plan-gate — are owned by [ADR-0017](0017-async-orchestration.md); its self-modification behaviour by [ADR-0019](0019-team-self-modification.md); merge of its PRs by [ADR-0021](0021-autonomous-merge.md) and [ADR-0023](0023-origin-based-autonomy-boundary.md). This ADR owns the *agent and its bounds*; those own its *orchestration*.

## Pros and Cons of the Options

### Option A: human as sole author

- ✅ Pro: Maximum control; no autonomous-authoring risk.
- ❌ Con: The implementation bottleneck the platform exists to remove remains.

### Option B: single unrestricted coding agent

- ✅ Pro: Simplest to build; one agent does everything.
- ❌ Con: Breaks the write/approve separation that is the platform's safety story.
- ❌ Con: No blast-radius bound — a mistaken or adversarially-prompted agent can change anything, including IaC.

### Option C: bounded implementer + separate reviewers + IaC split (chosen)

- ✅ Pro: Preserves separation; bounds damage; matches risk profile to agent.
- ✅ Pro: Composes with the existing reviewer roster and orchestration ADRs.
- ❌ Con: More moving parts (two implementer agents, scope-cap refusals, escalation paths).

## Implementation notes

- Agent specs: `plugins/ai-team/agents/implementer.md`, `plugins/ai-team/agents/iac-implementer.md`.
- Workflow: `.github/workflows/claude-implementer.yml` (Mode A `initial` + `initial-iac`, Mode B `fix-iteration`, Mode C `cleanup-sweep`, `manual-dispatch`).
- Guardrails are also encoded in `docs/standards/10-ai-workflows.md`.
- All prior "ADR-0013 (autonomous-team / implementer)" references across the workflows, agent specs, the loop diagram, and ADR-0016/0025 are repointed here; the Grafana references to ADR-0013 are unchanged.

## Links

- [ADR-0011](0011-ai-workflows.md) — the AI-workflow architecture and agent roster this extends with an authoring agent.
- [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — finding lifecycle; flagged the "ADR-0013" number collision this resolves.
- [ADR-0017](0017-async-orchestration.md) — scheduling, routing, concurrency, and the feature plan-gate for the implementer.
- [ADR-0019](0019-team-self-modification.md) — the competence gate and self-modification rules for implementer work on the platform repo.
- [ADR-0021](0021-autonomous-merge.md) — autonomous merge of implementer fix PRs.
- [ADR-0023](0023-origin-based-autonomy-boundary.md) — the origin-based autonomy boundary governing which implementer PRs auto-merge.
- [ADR-0025](0025-owner-guard-on-platform-opened-pickup.md) — owner-guard on the platform repo's Mode-A opened pickup.
