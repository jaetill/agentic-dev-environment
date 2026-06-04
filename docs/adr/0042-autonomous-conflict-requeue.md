# ADR-0042: Conflict recovery is autonomous re-queue — bounded at 7, then escalate

- **Status:** Proposed — direction ratified by Jason in formulation of #147 (2026-06-04, option A with cap raised 3→7); merge of this ADR's PR is the formal ratification
- **Date:** 2026-06-04
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, autonomy, resilience

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Extends [ADR-0026](0026-agentic-implementer.md)'s optimistic-concurrency model with autonomous recovery; touches the implementer contract (Mode A pre-flight) and the auto-merge gate's conflict branch.

## Context and Problem Statement

ADR-0026 deliberately forbids the implementer from resolving rebase conflicts: on a pre-flight `git rebase` conflict it aborts, discards the branch, and rebuilds fresh on a later cycle — an LLM splicing diverged hunks unsupervised is a silent-error risk, while a wasted run is cheap. That part is sound and unchanged.

The gap is the *recovery*. Today the aborting implementer comments asking a human to remove-and-re-add `ready-for-implementer`. The issue keeps the label, so the promoter skips it (already-ready issues are never re-promoted) and nothing re-dispatches it: it sits *ready, no PR* until a human pokes it. The same human-gate exists at the **merge end**: a qualifying PR whose `gh pr merge` fails on conflicts lands in `HFAIL — left for human`.

Live exhibits (2026-06-03): game-night-pwa #132 and meal-planner #64 conflicted after sibling merges and were hand-recovered (close PR, strip label, let the promoter rebuild) — the exact procedure this ADR automates.

## Decision Drivers

- The loop exists to absorb mechanical friction; "re-poke the label" is mechanical friction.
- ADR-0026's no-LLM-conflict-resolution boundary must survive intact — recovery means *rebuild*, never *merge hunks*.
- A genuinely persistent conflict must still reach the human — bounded retries, not a spin loop.
- High current merge churn means the same hot files can legitimately conflict on several consecutive attempts; the cap must not hair-trigger escalation (Jason: 3 → **7**).
- Reuse the existing promotion path; no new watcher machinery.

## Considered Options

- **A — self-re-queue with a bounded retry counter** (chosen): strip the dispatch label, count attempts, escalate at the cap.
- **B — event-driven precise retry:** identify the conflicting PR, watch for its merge, re-dispatch immediately.
- **C — status quo** plus an honest diagram label.

## Decision Outcome

**Chosen: A, cap = 7.** One concept applied at both conflict points: *conflict recovery is autonomous re-queue, bounded, then escalate.*

**Pre-flight conflict (implementer, Mode A step 11):** abort the rebase (unchanged), then instead of commenting-for-a-human: remove `ready-for-implementer`, increment a `conflict-retry:<n>` label (1-based), comment one line ("pre-flight conflict; re-queued, attempt n of 7"). The issue re-enters the promoter's pool and re-dispatches through the **normal** promotion path on a later cycle — by which time the conflicting sibling has typically merged.

**Merge-time conflict (auto-merge gate):** when a qualifying PR's `gh pr merge` fails on merge conflicts specifically, the gate closes the PR with a one-line comment, deletes the branch, removes `ready-for-implementer` from the linked issue, and increments the same `conflict-retry:<n>` — the rebuild then flows exactly like the pre-flight case. Non-conflict merge failures keep the existing `HFAIL — left for human` branch.

**Counter semantics:** `conflict-retry` increments only on a *conflicted attempt* (a dispatch that ended in abort, or a merge that failed on conflicts). Cycles spent waiting in the queue do not count. The promoter treats `conflict-retry:7` as ineligible-for-promotion and instead applies `human-todo` with an escalation comment — a persistent conflict is a structural signal (two work streams fighting over the same code), which is a human call.

**What this does not change:** no LLM conflict resolution, ever (ADR-0026); the fresh-rebuild discipline; the dispatch throttle (re-queued issues compete for slots like everything else — no cap exemption).

## Consequences

### Positive

- The two conflict sinks (`ready, no PR` stranding; `HFAIL` on conflicts) drain themselves; the 2026-06-03 hand-recovery procedure becomes loop behavior.
- Escalation at 7 converts "spinning" into a *structural* signal the human should actually see, instead of noise they must routinely absorb.

### Negative

- Up to 7 wasted builds on a pathological conflict before a human sees it. Accepted: builds are cheap (ADR-0026), and each retry is spaced by at least one promotion cycle.
- Label arithmetic (`conflict-retry:n` → `n+1`) is one more mutation the implementer and gate must do correctly; a missed increment delays escalation but cannot cause a spin (the strip-and-requeue still happens).

### Neutral

- `CONFWAIT` in the loop diagram becomes truthful ("re-queued, bounded retry") instead of aspirational ("retry next dispatch").
- Option B's lower retry latency was real but bought with blocker-identification + watcher machinery; next-cycle latency is acceptable at current windows.

## Implementation notes

- `plugins/ai-team/agents/implementer.md` — Mode A step 11 (and the Mode B analog): replace comment-for-human with strip + `conflict-retry` increment + one-line comment.
- `.github/workflows/triage-scan.yml` auto-merge job — split the merge-failure branch: conflict → close/strip/increment; other failures → `HFAIL` unchanged.
- `plugins/ai-team/agents/triage-bot.md` — eligibility: `conflict-retry:7` → apply `human-todo`, comment, skip.
- Labels `conflict-retry:1..7` created on first use; `docs/diagrams/autonomous-loop-flow.md` `CONF`/`CONFWAIT` + merge-gate `MFAIL` branch updated.
- Compositional self-change: the implementation PR carries `compositional-self-change` and holds for human merge.

## Links

- [ADR-0026](0026-agentic-implementer.md) — optimistic concurrency; the no-conflict-resolution boundary preserved here.
- [ADR-0030](0030-all-dispatch-through-promoter.md) — the promotion path reused for re-dispatch.
- #147 (formulation) — includes the 2026-06-03 hand-recovery exhibits (game-night #132, meal-planner #64).
