# ADR-0043: Prod deploys gate on human approval via environment protection — staged evolution to test→prod promotion

- **Status:** Accepted — option C chosen by Jason in formulation of #179, 2026-06-04; this ADR is the decision record and phase-1 ships with it
- **Date:** 2026-06-04
- **Deciders:** Jason Tilley
- **Tags:** ci-cd, deployment, governance, autonomy

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR with a staged rollout. Amends [ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md) — its interim policy ("treat all merges/releases as test") is replaced by a real gate.

> **Scope correction (2026-06-04, same day — Jason):** as originally worded, "phase 2" read as the mandated end-state, forcing a two-environment topology on every platform adopter. That is wrong. **The platform invariant this ADR establishes is exactly one thing: the production deploy is human-gated** (environment protection, required reviewer). The phase-1 shape — a single environment whose deploy job is the protected prod deploy — is a **fully compliant, permanent** end-state, right-sized for low-merge-volume projects. The dual-target shape (test deploys ungated, gated promotion) is an **opt-in ergonomic upgrade** for projects where merge volume makes per-merge approval clicks expensive — this fleet opts in (the autonomous loop generates that volume), which is why per-app phase-2 issues exist here. Adopters choose per project; Standard 02 §1 carries the same rule.

## Context and Problem Statement

ADR-0039 moved the human checkpoint off the code merge and promised it would reappear at **test→prod promotion** for user-facing features (#179), with an interim policy of "treat all merges/releases as test." The deploy-wiring audit (2026-06-04, posted to #179) found the interim policy describes a world that does not exist:

- **Every fleet app deploys straight to production on every merge** to its default branch — S3+CloudFront+Lambda (meal-planner, jaetill-portal, draft, carto), GitHub Pages (game-night-pwa, splendor), or Vercel git auto-deploy (ai-teacher).
- **All seven are user-facing UIs.** Under #179's classifier, all of them gate.
- **No test environment exists anywhere** except ai-teacher's Vercel per-PR Previews.
- **release-please is version-tagging only** — no deploy is release-triggered, so there is no release rail to gate.

Post-0039, an autonomous merge is an autonomous prod deploy. The volume is rising as the backlog drains, and the human's own work now flows through the same pipe.

## Decision Drivers

- Close the ungated-prod exposure **now**, without waiting for test infrastructure that takes weeks to build.
- Do no throwaway work — whatever ships today must be a component of the end-state, not scaffolding to demolish.
- End-state remains ADR-0039's promise: the human approves **ship-to-users for user-facing changes**, not every deploy.
- Native mechanisms over custom machinery: GitHub Environments already do "deploy waits for a named reviewer."

## Considered Options

- **A — protect every prod deploy, permanently:** environment protection on each deploy job. Uniform and immediate, but re-creates a per-merge human click forever.
- **B — build dual-target first:** merge→test always; gated promotion→prod keyed to `user-facing` releases. The end-state, but prod stays ungated for the weeks it takes to build test targets × 6 apps.
- **C — staged (chosen):** A's protection now; per-app evolution to B, with the protection rule migrating from the deploy job to the promotion job as each app converts.

## Decision Outcome

**Chosen: C.**

**Phase 1 — ships with this ADR.** Every prod deploy waits for the maintainer's approval via GitHub Environment protection (required reviewer: `jaetill`):

| App | Mechanism |
|---|---|
| game-night-pwa, splendor | Protection rule on the existing `github-pages` environment (settings-only; `deploy.yml` already targets it; `docs.yml` is build-only and unaffected) |
| meal-planner, jaetill-portal, draft, carto | New `production` environment + protection rule; one `environment: production` line added to each `deploy.yml` deploy job |
| ai-teacher | **Deferred to phase 2.** Vercel's git auto-deploy bypasses GitHub gates; it is also the only app that already has a test surface (Vercel PR Previews), so it converts directly to the phase-2 shape (Actions-driven `vercel deploy` behind the protected environment). Tracked by its own issue. |

The configuration is recorded in `scripts/configure-deploy-protection.ps1` (repeatable, idempotent — the `configure-branch-protection.ps1` pattern), not applied as unrecorded clicking.

**Phase 2 — per-app, tracked by issues.** Each app gains a test target (preview bucket/path, preview branch, or Vercel Preview); merges then deploy to **test ungated**, and a separate **promotion job** deploys prod behind the *same* protected environment. At conversion, the protection rule migrates from the deploy job to the promotion job — nothing built in phase 1 is discarded. The `user-facing` narrowing (gate only feature promotions; let refactors/fixes flow) is designed at conversion time, when there is a promotion rail to attach it to.

**Approval ergonomics:** queued deploys for the same environment supersede — approving the latest run ships the newest state; stale waiting runs can be rejected in bulk. The waiting-for-approval state is the new "held by me" cockpit bucket (replacing the retired merge-hold), per the cockpit redesign direction.

## Consequences

### Positive

- The ungated-prod exposure closes the day this ADR lands, fleet-wide (ai-teacher excepted, tracked).
- ADR-0039's risk note ("interim policy is a policy assertion, not an enforced gate") is retired — the gate is enforced by GitHub, not by convention.
- The human checkpoint is now exactly where ADR-0039 promised: at ship-to-users, not at merge.

### Negative

- **Until an app converts to phase 2, every merge of that app waits for a human approval click** — the per-item click ADR-0039 removed at merge reappears at deploy. Accepted as a transitional cost, knowingly: the alternative was weeks of ungated prod. Mitigations: superseding approvals batch naturally; phase-2 conversions remove the click per app.
- Transitions can calcify. Counter-measure: phase-2 issues are filed **now**, per app, so the work is in the loop's backlog rather than in anyone's memory.
- A human absent for days delays user-visible fixes (including security fixes like game-night #150). Accepted: that is precisely the judgment call the gate exists to give the human; a critical fix can be approved from a phone.

### Neutral

- The IaC cascade (ADR-0035) is untouched — `scope:iac` guards govern infrastructure changes; this ADR gates application deploys.
- Merge autonomy (ADR-0039) is untouched — code still merges without a human; only the deploy now waits.

## Implementation notes

- `scripts/configure-deploy-protection.ps1` — creates/updates environments and required-reviewer rules across the fleet (idempotent).
- Four app-repo PRs adding `environment: production` to the `deploy` job (meal-planner, jaetill-portal, draft, carto). Deploy workflows are bespoke per-app (no template counterpart — verified), so downstream edits are correct here.
- Phase-2 tracking issues: one per app ("build test target + gated promotion job"), plus ai-teacher's Vercel conversion issue.
- ADR-0039 banner: interim policy superseded by this ADR.
- Cockpit follow-up (existing redesign direction): "awaiting deploy approval" becomes a first-class held-by-me series.

## Pros and Cons of the Options

### A — protect every prod deploy, permanently
- Good: uniform, immediate, native (~1 line/repo).
- Bad: re-creates a per-merge human click forever — the anti-pattern ADR-0039 just removed at the merge.

### B — build dual-target first
- Good: the true end-state — the human approves only user-facing promotions.
- Bad: prod stays ungated for the weeks it takes to build test targets across 6 apps.

### C — staged: A now, evolve to B per-app (chosen)
- Good: closes the exposure today with zero throwaway work (the protected environment is exactly what B's promotion job reuses); each app converts on its own schedule.
- Bad: per-merge clicks during the transition, which can calcify — countered by filing the per-app phase-2 issues now.

## Links

- [ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md) — the promise this ADR keeps; its interim policy is replaced.
- [ADR-0035](0035-auto-merge-safe-additive-iac.md) — IaC deploy cascade, unaffected.
- #179 — formulation issue; the 2026-06-04 deploy-wiring audit is recorded there.
