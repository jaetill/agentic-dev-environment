# ADR-0024: Required test checks pass (not skip) on no-app repos

- **Status:** Proposed
- **Date:** 2026-05-30
- **Deciders:** Jason Tilley
- **Tags:** ci-cd, testing, ai-workflows, governance

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. This ADR *repairs* an unstated assumption in [ADR-0021](0021-autonomous-merge.md) — it does not reopen the merge-gate model.

## Context and Problem Statement

The reusable review workflow (`claude-pr-review.yml`, per [ADR-0018](0018-reusable-review-workflow.md)) gates its npm-based test jobs — `functional-test` and `e2e-test` — behind `detect-node`: a repo with no root `package.json` skips the whole job. The intent was that a meta/framework repo with no Node app surface (today, only the platform repo `agentic-dev-environment` itself) should not be asked to run an app test suite it doesn't have.

`functional-test` and `e2e-test` are also **required status checks** on `agentic-dev-environment/main`. The job comment asserted that a skipped required check "is treated as satisfied" by GitHub. **That is false.** GitHub's status rollup reports the PR green (it ignores skipped contexts), but branch protection evaluates each required context individually and a skipped required check is *not* a passing one. The result: every implementer PR against the platform repo sits `MERGEABLE`/`BLOCKED` forever, the auto-merger (ADR-0021) fails it with "base branch policy prohibits the merge," the fixed issue never closes, and the platform repo's backlog grows unbounded (52 of ~200+ fleet issues as of 2026-05-30) while looking green on every dashboard.

How should the required test contexts behave on a repo that has no app suite, so the merge gate stays honest *and* mergeable for both apps and frameworks?

## Decision Drivers

- **ADR-0021 already assumes pass, not skip.** Its condition 2 reads "`functional-test` and the rest pass." This ADR makes reality match that text.
- **One required-context contract across the fleet.** App repos and framework repos should present the same required check names, so branch protection is uniform and the template propagates cleanly (per `CLAUDE.md` template-propagation principle).
- **The gate must stay honest.** The fix must not let a real app repo bypass its suite. "Vacuous pass" applies only where there is genuinely nothing to test.
- **Mechanical, not judged.** The app/no-app determination must be decidable from repo state (`detect-node`), not a human call at merge time.

## Considered Options

- **Option A:** Job runs always; gate the *steps*. On a no-app repo the job concludes `success` via a single "no suite — pass by contract" step. (pass-not-skip)
- **Option B:** Drop `functional-test`/`e2e-test` from the platform repo's required-context list only. (per-repo carve-out)
- **Option C:** Leave it; merge platform PRs by admin override each time. (status quo)

## Decision Outcome

Chosen option: **Option A.** Remove the job-level `if: needs.detect-node.outputs.node == 'true'` from `functional-test` and `e2e-test`; move that condition onto each real step, and prepend a step gated on the inverse (`!= 'true'`) that emits a success notice. A job whose real steps are individually skipped still concludes `success`, so the required check reports `success` (not `skipped`) and branch protection is satisfied. App repos (`node == 'true'`) are byte-for-byte unchanged in behavior — the pass-by-contract step skips and the real suite runs.

Option B was rejected because it diverges the platform repo's required-context list from the app repos, which is exactly the per-repo drift the template model exists to prevent. Option C is the bug.

`test-writer` keeps its existing job-skip: it is not a required context, so its skip does not block, and it has no merge-gate consequence.

## Consequences

### Positive

- Platform-repo implementer PRs become mergeable; the auto-merger (ADR-0021) can close the loop on `agentic-dev-environment`, draining its backlog.
- One uniform required-context list across every fleet repo; branch protection no longer depends on a repo having a Node app.
- The misleading "skip is satisfied" assumption is removed from the codebase before it causes a second silent deadlock.

### Negative

- Two jobs now spin up a runner to do near-nothing on the platform repo (~seconds, negligible). Accepted as the cost of a uniform contract.

### Neutral

- The required-context *names* are unchanged, so no branch-protection reconfiguration is required on any repo — only the workflow body changes.

## Pros and Cons of the Options

### Option A: pass-not-skip (chosen)

- ✅ Pro: Uniform required-context contract across apps and frameworks.
- ✅ Pro: Zero behavior change on app repos; the diff is mechanical and auditable.
- ✅ Pro: No branch-protection edits needed.
- ❌ Con: Slightly more verbose workflow (per-step `if`).

### Option B: per-repo carve-out

- ✅ Pro: Smallest possible change (delete two required contexts on one repo).
- ❌ Con: Platform repo's gate now differs from the app repos — drift the template model forbids.
- ❌ Con: Re-introduces the same trap for any future no-app repo that copies the standard required-context list.

### Option C: status quo (admin override)

- ✅ Pro: No code change.
- ❌ Con: Defeats ADR-0021 — the loop pools at the last stage on the platform repo, indefinitely, and hides behind green dashboards.

## Implementation notes

- Affected workflow: `.github/workflows/claude-pr-review.yml` — `functional-test` and `e2e-test` jobs; `detect-node` comment corrected.
- No branch-protection API changes; required contexts keep their names.
- The fix PR is itself subject to the deadlock it cures (its own `functional-test`/`e2e-test` skip → blocked). It and the three already-blocked platform PRs (#100, #101, #103) require a one-time human admin merge to land; `enforce_admins=false` permits this. After the fix lands, subsequent platform PRs flow automatically.
- The bot/CI token cannot push `.github/workflows/` changes (lacks `workflow` scope by design); this change is pushed by the human.

## Links

- [ADR-0018](0018-reusable-review-workflow.md) — the reusable review workflow this modifies.
- [ADR-0021](0021-autonomous-merge.md) — the auto-merge gate whose "checks pass" assumption this repairs.
- [ADR-0023](0023-origin-based-autonomy-boundary.md) — places platform-repo merge-gate changes on the human side of the autonomy boundary.
- GitHub docs — "Troubleshooting required status checks": a required check that is skipped rather than reported successful leaves a PR unmergeable.
