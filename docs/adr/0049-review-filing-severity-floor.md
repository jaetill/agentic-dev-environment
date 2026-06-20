# ADR-0049: Per-repo review issue-filing severity floor

- **Status:** Proposed
- **Date:** 2026-06-20
- **Implementation:** Pending behind human ratification of this PR + setting `REVIEW_FILE_MIN_SEVERITY=high` on the platform repo
- **Deciders:** Jason
- **Tags:** ci-cd, review, autonomous-loop, backlog

> **Lifecycle:** `Proposed` → `Accepted` → `Ratified` → `Implemented`. The Implementation line is updated when this lands.

## Context and Problem Statement

The platform repo's open-issue count is dominated by its own review output: ~90% of open issues are `origin:internal-review` defects, and ~93% of those are `severity:medium`. The reviewers (code-reviewer, security-reviewer, test-writer) file a tracked GitHub issue for every Critical, High, **or Medium** finding. On the platform repo, almost every finding is about the loop's own gate machinery — so the fix PRs touch governance files, the ADR-0047 capability-delta firewall correctly holds them for human review, and they cannot auto-drain. The result: medium-severity self-findings accumulate faster than the human merge gate can clear them, and the count never falls.

How do we stop the platform's self-review backlog from refilling while it is drained, without weakening review coverage on the application repos (which auto-drain fine and benefit from medium-severity findings)?

## Decision Drivers

- The reusable `claude-pr-review.yml` is fleet-wide; any change must not silently alter app-repo behavior.
- Critical/High findings (real security/correctness) must always be filed, everywhere.
- The lever must be reversible and per-repo tunable, matching the existing knob pattern (`FLEET_MAX_DISPATCH_PER_RUN`, `AUTONOMOUS_MERGE_CAP`).
- Medium findings should not be *lost* — they should still surface in the PR review comment, just not become tracked issues on repos where they only pile up behind the human gate.

## Considered Options

- Option A: Per-repo severity floor via a `REVIEW_FILE_MIN_SEVERITY` repo variable (default `medium`; platform set to `high`).
- Option B: Hardcode a platform-repo special-case in the reviewer prompts.
- Option C: Disable internal-review issue filing on the platform repo entirely.
- Option D: Do nothing — drain manually and accept the refill.

## Decision Outcome

Chosen option: **Option A**, because it stops the platform refill while leaving every other repo untouched (the default floor `medium` preserves current behavior), keeps Critical/High coverage intact everywhere, and is a reversible per-repo knob consistent with the platform's existing variable-driven controls. Medium findings still appear in the PR review comment; they simply stop becoming tracked issues on repos whose floor is raised.

## Consequences

### Positive

- The platform's medium-severity self-review backlog stops refilling; the existing queue can be drained to a stable floor.
- Critical/High findings continue to be filed and dispatched on every repo.
- A general, reusable per-repo tuning knob, defaulting to today's behavior.

### Negative

- Medium findings on the platform repo are no longer individually tracked as issues — they live only in the PR review comment. A genuinely worth-tracking medium issue on the platform now depends on a human noticing it in-review.
- The floor is honored by an LLM reviewer prompt, not a deterministic gate, so it is a strong instruction rather than a hard guarantee.

### Neutral

- App repos are unchanged (default floor `medium`).
- The VERDICT/BLOCK gate is unaffected — it still keys on Critical/High and is independent of the filing floor.

## Pros and Cons of the Options

### Option A: Per-repo severity floor via repo variable

- ✅ Pro: Default preserves app-repo behavior exactly; only the platform changes.
- ✅ Pro: Reversible and per-repo tunable; same pattern as existing fleet knobs.
- ✅ Pro: Medium findings still surface in the PR comment — not lost.
- ❌ Con: Enforced via prompt instruction, not a deterministic gate.

### Option B: Hardcode platform special-case in prompts

- ✅ Pro: No variable plumbing.
- ❌ Con: Bakes a repo name into the reusable; not tunable for other repos without another edit.
- ❌ Con: Every future floor change is a gate-machinery PR.

### Option C: Disable internal-review filing on the platform entirely

- ✅ Pro: Instant, zero refill.
- ❌ Con: Drops Critical/High coverage on the platform repo — unacceptable for the repo that defines the loop's safety rails.

### Option D: Do nothing

- ✅ Pro: No change.
- ❌ Con: The backlog refills as fast as it drains; the count never falls — the problem this ADR exists to solve.

## Implementation notes

- Affected workflow: `.github/workflows/claude-pr-review.yml` (reusable) — the three reviewer filing instructions (code-reviewer, test-writer, security-reviewer) now reference `${{ vars.REVIEW_FILE_MIN_SEVERITY || 'medium' }}`.
- Repo variable: `REVIEW_FILE_MIN_SEVERITY` — unset (= `medium`) fleet-wide; set to `high` on `jaetill/agentic-dev-environment`.
- No standards doc required; this is a tuning knob, not a new practice.

## Links

- ADR-0047 — capability-delta firewall (why platform self-fix PRs hold for human review, which is what makes the medium backlog non-draining).
- ADR-0026 — review findings become tracked issues for the implementer.
- ADR-0030 — dispatch throttle (the `FLEET_MAX_DISPATCH_PER_RUN` knob pattern this mirrors).
