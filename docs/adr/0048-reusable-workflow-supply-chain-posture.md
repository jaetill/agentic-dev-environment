# ADR-0048: Reusable-workflow supply-chain posture — harden upstream + scope secrets; first-party reusables ride @main, pin only third-party

- **Status:** Accepted — ratified by Jason 2026-06-17 (directed: "write the ADR, accept it, push it, merge it, update the codebase to reflect the change").
- **Date:** 2026-06-17
- **Deciders:** Jason Tilley
- **Tags:** ci-cd, security, supply-chain, ai-workflows

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Complements [ADR-0034](0034-implementer-reusable-distributed.md) (reusable-distributed model) and [ADR-0006](0006-secrets.md) (secrets). Resolves meal-planner #132 (and the same finding fleet-wide).

## Context and Problem Statement

App repos are thin callers of this platform's reusable workflows (ADR-0034): `uses: jaetill/agentic-dev-environment/.github/workflows/<x>.yml@main` with `secrets: inherit`. A code-review finding (meal-planner #132) flagged this as a supply-chain risk: `@main` is a mutable ref, and `secrets: inherit` forwards **every** repo secret to the upstream code on each run — so a tampered upstream commit, or any flaw in the reusable, has the blast radius of all of an app's secrets.

The obvious fix the finding proposed — pin the reusable to a commit SHA, as we do for third-party actions — is wrong here for three reasons: (1) it **breaks ADR-0034 propagation** (apps freeze on an old reusable and stop receiving platform fixes, including security fixes *to the reusable itself*); (2) it **cannot merge** — editing a caller workflow makes its content differ from the default branch, which fails the GitHub App-token validation gate ("workflow file must match the default branch"), so the PR's own review battery can never go green; (3) because every SHA bump is another caller-file edit, it **institutionalizes a recurring merge dam**. So: what posture actually reduces the risk without those costs?

## Decision Drivers

- The upstream is **first-party** — we own `agentic-dev-environment`. The threat is "tampered/compromised upstream," not "untrusted third party."
- ADR-0034 propagation (apps ride `@main` so platform fixes flow automatically) is load-bearing and must be preserved.
- Any change to a caller workflow file needs a maintainer admin-merge (App-token gate) — so the posture must minimize how often caller files must change.
- Don't create merge/issue dams (the recurring failure class this fleet keeps hitting).

## Considered Options

- **A — Pin first-party reusables to SHA (+ auto-bump)** (the #132 ask): immutable ref, but breaks propagation, can't auto-merge, recurring dam, and can *delay* reusable security fixes from reaching apps.
- **B — Harden the upstream + scope secrets** (chosen): make `@main` trustworthy at the source (branch protection: no force-push, no deletions, required checks) so the mutable-ref risk is mitigated for the whole fleet at once with **zero caller edits**; and replace `secrets: inherit` with explicit minimal `secrets:` blocks to cut blast radius.
- **C — Accept `@main` + `secrets: inherit`, document only:** cheapest, no dams, but leaves the blast-radius risk unaddressed.
- **D — Mint the App token in the caller, pass a short-lived token (not the private key) to the reusable:** strongest (the crown-jewel private key never leaves first-party ground), but a larger refactor; recorded as the future structural option.

## Decision Outcome

**Chosen: Option B**, with **D** named as the future hardening if the App private key flowing to the reusable at all becomes unacceptable.

1. **First-party reusable workflows are referenced at `@main`** by app callers (ADR-0034). This is **accepted policy, not a defect.** The mutable-ref risk is mitigated at the source: this platform's `main` is branch-protected — `allow_force_pushes: false`, `allow_deletions: false`, the six required checks, and the capability-delta merge firewall (ADR-0047). `@main` is therefore "the reviewed platform HEAD," not an attacker-writable ref.
2. **Third-party actions remain SHA-pinned** (`anthropics/claude-code-action`, `actions/*`, etc.) — unchanged. Pinning is the right tool for code we do **not** own; `@main` is the right tool for first-party reusables we **do** own and protect.
3. **Secret forwarding is explicit and minimal.** Callers pass only the secrets a reusable consumes, not `secrets: inherit`:
   - `claude-pr-review.yml` caller → `CLAUDE_CODE_OAUTH_TOKEN` (`GITHUB_TOKEN` is auto-provided).
   - `claude-implementer.yml` caller → `CLAUDE_CODE_OAUTH_TOKEN`, `IMPLEMENTER_PAT`, `FLEET_APP_ID`, `FLEET_APP_PRIVATE_KEY`.
   This stops an app's *unrelated* secrets (AWS/DB/Vercel/Sentry/etc.) from flowing to the review/implementer reusables. Rolling this out edits caller workflow files, so it lands via maintainer **admin-merge** per app (the App-token gate) — a deliberate one-time batch, **never** left `ready-for-implementer` (that label is a trap: it re-dispatches PRs that can't merge).
4. **`enforce_admins` stays `false`** deliberately: the maintainer needs the admin-merge escape hatch precisely for caller-workflow changes (which can't pass the App-token gate). The residual "compromised admin account" vector is covered by admin-account hygiene (2FA), not by removing the override.

## Consequences

### Positive

- The mutable-`@main` risk is mitigated fleet-wide with no caller edits (the upstream is already hardened — verified 2026-06-17).
- Propagation (ADR-0034) is preserved: apps keep receiving reusable fixes, including security fixes, automatically.
- Blast radius drops once secret-scoping lands: a flaw in a reusable can touch only the secrets it's handed.
- The recurring "code-review re-files the `@main` finding → un-mergeable PR" loop ends: reviewers are taught this is accepted policy (below).

### Negative

- Secret-scoping (decision 3) must be admin-merged per app (App-token gate) — one-time toil, accepted. Until it lands, blast radius is unreduced (decision 1 already covers the mutable-ref vector).
- The App private key still flows to the implementer reusable (decision 3 scopes *which* secrets, not this one). Closing that fully is Option D, deferred.

### Neutral

- Third-party pinning practice is unchanged; this ADR only clarifies that it does **not** extend to first-party reusables.

## Pros and Cons of the Options

### A — Pin first-party reusables to SHA
- ✅ Immutable ref; matches third-party pinning intuition.
- ❌ Breaks ADR-0034 propagation; can delay reusable security fixes reaching apps; can't auto-merge (App-token gate); recurring merge dam.

### B — Harden upstream + scope secrets (chosen)
- ✅ Mitigates the mutable-ref vector fleet-wide with zero caller edits; preserves propagation; cuts blast radius; ends the re-file loop.
- ❌ Secret-scoping is a one-time admin-merged batch; App private key still flows (→ D later).

### C — Accept + document only
- ✅ Cheapest; no dams.
- ❌ Leaves blast radius unaddressed.

### D — Token-in-caller (short-lived token, not the private key)
- ✅ Strongest: crown-jewel private key never leaves first-party ground.
- ❌ Larger refactor; still admin-merged caller edits. Deferred as the future hardening.

## Implementation notes

- **Upstream hardening (decision 1):** verified in place — `allow_force_pushes: false`, `allow_deletions: false`, 6 required checks on platform `main`. No change required; `enforce_admins` intentionally left `false` (decision 4).
- **Reviewer guidance (decision 1):** `plugins/ai-team/agents/security-reviewer.md` — a first-party reusable `@main` ref is accepted (this ADR) and must NOT be filed as a finding; still flag (a) third-party actions not SHA-pinned, (b) `secrets: inherit` to any reusable, (c) a first-party ref when the upstream's `main` lacks branch protection.
- **Standard (decisions 1–3):** `docs/standards/02-ci-cd.md` §8 + the shipped copy `plugins/ai-team/skills/standards-ci-cd/standard.md` gain a "Workflow reference & secret-forwarding policy" subsection.
- **Secret-scoping rollout (decision 3):** seven app-repo caller PRs (`claude-pr-review.yml` + `claude-implementer.yml`), admin-merged by the maintainer — tracked, not `ready-for-implementer`.
- **`CLAUDE.md`:** a one-line entry under decision-making (don't pin first-party reusables).
- Resolves meal-planner #132.

## Links

- [ADR-0034](0034-implementer-reusable-distributed.md) — reusable-distributed model (the `@main` propagation this preserves).
- [ADR-0006](0006-secrets.md) — secrets standard (scope-minimal forwarding extends it to reusable calls).
- [ADR-0047](0047-firewall-gates-on-capability-delta.md) — the merge firewall that (with branch protection) makes `@main` "the reviewed platform HEAD."
- meal-planner #132 — the finding this resolves.
