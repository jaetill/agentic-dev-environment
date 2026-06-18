# ADR-0032: Additive self-change auto-lane — agent output-contract tightenings auto-merge under a deterministic gate

- **Status:** Accepted — ratified by Jason 2026-05-31. This ADR *amends the self-change firewall* ([ADR-0019](0019-team-self-modification.md) / [ADR-0023](0023-origin-based-autonomy-boundary.md)), which is human-ratified by design.
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, autonomy, self-modification

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. Introduces a deterministically-gated exception to the human-ratified self-change firewall.

> **Amended by [ADR-0047](0047-firewall-gates-on-capability-delta.md):** this ADR's single-agent-file additive lane is generalized into a *capability-delta* lane covering every self-change — the guard runs on all candidate PRs (no agent-quality / single-file restriction) and holds only on a gate/governance file, guardrail vocabulary, a net-new external action, or a destructive migration.

## Context and Problem Statement

[ADR-0031](0031-promoter-disambiguates-or-closes-vague-findings.md) routes a non-disambiguable vague agent finding to an auto-close plus an *agent-quality* issue that tightens the source agent's output contract. But two existing rules make that fix un-runnable without a human:

- The implementer is forbidden from editing agent definitions — `implementer.md` line 82: *"Modify ADRs, standards docs, or agent definitions. Those are the architect's domain."*
- The architect path is human-ratified — the self-change competence gate (ADR-0019/0023) routes changes to the loop's own agents to a human for ratification.

That firewall is correct in general: the loop must not silently rewrite its own behaviour or loosen its own guardrails. But it is too coarse — it treats a mechanical *"add a required `file:line` field to a finding template"* identically to a compositional *"change how the agent reasons."* The first is a bug-fix to an agent's output; gating it on a human merge re-introduces exactly the bottleneck ADR-0031 set out to remove.

## Decision Drivers

- The loop should fix demonstrated output defects in its own agents without a human merge-gate — a bug-fix in the process, not a change to the process.
- Self-modification of the labor force is the highest-stakes self-change; a qualifying change must be *provably unable* to touch a safety rail.
- Safety must be **externally and deterministically enforced**, never resting on the agent's own claim that a change is "additive."
- No human blocker. After-the-fact visibility is wanted; a forced merge is not.

## Considered Options

- **Option A:** Keep the firewall as-is — every agent edit human-ratified.
- **Option B:** A narrow auto-lane for additive output-contract tightenings, gated by a deterministic external check; everything else stays human-ratified.
- **Option C:** Track-only — file and dedupe the agent-quality issue but never auto-fix.

## Decision Outcome

**Chosen: Option B.** Define a narrow **additive self-change lane**. A PR auto-merges *without* ratification iff a deterministic guard — `additive-self-change-guard`, run **inside the auto-merge gate** (not as a branch-protection required check — that would retroactively block every in-flight PR until it re-ran, re-creating the ADR-0024 deadlock) — confirms **all** of:

1. **Scope** — changed files = exactly one `plugins/ai-team/agents/*.md`, **and that agent is not a rail-enforcer.** The promoter (`triage-bot`) and the architect are excluded from the lane entirely — their edits always go to human ratification, no matter how additive they look. This is structural, ahead of the denylist: the agents that *enforce* safety rails (the promoter holds the prose throttle; the architect holds the governance gate) never auto-edit, so we don't rely on a word-filter catching the right token in the most dangerous files. Eligible agents are the rest — the reviewers, testers, doc-keeper: agents that *produce findings* but enforce no rail.
2. **Size** — at most 8 changed lines (added + removed), tunable.
3. **Guardrail denylist** — no changed line, *added or removed*, matches the protected vocabulary: scope cap, `FLEET_MAX`/throttle, severity calibration, the self-change/competence gate, auto-merge eligibility, origin/human checkpoint, permission/token, model tier, inter-agent routing. A deletion does not disqualify on *presence* (a modification is a delete + an add in git); only a deleted/added line whose *content* is guardrail vocabulary disqualifies.
4. **Origin** — the PR closes an `agent-quality` issue (ADR-0031 machine-origin). That dispatch is **cap-exempt but dedup-bounded** (ADR-0031): the fix is never starved by the `FLEET_MAX` cap, and the one-per-agent dedup keeps the exemption from becoming a storm path.

Any miss → the existing rail: architect → human ratification.

Two properties make this safe:

- **A deletion does not disqualify on presence.** Git renders a modification (`be vague` → `be verbose`) as a delete + an add; only a line's *content* (guardrail vocabulary) can disqualify it. So legitimate tightenings pass, while deleting a guardrail line (`always report security as high severity` → trips on `severity`) does not.
- **The gate, not the agent, enforces the lane.** Because the check is deterministic and external, the implementer may make the edit (a carve to its line-82 prohibition) — a non-conforming diff fails the check and routes to a human regardless of what the implementer intended. The implementer's judgement is never the safety boundary.

Auto-merged self-edits append to a standing, pinned **`agent-self-change-log`** issue (and roll into the weekly digest) for after-the-fact visibility. Non-blocking — no human merge-gate.

## Consequences

### Positive

- ADR-0031's agent-quality fixes flow end-to-end with no human bottleneck.
- The firewall gains a precise seam: mechanical tightenings auto-flow; compositional changes stay human-ratified.
- Safety is externally enforced, not self-asserted. The worst a qualifying change can do is *add* a non-guardrail output requirement to one agent — bounded, recoverable, and logged.

### Negative

- **Residual risk:** within the size cap, a change can make a subtle quality change to one agent's output policy (never a safety rail). Mitigated by the size cap, single-file scope, and the visible log.
- A new guard step in the auto-merge gate and a carve to `implementer.md` line 82 add surface to the merge path and the implementer contract.

### Neutral

- The denylist is a living list: introducing a new guardrail concept into an agent's vocabulary later means adding it to the denylist. It lives next to the guard script and is versioned with it.

## Pros and Cons of the Options

### Option A: keep firewall as-is

- ✅ Pro: simplest, maximally conservative.
- ❌ Con: the human is the bottleneck for every agent tightening; ADR-0031's self-improvement loop is defeated.

### Option B: additive auto-lane (chosen)

- ✅ Pro: removes the bottleneck for the common case; safety is externally, deterministically enforced; bounded, logged blast radius.
- ❌ Con: residual subtle-quality risk within the cap; adds a guard step in the auto-merge gate + an L82 carve.

### Option C: track-only

- ✅ Pro: no firewall change.
- ❌ Con: the fixes never happen autonomously — the "park" ADR-0031 exists to eliminate.

## Implementation notes

- **Guard** — `scripts/additive-self-change-guard.sh`, a deterministic no-LLM classifier (changed-file scope, rail-enforcer exclusion, line-count cap, denylist over `git diff` added+removed lines, `agent-quality` origin). It is invoked by the **auto-merge gate** (`triage-scan.yml`): for a candidate implementer PR the gate runs the guard; `NOT_SELF_CHANGE` → normal flow, `IN_LANE` → eligible, `OUT_OF_LANE` → held for human. Placed in the gate rather than as a branch-protection required context so it adds no new required check (which would block in-flight PRs, per the ADR-0024 deadlock). Unit-tested against scope/size/denylist/rail-enforcer/origin/modification cases. The denylist is the calibration surface — conservative (over-blocking routes to a human); the structural limits bound the blast radius if it is imperfect.
- **`implementer.md` line 82** — carve: the implementer MAY edit exactly one `plugins/ai-team/agents/*.md` when the work closes an `agent-quality` issue; the guard enforces the lane.
- **ADR-0031 dispatch** — rewire the agent-quality fix from the generic implementer refuse-path into this lane.
- **Auto-merge gate** ([ADR-0021](0021-autonomous-merge.md)/[ADR-0023](0023-origin-based-autonomy-boundary.md)) — treat a guard-passing additive-self-change PR as auto-mergeable machine-origin.
- **Self-change log** — a pinned `agent-self-change-log` issue appended on each auto-merge; rolled into the weekly digest.
- **Loop diagram** — the `CG` self-change gate gains a third branch: additive (guard-gated) → auto-merge; compositional → architect → human.

## Links

- Enables [ADR-0031](0031-promoter-disambiguates-or-closes-vague-findings.md) — the agent-quality fix needs a dispatch path that doesn't bottleneck on a human.
- Amends [ADR-0019](0019-team-self-modification.md) and [ADR-0023](0023-origin-based-autonomy-boundary.md) — a deterministically-gated exception to human-ratified self-change.
- Relies on [ADR-0024](0024-required-test-checks-pass-on-no-app-repos.md) — auto-merging the self-edit needs the platform repo's now-cured required checks.
