# ADR-0038: Compositional self-changes route through human formulation, not a bespoke architect-stop

- **Status:** Accepted
- **Date:** 2026-06-03
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, intake, self-modification

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Amends [ADR-0019](0019-team-self-modification.md) sub-decision 3 (the competence gate's *routing*) and extends [ADR-0036](0036-human-intake-model.md) (a self-change proposal is an intake class). The firewall itself is unchanged — only where the human ratification happens.

## Context and Problem Statement

When the implementer hits a **compositional self-change** (a change to the team's own gates, agent roster, standards, or security posture — ADR-0019 sub-decision 3), it STOPs and routes to the architect, who proposes an ADR the human ratifies *before* implementation. In the loop diagram this is a terminal sink: `STOP — route to architect · propose ADR · human ratifies`.

But that is the *same act* the human-intake model (ADR-0036) already exists for: a thing the human must scope and decide before it can be built. We now have **two** human-decision surfaces — Formulation (features/bugs) and the architect-stop (self-changes) — that do the same job. Two surfaces means two places to watch, two lifecycles, and a self-change that's invisible to the intake backlog (it doesn't show in the cockpit's Formulation panel; it's a dead-end on a PR).

Should a compositional self-change be its own terminal sink, or should it enter the same human-intake/formulation flow as everything else the human owns the "what" of?

## Decision Drivers

- **One human-decision surface.** A self-change *is* a human "what" decision; it belongs where those live (intake/formulation), not as a parallel sink in the implementer's lane.
- **The firewall is non-negotiable.** ADR-0019's guarantee — the loop cannot change its own gates/roster/standards/security without a human-ratified ADR — must survive the move exactly.
- **Visibility.** A pending self-change should be a tracked backlog item (Formulation panel), not a comment on an abandoned PR.
- **Don't duplicate.** Same instinct as the rest of the platform: one source of truth, no parallel lifecycle to keep in sync.

## Considered Options

- **Option A — keep the bespoke architect-stop** (ADR-0019 status quo): compositional self-change → terminal "route to architect" → ADR → human ratifies → build.
- **Option B — route into human formulation** (chosen): the implementer files the compositional self-change as a `needs-formulation` + `requires-adr` intake issue; it flows through ADR-0036's formulation → approve gate (architect drafts the ADR during formulation, human ratifies by approving); on approval it re-enters the loop and builds, still holding for human merge (ADR-0023).

## Decision Outcome

Chosen option: **Option B — route compositional self-changes through human formulation.**

On detecting a compositional/standards/security/rail-enforcer self-change (or realising mid-build that a change requires an ADR), the implementer does **not** build it and does **not** draft the ADR. It files a platform-repo issue labelled `needs-formulation` + `requires-adr` + `compositional-self-change`, describing the proposed change, and stops. That issue lands in the **Formulation** state (ADR-0036, Ⓗ human-intake lane). There, the architect drafts the paired ADR (Status: Proposed) and the human ratifies by moving it to `approved`. Only then does it enter the promoter and build — and, being a compositional self-change, it still holds for human merge per ADR-0023.

The firewall is preserved because every guarantee is carried by a tag, not by the bespoke sink:
- **Human ratifies** — now via formulation → `approved` instead of a one-off "ratify before implement." Same human, same veto.
- **ADR required** — the `requires-adr` tag means it cannot be approved/built without the ratified ADR.
- **Heavier review** — unchanged; the platform repo runs the full review battery incl. security-review on the eventual PR.
- **Human-merge hold** — unchanged; ADR-0023 still holds compositional-self-change PRs for human merge.
- **One-directional boundary** — unchanged; the credential model (ADR-0019 sub-decision 6) is untouched.

## Consequences

### Positive

- One human-decision surface; self-changes show up in the Formulation panel like every other thing awaiting your scoping.
- The implementer's lane loses a terminal sink — a self-change is a human concern, so it lives in the human lane.
- Same lifecycle, tracking, and tooling as feature intake — nothing parallel to maintain.

### Negative

- A self-change now carries intake state (`needs-formulation`) it didn't before — slightly more label bookkeeping. Accepted; it's the cost of unifying.
- If the `requires-adr` tag is dropped, a self-change could slip through formulation as a vanilla feature. Mitigated: the architect/approval step checks for the ratified ADR, and ADR-0023's human-merge hold is a second backstop.

### Neutral

- The architect's role is unchanged in substance — it still drafts the ADR; it just does so during formulation rather than on a terminal PR.
- Mechanical/additive self-changes are unaffected: ADR-0032's auto-lane and the "mechanical → implementer does it directly" path (ADR-0019 sub-decision 3) are untouched. Only the *compositional* branch reroutes.

## Pros and Cons of the Options

### Option A: bespoke architect-stop (status quo)

- ✅ Pro: the self-change firewall is visibly its own thing.
- ❌ Con: a second human-decision surface duplicating intake; the pending self-change is invisible to the backlog; a dead-end on a PR.

### Option B: route through formulation (chosen)

- ✅ Pro: one human-decision surface; tracked + visible; same lifecycle as features; firewall preserved by tags.
- ❌ Con: depends on the `requires-adr` tag riding along (backstopped by the approval ADR-check and the ADR-0023 merge hold).

## Implementation notes

- `plugins/ai-team/agents/implementer.md` — the self-change / "requires an ADR mid-build" handling: file a `needs-formulation` + `requires-adr` + `compositional-self-change` issue (do not draft the ADR, do not build); stop. Replaces "post a comment requesting the architect on this PR."
- `docs/diagrams/autonomous-loop-flow.md` — the `CG` compositional branch routes to `FORM` (human intake) via a relabelled node, not a terminal architect sink.
- `docs/standards/12-self-modification.md` — operational procedure: compositional self-change → `needs-formulation` + `requires-adr` + `compositional-self-change` → formulation (architect drafts ADR) → `approved` → build → human-merge hold.
- Amended-by banners on [ADR-0019](0019-team-self-modification.md) and [ADR-0036](0036-human-intake-model.md).
- Unchanged: ADR-0032 additive auto-lane, ADR-0023 human-merge hold, ADR-0019 sub-decisions 1/2/4/6.

## Links

- [ADR-0019 — team self-modification](0019-team-self-modification.md) — the firewall; sub-decision 3 routing amended here.
- [ADR-0036 — human intake model](0036-human-intake-model.md) — the formulation flow self-changes now enter.
- [ADR-0023 — origin-based autonomy boundary](0023-origin-based-autonomy-boundary.md) — the human-merge hold that remains the merge-time backstop.
- [Standard 12 — self-modification](../standards/12-self-modification.md) — operational procedure.
