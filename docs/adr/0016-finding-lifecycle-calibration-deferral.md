# ADR-0016: Finding lifecycle - calibration, deferral, and Sentry-driven cleanup

- **Status:** Accepted — Rule 2 deferral caps amended by [ADR-0020](0020-fleet-orchestration.md); terminal merge stage added by [ADR-0021](0021-autonomous-merge.md); oscillation/loop-detection rule added by [ADR-0023](0023-origin-based-autonomy-boundary.md)
- **Date:** 2026-05-16
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, agents, signal-to-noise

> **Amended by [ADR-0030](0030-all-dispatch-through-promoter.md):** dispatch routing changed — all implementer dispatch now goes through the promoter (no direct bypass). See the *Impacted ADRs* table in ADR-0030 for the specific change to this ADR.

> **Amended by [ADR-0031](0031-promoter-disambiguates-or-closes-vague-findings.md):** a vague *agent-discovered* finding is no longer parked ("comment and leave"); the promoter either enriches it into a normal ticket or auto-closes it and dispatches a fix to the source agent's contract. The vague branch is a disposed lifecycle outcome, not a held one.

## Context and Problem Statement

The platform's AI reviewer agents (`code-reviewer`, `security-reviewer`, `triage-bot`, `doc-keeper`) produce findings on every PR, log scan, and merge. Two failure modes have surfaced in practice across the first month of platform use:

1. **Over-escalation.** Agents flag bounded or theoretical issues as Critical/High severity. On PR #82 of game-night-pwa the code-reviewer flagged the local-Windows-path marketplace source as a "Critical CI-blocker" (it was a documented and accepted trade-off). On PR #90 the same agent flagged a `file:` dep as a Critical CI-breaker (the same PR's `npm ci` actually succeeded — the agent reasoned from inspection without checking the run output it could have grep'd). Both were confidently-wrong Criticals.

2. **PR-of-the-week churn.** Every low/nit finding has been triggering its own implementer cycle. Each nit becomes its own issue, its own PR, its own review pass — multiplying CI cost (real Anthropic API spend) and human attention without proportional value.

Both behaviors stem from the same underlying incentive: agents that report findings have an implicit reputation incentive to find SOMETHING. A reviewer that says "nothing actionable" feels like it hasn't earned its API spend. The result is health-inspector pathology - finding something to justify the visit.

## Decision Drivers

- Preserve the signal-to-noise ratio of Critical/High verdicts. Today, a "VERDICT: BLOCK" on a migration PR is empirically often wrong, so engineers (and future Claude sessions) have learned to admin-merge past it. That's a trust collapse.
- Reduce per-fix-of-a-nit overhead: the implementer's full review pipeline is meaningful infrastructure cost.
- Keep real production signals at full priority: Sentry-reported bugs are real user impact and should NOT be deferred.
- Avoid permanent backlog rot: deferred issues that no feature work ever touches need a finalization path.

## Considered Options

- **Option A:** Status quo - tighten prompts iteratively, hope severity calibration improves.
- **Option B:** Explicit calibration philosophy + deferral policy + Sentry-priority rule.
- **Option C:** Move all reviewer agents from `sonnet` to `haiku` to reduce per-find cost without changing severity behavior.
- **Option D:** Disable the issue-filing side effect of reviewer agents; keep PR-comment-only output.

## Decision Outcome

**Option B.** Three rules baked into agent definitions:

### Rule 1: Calibration philosophy

Every reviewer-style agent (`code-reviewer`, `security-reviewer`, `triage-bot`, `doc-keeper`) gets explicit language reminding it that:

- A clean review with zero blocking findings is a valid outcome.
- Manufacturing severity to justify the review erodes trust in future Critical verdicts.
- When in doubt, downgrade.
- Predictions of specific failure modes ("CI will break") must be checked against actual run output before being filed as Critical.

This is meta-guidance shaped by observed behavior, not a process change. The agents do what they always did, just with the calibration mindset made explicit. Severity-label semantics remain the existing scheme (Critical / High / Medium / Low / Nit).

### Rule 2: Deferral policy

Low and nit-severity findings get filed as GitHub issues labeled `deferred-until-adjacent`. The implementer does NOT pick these up in isolation. Instead, when the implementer is already working on a feature, Sentry bug, or higher-severity fix in some directory, it scans for `deferred-until-adjacent` issues citing files in the same directory. If any are bounded and unambiguous, it bundles up to 2 of them into the in-flight PR's "While here" section.

Medium findings default to non-deferred (they imply real risk), but security-reviewer's defense-in-depth Mediums and doc-keeper's prose-quality Mediums can use the deferral label sparingly.

### Rule 3: Sentry-bug auto-pickup

Issues with the `source:sentry` label (Sentry's GitHub integration auto-applies this when its alert rules create an issue) OR `severity:critical` get implementer attention immediately, regardless of whether `ready-for-implementer` is set. Production errors that fired in real user sessions are pre-validated work - they don't need a triage gate.

Sentry-bug pickup is ALSO a trigger for the deferral-bundling scan. Fixing a real bug usually involves loading a file into context that has nits filed against it; bundle them.

### Rule 4: Oscillation detection (added by [ADR-0023](0023-origin-based-autonomy-boundary.md), 2026-05-25)

A finding that has been fixed and then reverted before is not a finding to re-fix — it is a signal the loop is churning. Before acting on a finding, the implementer and triage-bot check git and issue history for a prior fix-and-revert cycle of the same finding; on a detected cycle they halt and escalate to a human rather than re-fixing. ADR-0023 places loop-churn defense here, in agent logic, deliberately instead of behind a human gate. Operational detail lands in the agent definitions per ADR-0023's implementation set.

### Backlog finalization

- **Quarterly sweep:** a future slash command `/ai-team:sweep-deferred` (not part of this ADR's implementation) runs through `deferred-until-adjacent` issues older than 90 days. Closes obviously stale ones; re-triages real ones.
- **Hard age limit:** any deferred issue open >180 days is auto-flagged for re-triage.
- **Quarterly cap (informational):** if `deferred-until-adjacent` issues exceed ~30 per repo, run a deliberate cleanup sprint.

## Consequences

### Positive

- Critical/High verdicts regain meaning. When a reviewer says Critical, it actually is.
- Reduced CI / Anthropic-API spend per nit (no dedicated PR + review pipeline per low-severity finding).
- Implementer PRs are wider but more contextually coherent (bundled fixes are adjacent to the feature work, not random).
- Sentry bugs get faster attention without requiring manual triage gating.

### Negative

- **Wider PRs for the implementer.** Bundled fixes mean a feature PR's diff touches more lines than strictly required by the issue. Mitigated by: 2-bundle cap; explicit "While here" PR-body section; reviewers can still nit on bundled changes.
- **Stable code may carry nits forever.** Files that no feature ever touches accumulate `deferred-until-adjacent` issues with no natural exit. Mitigated by the quarterly sweep + 180-day re-triage.
- **Risk of severity miscalibration becoming more consequential.** A "low" that should have been "medium" sits in backlog longer. Pairs with Rule 1 (calibration philosophy) - both rules need each other.
- **Subjective bundling decisions.** "Same area" and "bounded" are fuzzy. The implementer is told to err on the side of skipping when in doubt; the 2-cap prevents this from spiraling.

### Neutral

- The platform's `claude-implementer.yml` workflow needs updating to trigger on `source:sentry` and `severity:critical` labels in addition to `ready-for-implementer`. Not part of this ADR; tracked as a follow-up workflow change.
- The release-captain's release notes get a new optional "Cleaned up while here" section. Cosmetic but visibility-positive.

## Implementation notes

- **Agent files modified:** `code-reviewer.md`, `security-reviewer.md`, `triage-bot.md`, `doc-keeper.md`, `implementer.md`, `release-captain.md` — see commit log for diffs.
- **Standard 10 (AI workflows)** gets a new section documenting the calibration + deferral + Sentry policy. The platform plugin ships a copy of Standard 10 as a skill, so both files are updated.
- **Playbook entry** added to `docs/runbooks/platform-port-quirks.md` warning consumers that reviewer behavior will look different after this lands (fewer Criticals, more low-severity issues filed with the deferral label).
- **Follow-up not in this ADR:**
  - `claude-implementer.yml` trigger update (Sentry / severity:critical labels) — needs project-side workflow update on each consumer
  - `/ai-team:sweep-deferred` slash command — quarterly housekeeping tool
  - Memory file capturing the policy for future Claude sessions

## Pros and Cons of the Options

### Option A: Status quo, iterate on prompts

- ✅ Pro: minimal change overhead; can adjust prompts per-PR.
- ❌ Con: doesn't address the root cause (incentive to find something); calibration shifts case-by-case rather than systematically.
- ❌ Con: PR-of-the-week churn continues.

### Option B: Calibration + deferral + Sentry-priority (CHOSEN)

- ✅ Pro: addresses both failure modes (over-escalation + churn) with one coherent policy.
- ✅ Pro: Sentry priority preserves what matters at full speed.
- ✅ Pro: empirically grounded in observed behavior across multiple PRs in May 2026.
- ❌ Con: wider PRs; some subjective bundling decisions; needs a sweep mechanism for stable-code backlog.

### Option C: Downgrade reviewer models to haiku

- ✅ Pro: real cost reduction per find.
- ❌ Con: doesn't fix the calibration problem; cheaper finds + bad calibration = more noise, not less.
- ❌ Con: degrades the platform's quality reputation if haiku produces lower-quality reviews.

### Option D: Disable issue-filing side effects

- ✅ Pro: stops the backlog churn directly.
- ❌ Con: loses the value of persistent backlog for finding tracking.
- ❌ Con: doesn't address the over-escalation pattern at all (Critical findings would still be miscalibrated, just lost).

## Links

- [ADR-0005 — code quality enforcement gap](0005-quality-gates.md)
- [ADR-0011 — AI workflows](0011-ai-workflows.md)
- [ADR-0026 — agentic implementer](0026-agentic-implementer.md) (the autonomous-team / implementer architecture; formerly an informal "ADR-0013" reference that collided with the Grafana ADR — resolved 2026-05-31)
- [Standard 10 — AI workflows](../standards/10-ai-workflows.md)
- Empirical examples that drove this decision:
  - game-night-pwa PR #82 (migration PR) — code-reviewer's BLOCK on local-Windows-path was a category error
  - game-night-pwa PR #90 (admin-invite-e2e) — code-reviewer's Critical on `file:` dep was contradicted by the same PR's `npm ci` success
  - Same PR's security-reviewer surfaced unrelated `lambda/feedback.js` PII concerns out of the PR's actual diff scope
