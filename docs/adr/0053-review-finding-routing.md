# ADR-0053: Review findings — resolve on the PR, don't bloom into issues

- **Status:** Ratified
- **Date:** 2026-06-25
- **Implementation:** Pending — implemented via the **review-lead** consolidation agent (#587, amendment below), not per-reviewer. Review-lead def + `claude-pr-review.yml` rewiring + standards doc. Ratified by Jason 2026-06-25; review-lead amendment ratified by Jason 2026-06-26.
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, code-review, orchestration, backlog-hygiene

> **Format:** MADR 4.x with the platform's three extensions. Bundled-sub-decision ADR — two coupled choices about where a review finding lives.

> **Amended (2026-06-26, #587 — ratified by Jason):** the routing decided here is **implemented by a new `review-lead` consolidation agent**, not per-reviewer (the original Implementation note below). Mined from #251's agent-team "Code Review = lead + peers" pattern. The peer reviewers (`code-reviewer` / `security-reviewer` / `test-writer`) become **advisory reporters** — they no longer file issues, post individual verdicts, or self-dedup. A **`review-lead`** final job reads their findings and is the single owner of: (1) cross-reviewer **dedup**; (2) the **on/off-diff routing** this ADR specifies (on-diff → consolidated verdict + one PR comment + Mode B, not filed; off-diff → filed, auto-dispatched per #579); (3) the **one authoritative VERDICT** (the per-reviewer gates collapse into the lead's); (4) **one consolidated PR comment**. **Trust boundary:** the lead may dedup, consolidate, route, and re-rank, but may **NOT silently drop a peer's Critical/High BLOCK** — it may annotate "lead-assessed: likely false positive," but a Crit/High still blocks until the originating peer's own re-review clears it (preserves the ADR-0049 floor; no single agent can suppress a security finding). **Architecture:** lead-as-final-job reading peer outputs (incremental; the parallel reviewer jobs stay). Full dynamic-workflow review (#588) is explicitly out of scope. This amendment supersedes the per-reviewer wording in *Decision Outcome* sub-decision 1 and *Implementation notes* below.

## Context and Problem Statement

The fleet's open-issue count blooms faster than work is completed, and the cause is structural, not volume: **the reviewers file a tracked GitHub issue for every finding at or above the severity floor (ADR-0049, default `medium`) — *in addition to* the PR-blocking verdict gate that already exists.** So a single PR can spawn N `origin:internal-review` defect issues, each of which the promoter then dispatches as a *separate* implementer run producing a *separate* PR — which can itself draw findings. The `#571 → #572 → #578 → #579` chain (2026-06-24) is the archetype: a flaw in one PR's diff became a standalone issue, got its own PR, which had its own flaw, which became another issue.

In a human team a reviewer requests changes **on the PR**; the author fixes the **same** PR; it merges only when approved. No issue is created for a flaw the PR itself introduced. The platform already has both halves of that loop — a `VERDICT: BLOCK / APPROVE-WITH-COMMENTS / APPROVE` gate (`claude-pr-review.yml`, enforced by a gate step) and the implementer's **Mode B fix-iteration** ("review feedback → push to same PR", `implementer.md`). The bloom comes from running the *file-an-issue-per-finding* behavior on top of that loop, for findings the loop already handles.

The question: **for a review finding, when should it become a tracked issue, and when should it be resolved on the PR that produced it?**

## Decision Drivers

- **The backlog should be real work, not review correspondence.** A finding about a line a PR just wrote is not independent work — it's part of finishing that PR.
- **The quality gate must hold.** Critical/High findings must still block merge.
- **Pre-existing problems must not vanish.** A finding about code the PR *didn't* touch is genuine separate work and must survive the PR's lifecycle.
- **Calibration/deferral philosophy (ADR-0016) stays.** Low/Nit findings should not force work.
- **Throughput & token economy.** Re-dispatching a fresh implementer run per finding (full context reload) is wasteful when Mode B already has the PR's context.
- **Minimal new machinery.** The VERDICT gate and Mode B already exist; prefer re-wiring over building.

## Considered Options

- Sub-decision 1 — **Routing:** where does a finding live?
  - 1A: Status quo — every finding ≥ floor becomes an issue (and crit/high also BLOCK).
  - 1B (chosen): **Diff-scoped routing** — findings about the PR's *own diff* are resolved on the PR (VERDICT + Mode B), never filed as issues; only findings about *pre-existing / adjacent* code become issues.
  - 1C: Never file issues — everything rides the PR; off-diff findings become PR comments only.
- Sub-decision 2 — **On-diff Medium handling:** does a Medium finding on the diff block the merge?
  - 2A (chosen): **Comment, don't block** — crit/high BLOCK (Mode B fixes before merge); Medium is `APPROVE-WITH-COMMENTS` (mergeable), recorded as a PR comment; the reviewer may *escalate* a Medium to High if it must be fixed first.
  - 2B: **Block on Medium too** — fix every Medium on the diff before merge.

## Decision Outcome

We chose the bundle:

- Sub-decision 1 → **1B (diff-scoped routing).** The reviewer classifies each finding as *on-diff* (about a line this PR added/changed) or *off-diff* (about code this PR did not touch). On-diff findings are reflected only in the VERDICT and PR comments and are fixed via Mode B; they are **not** filed as issues. Off-diff findings are filed as issues exactly as today (with the ADR-0016 dedup discipline).
- Sub-decision 2 → **2A (comment, don't block on Medium).** Keep the ADR-0049 floor knob, but it now governs the **BLOCK threshold for on-diff findings** rather than the issue-filing threshold. Default: crit/high block; Medium/Low/Nit are non-blocking comments. A reviewer that judges a Medium must-fix escalates it to High.

The bundle is internally consistent because once on-diff findings stop becoming issues (1B), the only remaining question is *which* on-diff findings hold the merge (2A) — and both lean on machinery the platform already has (VERDICT gate + Mode B). Off-diff issues retain the full ADR-0016 lifecycle; on-diff findings get cross-cycle continuity from Mode B re-review, not from a tracked issue.

## Consequences

### Positive

- The dominant bloom source is removed: a PR's own flaws no longer multiply into issues-and-PRs. The `#571→#572→#578→#579`-style cascade collapses to a few review comments on one PR.
- Crit/high findings stop being **double-tracked** (blocked *and* issued); they are fixed once, on the PR.
- Fewer redundant implementer dispatches (Mode B reuses PR context instead of a cold re-dispatch).
- The backlog regains signal: an open `origin:internal-review` issue now means "a real, separate problem," not "review correspondence."

### Negative

- Correctly classifying on-diff vs off-diff is a judgment the reviewer must make; a misclassification either (a) files an issue that should have been a PR comment (residual bloom) or (b) lets a pre-existing problem ride as a comment and vanish on merge. Mitigation: when unsure, treat as **on-diff** (keeps it on the PR; a genuinely separate problem will resurface on the next PR that touches that code).
- On-diff Medium findings can now merge unaddressed (recorded only as comments). Mitigation: the reviewer escalates must-fix Mediums to High; the floor knob can be set to block Medium per-repo if a project wants a stricter bar.

### Neutral

- Off-diff issue filing, dedup, and the severity ladder are unchanged.
- The VERDICT gate and Mode B are unchanged mechanically; only what *feeds* them changes.

## Pros and Cons of the Options

### Sub-decision 1: Routing

| Option | Pros | Cons |
|---|---|---|
| **1A status quo** | Every finding is tracked; nothing relies on diff classification | The bloom itself; double-tracking; cascade of issues-about-PRs |
| **1B diff-scoped** (chosen) | Kills the bloom at the source; matches human-team norms; reuses existing gate + Mode B | Requires the reviewer to classify on-/off-diff |
| **1C never file** | Simplest reviewer logic | Pre-existing/adjacent problems become comments and are lost on merge — throws away the one legitimate use of finding-issues |

### Sub-decision 2: On-diff Medium handling

| Option | Pros | Cons |
|---|---|---|
| **2A comment, don't block** (chosen) | Preserves throughput; Mediums don't stall merges; reviewer can escalate | A Medium can merge unaddressed unless escalated |
| **2B block on Medium** | Highest quality bar on the diff | More Mode-B iterations; more 3-attempt escalations to the human; slower throughput |

## Implementation notes

- **`claude-pr-review.yml`** (per the #587 amendment): the peer reviewer prompts (`code-reviewer` / `security-reviewer` / `test-writer`) stop filing issues, stop emitting individual verdicts, and stop self-deduping — they emit structured findings only. A new **`review-lead`** job runs after them and does: dedup → on/off-diff classification → consolidated VERDICT (crit/high on-diff → BLOCK) → file only off-diff issues → one consolidated PR comment. The gate step now reads the **lead's** verdict (the per-reviewer gates are removed). New agent def: `plugins/ai-team/agents/review-lead.md`. **The peer jobs themselves MUST remain required status checks** — they are report-only (no gate step) but their reports are the review-lead's input, so a skipped or timed-out review must block the merge. "Report-only" means *not gating*, NOT *optional*; do not drop `review / code-review` or `review / security-review` from branch-protection required checks.
- **`implementer.md`**: note that Mode B is now the primary resolution path for on-diff findings (it already is for BLOCKs); no behavioral change, just doc alignment.
- **Standards doc:** add `docs/standards/NN-review-finding-routing.md` capturing the on-/off-diff rule and the escalate-to-block convention (write with this ADR per the platform's "standard + ADR together" rule).
- **Amends:** [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) (finding lifecycle — on-diff findings no longer enter the issue lifecycle), [ADR-0026](0026-agentic-implementer.md) (reviewer/implementer division — reviewers request-changes on-PR for on-diff), [ADR-0049](0049-review-filing-severity-floor.md) (the floor now governs the on-diff BLOCK threshold, not issue-filing).
- **Resolved at ratification (Jason, 2026-06-25):** off-diff findings **continue to auto-dispatch** — they enter the promoter queue as today, NOT `needs-formulation`. The loop stays aggressive on genuinely separate findings; the bloom fix is purely about not creating issues for on-diff findings, not about throttling the legitimate off-diff ones.

## Links

- Martin Fowler, *Pull Request* / code-review discussion — the request-changes-on-PR norm this ADR restores: `https://martinfowler.com/articles/ship-show-ask.html`
- Google Engineering Practices, *Code Review Developer Guide* (what to block on vs. what to defer): `https://google.github.io/eng-practices/review/`
- The 2026-06-24 cascade (`#571 → #572 → #578 → #579`) — the worked example motivating this ADR.
- [ADR-0016](0016-finding-lifecycle-calibration-deferral.md), [ADR-0026](0026-agentic-implementer.md), [ADR-0049](0049-review-filing-severity-floor.md).
