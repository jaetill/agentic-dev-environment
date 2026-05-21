# ADR-0018: Distribute platform workflows via reusable workflows

- **Status:** Accepted
- **Date:** 2026-05-21
- **Deciders:** Jason Tilley (with AI architectural review)
- **Tags:** ci-cd, distribution, workflows, drift

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR.

## Context and Problem Statement

[ADR-0015](0015-platform-as-plugin.md) eliminated drift for the platform's agents, hooks, commands, and skills by packaging them as a plugin — projects subscribe to one canonical source instead of holding copies. But the Claude Code plugin format does **not** carry `.github/workflows/`. Workflows were left on the old copy-paste model.

The consequence is exactly the drift ADR-0015 was meant to end, just relocated. Each subscribing project holds a full **inlined copy** of the agent workflows (`claude-pr-review.yml` and friends). game-night-pwa's inlined `claude-pr-review.yml` even says so in its header: *"Inlined from the platform's reusable workflow ... When the platform repo is published, this can be replaced with `uses:`."* The copies have since diverged — the platform's reusable `claude-pr-review.yml` is 4 jobs and stale; game-night-pwa's inlined copy has grown to 8; the other projects' copies are in unknown states.

The inlining was always a stopgap: you cannot `uses:` a reusable workflow from a repo that is not on GitHub, and the platform repo was local-only. **That blocker is now gone — the platform repo is public.** How should platform workflows be distributed and kept in sync across projects?

## Decision Drivers

- **Eliminate drift** — the same goal ADR-0015 achieved for plugin components, applied to the one component class it could not cover.
- **Single source of truth, version-pinnable** — consistent with how the plugin is versioned.
- **Match GitHub's native mechanism** rather than inventing one.
- **Do not break the autonomous-loop event cascade** — the implementer→reviewers→fix-iteration loop depends on bot actions triggering downstream workflows.
- **The platform repo is now public** — cross-repo `uses:` is unblocked.

## Considered Options

- **Option A: Reusable workflows + `uses:`** — one canonical reusable per workflow in the platform repo; each project carries a thin caller stub.
- **Option B: Terraform `github_repository_file`** — manage workflow files as Terraform resources; `tofu plan` detects drift, `tofu apply` reverts it.
- **Option C: Drift-check CI job** — a job that diffs each project's workflow against the canonical copy and flags divergence.
- **Option D: Status quo** — keep inlined copies.

## Decision Outcome

Chosen option: **Option A — reusable workflows referenced via `uses:`**, because it is GitHub's purpose-built mechanism for exactly this problem and it eliminates drift *structurally*: a caller that does `uses:` has no local copy of the logic, so there is nothing to drift. It is also the plan the projects' own inline comments already committed to, and it gives the same version-pinning surface as the plugin (`@v0.x` once stable). It is, precisely, "ADR-0015 for workflows."

Two findings shaped the decision and are recorded here because they are non-obvious and load-bearing:

### The `GITHUB_TOKEN` cascade constraint fixes the bot identity

The autonomous loop is a cascade: the implementer opens a PR → that must trigger the reviewers → a reviewer's `VERDICT: BLOCK` must trigger fix-iteration → a fix push must re-trigger the reviewers. GitHub deliberately **does not let actions performed with the automatic `GITHUB_TOKEN` trigger other workflows** (its infinite-loop prevention). `github-actions[bot]` *is* the `GITHUB_TOKEN` identity. So the loop's actors cannot be `github-actions[bot]` — their events would be dead-ends and the loop would never advance. The actors must use a GitHub App or PAT identity, whose events *do* cascade. The platform's `claude[bot]` (the Claude GitHub App) is therefore not cosmetic; it is structurally required. This rules out "just pass the workflow `GITHUB_TOKEN`" as a way to sidestep the validation caveat below.

### The reusable-workflow validation caveat (#443) — tested, resolved

claude-code-action's default Claude-App auth performs an OIDC → App-token exchange that validates "the workflow file matches the default branch." [Issue #443](https://github.com/anthropics/claude-code-action/issues/443) reported this validation **breaking reusable workflows** — the exchange failed with `App token exchange failed: Workflow validation failed`. Anthropic shipped a cross-repo fix; the issue thread left it ambiguous whether the fix fully held.

This was tested empirically before accepting this ADR. A throwaway cross-repo probe — a reusable workflow on the platform repo, `uses:`'d from game-night-pwa — ran claude-code-action with the default `claude[bot]` App auth. Result (run `26201992473`, 2026-05-21): the log shows `Exchanging OIDC token for app token... App token successfully obtained` — exactly the step #443 broke. **The caveat is resolved for this platform's setup.** No custom App or PAT is needed; the `claude[bot]` path works with cross-repo reusables; the implementer's `claude[bot]` identity filters need no change.

## Consequences

### Positive

- **Drift eliminated structurally.** A `uses:` caller has no local copy of the workflow logic — there is nothing to diverge. Same property the plugin gave agents and hooks.
- **Single source of truth, version-pinned.** One canonical reusable per workflow; consumers pin `@v0.x` (or float `@main`). Symmetry with the plugin: plugin pinned by version, reusable workflows pinned by tag.
- **No new infrastructure.** `uses:` is native GitHub; no Terraform state, no provider, no drift-detection job to maintain.
- **Closes the last ADR-0015 gap.** Workflows were the one platform component the plugin migration could not cover.
- **The `claude[bot]` identity and the autonomous-loop cascade are preserved** — the test confirmed the default App path works inside reusables.

### Negative

- **Callers still need a thin stub** (a trigger plus the `uses:` line). That stub can technically drift, but it is small enough to have negligible drift surface.
- **The reusable's interface must stay stable** — a breaking change to a reusable's inputs/secrets affects every caller at once. Mitigated by version-pinning: callers stay on a tag until they choose to bump.
- **Dependency on Anthropic continuing to support cross-repo reusables.** Mitigated: tested and working today, and the `ci-health` watcher (ADR-0017) would surface a regression.

### Neutral

- **The platform's reusable workflows must be reconciled to the de-facto-current versions before projects switch.** game-night-pwa's inlined copies have grown past the platform's stale reusables (e.g., `claude-pr-review.yml`: 4 jobs in the platform reusable vs. 8 in game-night-pwa's inlined copy, plus missing `id-token: write` and `--permission-mode bypassPermissions`). Reconciliation is the bulk of the rollout work.
- The platform standardizes agent auth on `CLAUDE_CODE_OAUTH_TOKEN` (per the token work of 2026-05-21); the reconciled reusables use the OAuth-first pattern, and `ANTHROPIC_API_KEY` is not required.

## Pros and Cons of the Options

### Option A: Reusable workflows + `uses:` (chosen)

- ✅ Pro: GitHub-native; drift becomes structurally impossible (no local copy).
- ✅ Pro: Version-pinnable; consistent with the plugin's versioning model.
- ✅ Pro: Zero new infrastructure.
- ✅ Pro: The plan the projects' own comments already committed to; blocker (platform not public) is cleared.
- ❌ Con: Callers keep a thin stub; reusable interface changes are fleet-wide (mitigated by pinning).
- ❌ Con: Relies on claude-code-action's cross-repo-reusable support (tested working; #443 resolved).

### Option B: Terraform `github_repository_file`

- ✅ Pro: Real drift detection + revert via the existing `drift-detector` / `iac-drift-detect` machinery.
- ❌ Con: Heavyweight — Terraform state, a provider, and apply cycles to solve "keep one file synced across N repos," which `uses:` does natively with zero state.
- ❌ Con: Mild circularity — workflows run Terraform; Terraform would manage workflows.
- ❌ Con: Detection-and-revert still needs someone (or something) to run `apply`.

### Option C: Drift-check CI job

- ✅ Pro: Lighter than Terraform; needs no migration.
- ❌ Con: Detection, not prevention — it watches drift instead of making it impossible.
- ❌ Con: A band-aid; the copies still exist and still diverge between checks.

### Option D: Status quo (inlined copies)

- ✅ Pro: No migration.
- ❌ Con: Drift is guaranteed and already happening (4-job vs 8-job `claude-pr-review.yml`).
- ❌ Con: Diverges from ADR-0015's principle for no reason now that the publish blocker is gone.

## Implementation notes

- **Identity:** retain `claude[bot]` (the default Claude GitHub App). No custom App or PAT. No change to `claude-implementer.yml`'s `claude[bot]` identity filters — the #443 test confirmed the App path works inside cross-repo reusables.
- **Auth:** reconciled reusables use the OAuth-first pattern (`claude_code_oauth_token` with `anthropic_api_key` as optional fallback); `CLAUDE_CODE_OAUTH_TOKEN` is the required secret.
- **Rollout (follow-up work):**
  1. Reconcile each platform reusable up to the de-facto-current version (start with `claude-pr-review.yml`: 4 → 8 jobs, add `id-token: write`, `--permission-mode bypassPermissions`, `allowed_bots`).
  2. Replace each subscribing project's inlined workflow with a thin `uses:` caller stub, one project at a time, verifying each.
  3. Version-pin: float `@main` during the migration; pin to a release tag once the reusable interfaces stabilize.
- **Affected workflows:** `.github/workflows/claude-pr-review.yml` (and any other reusable that projects inlined), the caller stub in each of the ~8 subscribing projects.
- **#443 test artifact:** throwaway probe run `26201992473` on game-night-pwa (reusable `_test-reusable-claude.yml` on the platform repo, caller `_test-caller-claude.yml` on game-night-pwa); both files removed after the test.

## Links

- [ADR-0015 — platform as plugin](0015-platform-as-plugin.md) — the sibling decision; this ADR extends its no-drift principle to the one component class plugins cannot carry.
- [ADR-0017 — async orchestration](0017-async-orchestration.md) — the `ci-health` watcher defined there backstops the "dependency on Anthropic" risk.
- [claude-code-action issue #443](https://github.com/anthropics/claude-code-action/issues/443) — the reusable-workflow validation caveat, tested and resolved.
- [GitHub: reuse workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows) — the `uses:` mechanism.
- [GitHub: triggering a workflow from a workflow](https://docs.github.com/en/actions/using-workflows/triggering-a-workflow) — documents that `GITHUB_TOKEN` events do not cascade.
