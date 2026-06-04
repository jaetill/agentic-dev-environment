# ADR-0034: The implementer workflow is reusable-distributed, not copied per repo

- **Status:** Accepted — ratified by Jason 2026-05-31; platform pattern live-validated the same day.
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ci-cd, ai-workflows, orchestration

## Context and Problem Statement

[ADR-0018](0018-workflow-distribution.md) established that fleet workflows should be **reusable-distributed** — the logic lives once in the platform repo and each project carries a thin caller — so behaviour changes propagate without per-repo edits. `claude-pr-review.yml` follows this. But `claude-implementer.yml` was **inline-copied into all 8 repos**: each held the full ~600-line workflow. Every change to implementer behaviour therefore required editing 8 files, and the copies drifted (mixed default-branch handling, differing trigger conditions — see the implementer-drift reference). In a single working session this copy-drift forced two separate N-repo hand-edits (the ADR-0030 dispatch trim and the ADR-0033 plan-gate inversion), and it would force a third for the upcoming merge-autonomy change. The drift is not hypothetical; it is a recurring tax.

## Decision Drivers

- Single source of truth for the implementer, matching the `claude-pr-review.yml` precedent and ADR-0018.
- Behaviour changes should be a one-file edit, not an 8-repo propagation.
- The refactor must not change implementer behaviour — only where the code lives.
- Must keep working with the promoter's `gh workflow run claude-implementer.yml` dispatch, uniformly across the fleet.

## Considered Options

- **Option A:** Keep inline copies; accept the per-repo edit tax (status quo).
- **Option B:** Reusable workflow + thin per-repo caller (the ADR-0018 pattern `claude-pr-review.yml` already uses).
- **Option C:** A central implementer that operates cross-repo from the platform. Rejected — the implementer must run *in* the target repo (checkout, build, push), which a reusable called from the repo's caller does natively while a central actor does not.

## Decision Outcome

**Chosen: Option B.** The logic moves to `claude-implementer-reusable.yml` (`on: workflow_call`, three inputs: `issue_number`, `mode`, `bundle_issues`). Every repo — platform included — carries a thin `claude-implementer.yml` caller that triggers on `issues` / `issue_comment` / `workflow_dispatch`, forwards those inputs, and calls the reusable with `secrets: inherit`.

Two properties made the refactor near-zero-risk to the body:

- **`github` context is inherited.** A called workflow sees the *caller's* `github.event` / `github.event_name`, so every job's existing `if: github.event_name == 'issues' && …` and `github.event.*` reference works unchanged (the same inheritance `claude-pr-review.yml` already relies on).
- **The `inputs.` context name is shared** by `workflow_dispatch` and `workflow_call`, so the body's `inputs.issue_number` / `inputs.mode` / `inputs.bundle_issues` references needed no change — only the `on:` block moved them from `workflow_dispatch.inputs` to `workflow_call.inputs`.

The reusable keeps the name `claude-implementer-reusable.yml`; the caller keeps `claude-implementer.yml`, so the promoter's `gh workflow run claude-implementer.yml --repo <repo>` dispatches uniformly across the fleet (every repo is now a caller).

**Live-validated** on the platform repo before fleet rollout: a `mode=cleanup-sweep` dispatch invoked the reusable, the `cleanup-sweep` job ran while `initial`/`initial-iac`/`fix-iteration`/`manual-dispatch` correctly skipped, and `secrets: inherit` carried the agent token.

## Consequences

### Positive

- Implementer behaviour is a **one-file edit** (the reusable); all repos pick it up via `@main`. The ADR-0033 plan-gate inversion that was pending propagation to 7 app repos is resolved automatically by this rollout — the app callers now run the platform's (already-inverted) reusable.
- Drift is structurally impossible — there is one body, not eight.
- Matches the `claude-pr-review.yml` distribution model; the fleet is now consistent.

### Negative

- A behaviour change on the reusable's `@main` reaches every repo at once — there is no per-repo staging. Acceptable: the review battery and merge gate still gate every resulting PR, and the reusable is itself change-controlled.
- One indirection added (caller → reusable) when reading the workflow.

### Neutral

- Pinned to `@main` (like `claude-pr-review.yml`), not a version tag; if the fleet later wants release-pinned workflows, that is a separate ADR-0018 follow-up applying to both reusables equally.

## Pros and Cons of the Options

### Option A: inline copies (status quo)

- ✅ Pro: per-repo independence; a change can be staged one repo at a time.
- ❌ Con: every change is an 8-repo edit; the copies drift; it contradicts ADR-0018.

### Option B: reusable + thin caller (chosen)

- ✅ Pro: single source of truth; one-file changes; matches the existing pr-review pattern; drift eliminated.
- ❌ Con: `@main` changes hit the fleet at once (mitigated by the downstream review/merge gates).

### Option C: central cross-repo implementer

- ✅ Pro: fully centralized.
- ❌ Con: the implementer must run in the target repo to build and push; a central actor cannot do that cleanly.

## Implementation notes

- `claude-implementer-reusable.yml` (platform) — the former `claude-implementer.yml` body, `on:` swapped to `workflow_call` with the three inputs; jobs unchanged.
- `claude-implementer.yml` (every repo) — thin caller: `issues`/`issue_comment`/`workflow_dispatch` → `uses: …/claude-implementer-reusable.yml@main` with `secrets: inherit`.
- App repos must carry `CLAUDE_CODE_OAUTH_TOKEN` and `IMPLEMENTER_PAT` (they already did, for the inline copy); `secrets: inherit` forwards them.

## Links

- Implements [ADR-0018](0018-workflow-distribution.md) for the implementer (the pattern `claude-pr-review.yml` already follows).
- Resolves the propagation half of [ADR-0033](0033-opted-in-features-build-without-plan-gate.md) — app repos inherit the inverted plan-gate via the reusable.
- Built on [ADR-0026](0026-agentic-implementer.md) — the implementer workflow this restructures.
