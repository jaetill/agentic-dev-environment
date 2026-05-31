# ADR-0031: The promoter disambiguates-or-closes vague agent findings and feeds quality failures back to the source agent

- **Status:** Accepted
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, signal-to-noise, autonomy

## Context and Problem Statement

The promoter's eligibility pass ([`triage-bot.md`](../../plugins/ai-team/agents/triage-bot.md) §Process) had a terminal branch for a vague candidate: *"do NOT promote — comment exactly what is missing and leave it,"* drawn in the loop diagram as a node labelled "re-evaluated next cycle." Two flaws hide in that branch.

**It is reachable only from the loop's own agents.** The promoter evaluates *agent-discovered* work exclusively — a human-authored issue is never promoted here (filing it *was* its triage; the implementer picks it up on `issues: opened`). So the vague branch fires only when one of the loop's own agents (code-review, ci-health, dep-watch, …) files an underspecified finding. That is a violation of the agent's output contract — findings are supposed to carry a file, a line, and a bounded change — not a human-input problem.

**The branch is a sink, not a wait.** A comment requesting detail does not edit the issue body. So "re-evaluate next cycle" is a no-op on unchanged text: the verdict is identical every pass. The only thing that can move the issue is an external actor editing it, and for an agent-authored issue no actor is watching. Worse, unlike the adjacent oscillation guard — which applies an `oscillation-detected` label and skips already-labelled issues — the vague branch applies no label and has no dedup. So the promoter re-comments on the same issue every in-window cycle: an immortal issue *plus* comment spam. This is a direct contributor to the unbounded backlog growth the loop exists to drain.

## Decision Drivers

- The vague branch must not be an infinite sink or a spam source.
- "Re-evaluate next cycle" must only happen when the input actually changed.
- A vague agent finding is a labor-quality defect — the loop should fix the *cause* (the agent), not endlessly re-observe the symptom.
- Auto-closing must not silently lose a real-but-poorly-worded finding.
- It must respect the fleet throttle ([ADR-0030](0030-all-dispatch-through-promoter.md)) — no new unbounded dispatch path.

## Considered Options

1. **Label-and-park** — comment once, apply `needs-detail`, skip already-labelled issues (mirror the oscillation guard).
2. **Promoter enriches** — disambiguate the finding from the code it references, rewrite the body, then treat it as a normal candidate.
3. **Close-at-source + feedback** — treat a vague agent finding as a contract violation: auto-close it and raise a tracked improvement against the agent that produced it.

## Decision Outcome

**Chosen: options 2 and 3 in combination — the vague branch stops being a terminal state.** On a candidate that passes every eligibility gate *except* well-specified:

- **Disambiguable** (the finding references real code the promoter can read to recover the missing repro / acceptance criteria): the promoter rewrites the issue body with the missing specifics, comments that it enriched the finding, and the issue re-enters the *same* pass as an ordinary well-specified candidate. It promotes + dispatches if it ranks within `FLEET_MAX_DISPATCH`; otherwise it stays in the backlog and is re-evaluated next cycle as a normal ticket. No special state.

- **Not disambiguable:** the promoter **auto-closes** the vague issue with an explanatory comment, then **files (or appends to) an agent-quality issue** in the platform repo against the source agent. That issue is **deduped to one open issue per agent** — each new instance is appended as a comment linking the closed example and naming the missing field, so it cannot itself become spam. It is well-specified by construction (it names the agent, the missing field, and the spec file to tighten), is **exempt from the survived-one-cycle gate**, and is **promoted + dispatched in the same run** (still counting against the throttle) so the implementer drafts the contract tightening as a human-reviewed PR.

Rationale for dispatching the fix immediately rather than parking it (Jason): it won't pile up if it's worked the moment it's raised; it is a *bug-fix in the existing process*, not a change to the process, so it does not need the human-ratification ceremony; and a downstream agent struggling with an upstream agent's output should not have to wait on a human to tell the upstream agent to do better.

Every vague finding now either becomes a normal ticket or is closed with a tracked, dispatched improvement. Nothing loiters.

## Consequences

### Positive

- The sink and the comment spam are eliminated; the backlog can no longer accrue immortal vague issues.
- The loop self-corrects its own labor: repeated vague findings from one agent converge to a single tracked, dispatched fix to that agent's contract.
- "Re-evaluate next cycle" now applies only to inputs that genuinely changed (enriched bodies), which is logically sound.

### Negative

- **Disambiguation cost** — the promoter spends a code-read on each vague candidate. Bounded by the already-gated candidate set, and vague agent findings should be rare once their source is fixed.
- **False-negative close** — a conservative promoter may close a real finding it could have salvaged. Mitigated: closed ≠ deleted, the agent-quality issue links every closed example, and a human reviewing that issue can reopen a genuine one. That link is precisely what makes auto-close acceptable.
- The loop now edits its own agents' contracts. Acceptable because platform-repo PRs are human-reviewed — no agent spec changes without eyes on it.

### Neutral

- Same-run dispatch of the agent-quality issue is a deliberate exception to the survived-one-cycle gate. It is justified because the issue is promoter-authored and well-specified by construction — it cannot be the half-formed same-scan artifact the gate exists to catch.

## Pros and Cons of the Options

### Label-and-park (rejected as the sole fix)

Good: kills the spam with one label; mirrors the oscillation guard's proven pattern. Bad: still parks agent-authored vague issues forever — nobody is watching to add the detail — so it treats the symptom and leaves the source agent producing more.

### Promoter enriches (chosen, for the disambiguable case)

Good: turns a dead end into a normal ticket; uses the promoter's Tier-2 (Sonnet) judgement against real code; delivers "treat it like any other issue." Bad: hallucination risk if the promoter over-reaches — bounded by the standing "when in doubt, do not promote" asymmetry ([ADR-0020](0020-fleet-orchestration.md)).

### Close-at-source + feedback (chosen, for the non-disambiguable case)

Good: keeps the queue clean *and* fixes the cause; a blameless-retro applied to the AI team. Bad: false-negative close risk — mitigated by the linked, dispatched agent-quality issue, which preserves the finding and routes the improvement.

## Implementation notes

- [`triage-bot.md`](../../plugins/ai-team/agents/triage-bot.md) §Process, well-specified step: replace "comment and leave" with the disambiguate → enrich / else → close + feedback branches, plus the agent-quality dedup and same-run-dispatch detail.
- Agent identity is read from the source label / bot author; the agent-quality issue points at `plugins/ai-team/agents/<agent>.md`.
- The agent-quality dispatch counts against `FLEET_MAX_DISPATCH` like any other promotion ([ADR-0030](0030-all-dispatch-through-promoter.md)); the survived-one-cycle exemption applies only to it.
- Loop diagram: the `NOTPROMO` "re-evaluated next cycle" node is replaced by the disambiguation branch.

## Links

- Amends [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — a vague finding is now a *disposed* lifecycle outcome (enriched or closed-with-feedback), not a parked one.
- Builds on [ADR-0029](0029-promoter-owns-nit-adjacency.md) and [ADR-0020](0020-fleet-orchestration.md) — the same "the promoter owns the judgement" principle.
- Respects [ADR-0030](0030-all-dispatch-through-promoter.md) — the agent-quality fix dispatches through the throttle, not around it.
