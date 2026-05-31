# ADR-0025: Owner-guard the platform repo's opened auto-pickup

- **Status:** Proposed
- **Date:** 2026-05-30
- **Deciders:** Jason Tilley
- **Tags:** security, ai-workflows, governance, ci-cd

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. Closes a concrete exposure in the Mode-A pickup model (ADR-0026, ADR-0017); does not reopen the trust model itself.

## Context and Problem Statement

The implementer's Mode A `initial` job on the platform repo (`agentic-dev-environment`) auto-picks-up on `issues.opened` when the issue carries `bug`/`defect`/`feature-request` and the author is a non-bot. That repo is **public**, and it ships issue templates (`bug-report.md` → `labels: bug`, `feature-request.md` → `labels: feature-request`) that auto-apply those labels. Therefore **any GitHub user** can open an issue via a template and start an implementer run on the repo that holds the team's gates, agents, and standards — the implementer executes with `--permission-mode bypassPermissions` on an attacker-controlled issue body.

The seven app repos do not have this exposure: their `initial` job fires only on a `labeled` event (`ready-for-implementer`/`severity:critical`/`source:sentry`), and applying those labels needs triage/write access, so a non-maintainer's request is inert until a maintainer opts it in.

The existing backstops (the competence gate, the review battery, and the auto-merge human-origin hold under ADR-0023) prevent a hostile change from *merging*, but only after the work is already done. That places the human checkpoint at merge time, which wastes implementer runs and forces the owner to triage attacker-authored PRs. The human-in-the-loop checkpoint should precede implementation, not merge.

How do we ensure no non-owner request consumes an implementer run on the platform repo before the owner is in the loop?

## Decision Drivers

- **Human-in-the-loop must precede implementation, not merge.** A request from anyone other than the owner should start no autonomous work until the owner opts it in. Build-then-hold is poor resource orchestration.
- **Match the posture the app repos already have.** Non-maintainer requests are inert there; the platform repo should be no weaker.
- **Preserve the owner's own fast-path.** The owner opening a labelled issue on the platform repo *is* the owner being in the loop; that convenience should remain.
- **Mechanical, spoof-proof gate.** `author_association` is set by GitHub from the actor's relationship to the repo and is not user-controllable.

## Considered Options

- **Option A:** Add `author_association == 'OWNER'` to the platform repo's `opened` pickup path (both `initial` and `initial-iac`).
- **Option B:** Remove the `opened` pickup path entirely — make the platform repo label-gated like the app repos (owner opts in every issue with `ready-for-implementer`).
- **Option C:** Leave it; rely on the competence gate + review + merge-time human-origin hold.

## Decision Outcome

Chosen option: **Option A.** The `opened` path on both `initial` and `initial-iac` now requires `github.event.issue.author_association == 'OWNER'`. A non-owner's templated issue starts no work; it waits, inert, until the owner reviews it and applies `ready-for-implementer` — at which point it follows the same path as any opted-in item (and remains human-origin, so it still takes the human-merge checkpoint per ADR-0023).

Option A over B because the owner's self-filed fast-path on the platform repo is a deliberate convenience worth keeping, and the owner opening an issue already satisfies "the human is in the loop." Option C is the status quo this ADR rejects: the checkpoint sits at merge, after the run is spent.

## Consequences

### Positive

- No non-owner request can consume an implementer run on the platform repo. The human checkpoint precedes implementation across the whole fleet.
- Closes a prompt-injection / abuse surface on a public repo whose implementer runs with `bypassPermissions`.
- The owner's own opened-issue fast-path is unchanged.

### Negative

- A trusted human *collaborator* (not the owner) opening an issue on the platform repo no longer fast-paths; they would apply `ready-for-implementer` like any opt-in. Acceptable — there are no such collaborators today, and broadening to `OWNER, COLLABORATOR` is a one-token change if that ever changes.

### Neutral

- App repos are unaffected — they were never exposed.

## Pros and Cons of the Options

### Option A: owner-guard the opened path (chosen)

- ✅ Pro: Closes the exposure while preserving the owner's fast-path.
- ✅ Pro: Spoof-proof, mechanical, two-line change.
- ❌ Con: The platform repo keeps a special case (an `opened` path) the app repos don't have.

### Option B: drop the opened path (label-gate like app repos)

- ✅ Pro: Maximum uniformity; removes the special case entirely.
- ❌ Con: Costs the owner an extra `ready-for-implementer` click on their own platform issues with no security gain over A.

### Option C: status quo

- ✅ Pro: No change.
- ❌ Con: The checkpoint stays at merge; attacker-authored runs still execute and must be triaged. The waste this ADR exists to remove.

## Implementation notes

- Affected workflow: `.github/workflows/claude-implementer.yml` — `initial` and `initial-iac` `opened` conditions gain `&& github.event.issue.author_association == 'OWNER'`.
- No branch-protection or template changes; the public templates stay (they remain correct for owner-filed issues).
- Verified context: the seven app repos are `opened-pickup=False` (label-gated) and carry no exposure.

## Links

- [ADR-0026](0026-agentic-implementer.md) — the implementer (Mode A) this guards.
- [ADR-0017](0017-async-orchestration.md) — the promoter/window gate and the owner fast-path it bypasses.
- [ADR-0023](0023-origin-based-autonomy-boundary.md) — the merge-time human-origin hold this complements by moving the checkpoint earlier.
- GitHub docs — `author_association` values (OWNER / MEMBER / COLLABORATOR / CONTRIBUTOR / NONE) on issue/PR payloads.
