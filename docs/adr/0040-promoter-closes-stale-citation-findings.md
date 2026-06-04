# ADR-0040: The promoter closes stale-citation findings via a deterministic existence check before evaluation

- **Status:** Accepted — ratified by Jason's merge of PR #197, 2026-06-04 (60d9832); implementation pending (builds through the loop via #195)
- **Date:** 2026-06-04
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, signal-to-noise, autonomy, token-economy

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Extends [ADR-0031](0031-promoter-disambiguates-or-closes-vague-findings.md) (vague-finding disposition) with a sibling disposition for *stale-citation* findings.

## Context and Problem Statement

ADR-0031 gave the promoter disposition authority over **vague** agent findings: disambiguate-or-close, nothing loiters. But a second class of immortal finding has no disposition at all: the **stale citation** — a finding that was well-specified when filed, whose cited file has since been deleted or reverted out of existence.

The promoter *detects* these (it reads the code while judging promotability) but has no authority to act. Observed behavior across two manual cycles on 2026-06-03: splendor #13 / #14 / #23 / #25 / #26 (all citing `src/auth/` and `src/game/` files removed by splendor PR #28's revert) were re-evaluated **both passes**, re-flagged *"human action needed: close as stale"* both times, and left open. Platform #124 (a "broken link" that exists nowhere on HEAD) was hand-closed by the human the same day.

The cost is threefold: stale findings are **immortal** (nothing will ever make a deleted file reappear); they **burn promoter evaluation tokens every cycle** — directly aggravating the context-ceiling risk in the exhaustive evaluation pass; and they pollute the backlog counts the cockpit reports. Like ADR-0031's vague branch before it, "re-evaluate next cycle" is a no-op on an input that cannot change.

## Decision Drivers

- **No infinite sinks** — ADR-0031's principle: every finding either becomes a normal ticket or is closed with a tracked reason. Nothing loiters.
- **Deterministic before LLM.** File existence is a fact, not a judgment. A bash check costs zero tokens and shrinks the LLM's working set — the cheapest lever against the evaluation pass's context growth.
- **Closing must not silently lose a real finding.** A closed issue is linked and reopenable; the close comment must carry provenance (what removed the file).
- **Stale ≠ moved.** A finding whose file exists but whose line numbers drifted is still actionable; only a finding whose subject is *gone* is stale.
- **A stale citation is not an agent-quality defect.** Unlike a vague finding (a contract violation at filing time), a stale citation was correct when filed — the code moved later. No feedback loop against the source agent is warranted.

## Considered Options

1. **Status quo** — promoter flags "close as stale," human closes by hand.
2. **Auto-demote to `severity:nit`** — keep them in the queue but out of the way.
3. **Deterministic auto-close with provenance comment** — pre-LLM bash check; cited paths absent on HEAD → close, comment, link.
4. **LLM judges staleness during evaluation** — fold the call into the promoter's judgment pass.

## Decision Outcome

**Chosen: option 3 — deterministic auto-close, the stale sibling of ADR-0031's vague-close.**

Before the promoter's LLM evaluation of a candidate finding, a **deterministic existence check** (`scripts/stale-citation-check.sh`) runs:

- **Extract cited paths** from the finding — the body's `**File:** <path>:<line>` field first, falling back to the title convention `[agent] <path>:<line> — <description>`. Multiple cited paths are all collected.
- **All cited paths absent on default-branch HEAD → stale.** The promoter closes the finding with a comment stating the disposition, naming the removing commit/PR when findable (`git log --diff-filter=D -- <path>`), and noting the issue is reopenable if the work returns. Closed-and-linked, not lost.
- **Any cited path present → not stale.** Line drift does not matter; the finding proceeds to normal evaluation untouched.
- **No paths extractable → not this ADR's concern.** That is a vague finding; ADR-0031's disambiguate-or-close branch owns it.

**No agent-quality feedback** is filed (contrast ADR-0031): the source agent's output was correct at filing time.

**Why not the alternatives:** option 1 leaves an immortal class and a standing human chore — the exact pattern ADR-0031 was written to kill. Option 2 hides the corpse instead of burying it: the nit still occupies the queue, still gets swept into Mode-C batches, and still burns evaluation. Option 4 spends LLM tokens to learn a fact `test -e` establishes for free, and makes the disposition non-deterministic — the one property this check must not lose.

**Acceptance fixture:** splendor #13 / #14 / #23 / #25 / #26 remain open deliberately. The first post-ship promoter pass must close all five autonomously, each with a provenance comment naming splendor PR #28. The fixture closing is the ship-verification.

## Consequences

### Positive

- The stale class drains itself; the splendor five stop being re-litigated every cycle.
- Every skipped stale finding is one less item in the LLM evaluation set — a direct, compounding reduction in the pass's token and context load.
- Cockpit backlog counts stop overstating real work.

### Negative

- A finding citing a file that was *renamed* (not deleted) closes as stale even though the defect may persist at the new path. Accepted: the close comment carries provenance, the issue is reopenable, and the reviewer agents will re-find a persisting defect at its new location on a future pass. A `git log --follow` rename hint in the close comment is a permitted future tightening, not required now.
- A finding citing only a directory (no file) needs the check to test the directory; the script must handle both.

### Neutral

- The check runs per-candidate inside the promoter pass — no new workflow, no new dispatch path, no throttle interaction (ADR-0030 untouched).
- Disposition authority expands by exactly one deterministic branch; the promoter's LLM judgment surface is unchanged.

## Pros and Cons of the Options

### Option 1 — status quo (human closes by hand)

- ✅ Zero new machinery.
- ❌ Stale citations are immortal: nothing makes a deleted file reappear, so nothing triggers resolution.
- ❌ Burns promoter evaluation tokens every cycle on inputs that cannot change.
- ❌ Keeps a standing human chore that is pure mechanical friction — the exact pattern ADR-0031 was written to kill.

### Option 2 — auto-demote to `severity:nit`

- ✅ Keeps the finding in the queue in case the file reappears.
- ❌ Hides the corpse instead of burying it: the nit still occupies the queue, still gets swept into Mode-C batches, and still burns evaluation tokens.

### Option 3 — deterministic auto-close with provenance comment (chosen)

- ✅ Zero LLM cost: file existence is a `test -e` check, not a judgment.
- ✅ Closed issues are linked and reopenable — provenance preserved, nothing silently lost.
- ✅ Directly shrinks the LLM evaluation set; every skipped stale finding is a compounding token and context saving.
- ❌ A renamed (not deleted) file closes a still-actionable finding. Accepted: the close comment names the removing commit/PR; the finding is reopenable; reviewer agents re-find persisting defects at new paths on a future pass.

### Option 4 — LLM judges staleness during evaluation

- ✅ Unified evaluation path; no separate script.
- ❌ Spends LLM tokens to determine a fact `test -e` establishes for free.
- ❌ Makes the disposition non-deterministic — the one property this check must not lose.

## Implementation notes

- `scripts/stale-citation-check.sh` — new; input: issue title + body, repo checkout at HEAD; output: `STALE <path>...` / `PRESENT` / `NO_PATHS`. Pure bash, no LLM.
- `plugins/ai-team/agents/triage-bot.md` — Pass-2 eligibility: run the check before LLM evaluation of each candidate; on `STALE`, close with the provenance comment and skip evaluation.
- Amended-by banner on [ADR-0031](0031-promoter-disambiguates-or-closes-vague-findings.md).
- `docs/diagrams/autonomous-loop-flow.md` — add the stale-close branch beside `DISAMB`/`CLOSEV` in box ②.
- This is a compositional self-change (promoter contract + a gate-adjacent script): the implementation PR carries `compositional-self-change` and holds for human merge per ADR-0023/0039.

## Links

- [ADR-0031](0031-promoter-disambiguates-or-closes-vague-findings.md) — the vague-finding disposition this extends; same nothing-loiters philosophy.
- [ADR-0030](0030-all-dispatch-through-promoter.md) — dispatch routing; untouched by this ADR.
- #195 — the formulation issue; #124 and splendor #13/#14/#23/#25/#26 — the motivating exhibits.
