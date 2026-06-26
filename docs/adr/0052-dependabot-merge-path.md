# ADR-0052: Dependabot PRs bypass the LLM review battery and auto-merge for patch/minor

- **Status:** Accepted
- **Date:** 2026-06-23
- **Implementation:** Pending behind PR for `claude-pr-review.yml` short-circuit (this repo) + per-app `dependabot-auto-merge.yml` (game-night-pwa first); held for human ratify.
- **Deciders:** Jason
- **Tags:** ci-cd, security, dependabot, review-gate

> **Lifecycle:** `Proposed` (drafted, undecided) → `Accepted` (decided, awaiting human ratify) → `Ratified` (human-approved, PR merged, code changes pending) → `Implemented` (code changes merged).

> **Format:** This ADR follows [MADR 4.x](https://adr.github.io/madr/) with the platform's documented extensions.

## Context and Problem Statement

Dependabot-authored PRs run with a **read-only `GITHUB_TOKEN` and no access to repository secrets** — a deliberate GitHub safety posture, because the PR head is untrusted third-party code. Our required branch-protection checks on app repos include four contexts produced by the `claude-pr-review` reusable (`code-review`, `security-review`, `functional-test`, `e2e-test`), each of which mints/uses `CLAUDE_CODE_OAUTH_TOKEN`. With no secret available, those jobs **fail** rather than skip, so every Dependabot PR is permanently `BLOCKED` and the PRs pile up unmerged. How do we let safe dependency bumps flow through the gate without weakening review for human- or implementer-authored code?

## Decision Drivers

- A *skipped* required check does NOT satisfy branch protection (ADR-0024) — it blocks the merge. Any fix must make the required jobs **run and conclude green**, not skip.
- The fix touches **fleet-wide review machinery**: a guard that mis-fires for a non-Dependabot author would silently disable PR review across every repo. Correctness of the author predicate is paramount.
- The fleet App is deliberately NOT granted repo-admin (ADR-0023 trust posture), so admin-bypass merges are not an available mechanism.
- Dependabot PRs can't be reviewed by the LLM agents anyway (no auth), so the security story for dependency bumps must rest on **secret-free** signals: `npm audit`, gitleaks, lockfile integrity, and semver constraints.
- Major version bumps carry breaking-change risk and deserve a human; patch/minor are the high-volume, low-risk majority that justify automation.

## Considered Options

- Option A: Short-circuit the review battery to green for Dependabot + auto-merge patch/minor only (majors stay manual). **[chosen]**
- Option B: Review Dependabot PRs via a `pull_request_target` trigger so the workflow runs with the base repo's secrets.
- Option C: Admin-bypass merge of Dependabot PRs.
- Option D: Status quo — leave the required checks failing.

## Decision Outcome

Chosen option: **Option A**. The reusable `claude-pr-review.yml` jobs detect a Dependabot author (`github.event.pull_request.user.login == 'dependabot[bot]'`) and, for that author only, run a trivial "short-circuit to green" step while gating their real (token-minting / test) steps off — so each REQUIRED job concludes `success` without needing a secret. App repos add a `dependabot-auto-merge.yml` (`on: pull_request`) that enables GitHub auto-merge for `version-update:semver-patch` and `version-update:semver-minor`, and comments-without-merging on majors. Security for bumps rests on the secret-free gates (`npm audit`, gitleaks, lockfile integrity) plus semver. The two halves are coupled: auto-merge's `--auto` only fires once the required checks can go green, which is exactly what the Part-A short-circuit provides.

## Consequences

### Positive

- Dependabot PRs stop piling up; safe patch/minor bumps merge hands-free.
- The author predicate is an exact-string match on the PR author, so human/implementer PRs are wholly unaffected — review runs normally for them.
- No new privilege is granted: the fix needs neither repo-admin nor secrets on untrusted PRs.

### Negative

- The LLM review battery does not actually inspect Dependabot diffs; we accept that dependency-bump risk is covered by `npm audit` + gitleaks + lockfile + semver instead of agent review.
- Adds a per-author branch to the reusable's `if:` conditions — a maintenance surface that must keep the `==`/`!=` halves in sync.

### Neutral

- Major bumps still require a human to review and merge; throughput for majors is unchanged.

## Pros and Cons of the Options

### Option A: Short-circuit review to green + auto-merge patch/minor

- ✅ Pro: Keeps the untrusted PR on the safe `pull_request` trigger (no secret exposure to third-party code).
- ✅ Pro: Required checks legitimately conclude green (run, not skip), satisfying branch protection per ADR-0024.
- ✅ Pro: Exact-author predicate means zero blast radius onto human/implementer PRs.
- ❌ Con: Dependency diffs aren't agent-reviewed; relies on secret-free gates + semver discipline.

### Option B: `pull_request_target` review

- ✅ Pro: Would let the agents run with base-repo secrets and actually review the bump.
- ❌ Con: `pull_request_target` runs untrusted PR head code with access to secrets — the classic "pwn-request" exfiltration vector. Rejected on security grounds.

### Option C: Admin-bypass merge

- ✅ Pro: Simplest to merge a blocked PR.
- ❌ Con: Requires repo-admin, which the fleet App is deliberately NOT granted (ADR-0023). Mechanically unavailable and against the trust posture.

### Option D: Status quo

- ✅ Pro: No change, no risk of a mis-fired guard.
- ❌ Con: Dependabot PRs remain permanently blocked and accumulate — the problem this ADR exists to solve. Rejected.

## Implementation notes

- Affected workflow (platform): `.github/workflows/claude-pr-review.yml` — each token-minting/test job gains a Dependabot short-circuit. Guard is exactly `github.event.pull_request.user.login == 'dependabot[bot]'` (PR author, available under `workflow_call` because the `pull_request` event context propagates from the caller — every sibling job already reads `github.event.pull_request.*`). `github.actor` was rejected because it tracks the run INITIATOR, which mis-fires on a human synchronize of a Dependabot branch.
- Affected workflow (per app): `.github/workflows/dependabot-auto-merge.yml` — `on: pull_request`, `dependabot/fetch-metadata@v2`, `gh pr merge --auto --squash` for patch/minor, comment-only for majors. game-night-pwa is the first consumer; propagate to other app repos as a template change (per CLAUDE.md template-propagation principle), not per-repo edits.
- Secret-free security gates that still apply to Dependabot PRs: `npm audit`, gitleaks, lockfile integrity, semver constraints, plus the secret-free `destructive-change-check` job.

## Links

- [GitHub: Automating Dependabot with GitHub Actions](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/automating-dependabot-with-github-actions) — the documented `fetch-metadata` + `gh pr merge --auto` pattern and the read-only-token / no-secrets posture.
- [GitHub: Keeping your GitHub Actions and workflows secure — pwn requests](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/) — why Option B (`pull_request_target`) is rejected.
- ADR-0024 — a skipped required check is not satisfied; jobs must run-and-green.
- ADR-0023 — the fleet App is not granted repo-admin (rules out Option C).
- ADR-0047 — compositional self-change firewall; this is a fleet-wide review-path change held for human ratify.
- ADR-0048 — reusable-workflow secret declaration (`CLAUDE_CODE_OAUTH_TOKEN: required:false`) that this change leans on.
