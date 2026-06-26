# ADR-0041: The fleet App is the loop's single write identity — retire `app/claude` pushes

- **Status:** Implemented
- **Date:** 2026-06-04
- **Implementation:** Implemented 2026-06-10 via #351, #356 (step 3 of the rollout plan: implementer wires fleet-App token into claude-code-action; auto-merger filter repoints; ratification was #200, 2026-06-04 (48bbd21))
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, security, identity, ci-cd

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Changes the implementer's push/PR identity; the auto-merge entry filter (ADR-0021 implementation detail) repoints in the same change.

## Context and Problem Statement

The implementer's code pushes and PRs author as `app/claude` — the official Claude GitHub App. That App is Anthropic's: its permissions cannot be extended by the fleet owner, and it lacks `workflows: write`. Consequence ([#183](https://github.com/jaetill/agentic-dev-environment/issues/183), promoter-filed): **every `scope:ci` fix fleet-wide is undeliverable** — the push is rejected at `.github/workflows/**`, and the promoter now refuses to dispatch the whole class as guaranteed failures. A second, quieter problem: a third-party App sits in the loop's write path at all.

The fleet already owns a first-party App — `jaetill-ai-triage-team` — which mints tokens for dispatch, merge, and cross-repo work, and whose permissions the owner controls.

## Decision Drivers

- `scope:ci` work must be deliverable; a standing undeliverable class rots the backlog.
- One write identity, owner-controlled, beats two identities forever.
- Author-keyed logic (auto-merge entry filter, `allowed_bots`, cockpit queries) must stay coherent.
- The fleet token's blast radius grows with `workflows: write` — injection hardening must precede the grant.
- Bounded, reversible migration.

## Considered Options

- **A — single identity:** pass the fleet-App token as `github_token` to claude-code-action in the implementer; all pushes/PRs author as `jaetill-ai-triage-team[bot]`.
- **B — split identity:** fleet token only for `scope:ci` runs; `app/claude` for the rest.
- **C — post-step push:** agent writes files; a separate fleet-token step commits workflow paths.

## Decision Outcome

**Chosen: A.** The fleet App becomes the loop's single write identity. B trades a one-time mechanical sweep for two-identities-forever complexity in every author-keyed check; C splits one logical change across two committer identities and adds the most machinery.

**Security sequencing (hard precondition):** the fleet token with `workflows: write` can rewrite the loop's own gates if hijacked. The known injection surfaces — **#126/#128** (script injection via `repository_dispatch` `client_payload` interpolation with the fleet token in scope) and **#138** (label-dispatch without applicator verification) — must be fixed and merged **before** the permission grant. The grant is the last step, not the first.

The step 3 implementation PR must carry the following preflight checklist in its description, and a reviewer must confirm all three are checked before approving:

- [ ] #126 merged
- [ ] #128 merged
- [ ] #138 merged

**Hard gate — capability-delta guard:** Any PR that wires, re-wires, or reverts the fleet-token `github_token` line in `claude-implementer-reusable.yml` is automatically held for human ratification. `additive-self-change-guard.sh` classifies `claude-implementer*.yml` as gate machinery ([ADR-0047](0047-firewall-gates-on-capability-delta.md)) and applies `hold:compositional`; the auto-merger will not merge a held PR. Only the repo owner can remove the hold, and doing so is the act of ratifying that the preflight checklist above is satisfied. Hold gate (blocks autonomous merge until the owner acts) + reviewer sign-off (preflight checklist confirmed) = the two-factor hard gate on this write-path. Soft prose alone is no longer the only enforcement.

**Migration order:**

1. Fix #126/#128 (+#138) — injection hardening lands first. (**Done** — #126, #128, and #138 all closed before step 3 was dispatched.)
2. Owner grants the App `Workflows: Read and write` and approves the installation update (human-only, account-side).
3. Wire `github_token: <fleet token>` into `claude-implementer-reusable.yml` (one file per ADR-0034) and the platform's caller; sweep author-keyed logic in the same PR: triage-scan auto-merge filter (`app/claude` → `app/jaetill-ai-triage-team`), `allowed_bots` entries, ADR-0032 digest queries, and ops-cockpit panels keyed on PR author.
4. **Staged rollout:** flip one small app repo first, drive one full issue→PR→auto-merge pass in a manual window (claude-code-action's behavior with a custom `github_token` across our modes is unverified — this run is the verification), then sweep the fleet.
5. Rollback at any point = revert the `github_token` line; `app/claude` resumes.

## Consequences

### Positive

- `scope:ci` class becomes deliverable; the promoter's refusal carve-out is removed.
- The third-party App leaves the write path; the loop's hands are owner-controlled end to end.
- One identity for every author-keyed check, query, and dashboard.

### Negative

- The fleet token becomes the highest-value credential in the system (contents + PRs + workflows, fleet-wide). Accepted only behind the injection-hardening precondition above; the credential never appears in agent-readable context (existing ADR-0019 boundary).
- PR-author history discontinuity: pre-migration PRs author as `app/claude`, post- as the fleet bot. Cockpit queries spanning the boundary must OR both authors or accept the seam.

### Neutral

- Review-battery workflows don't push code; they keep their current tokens. Only the implementer's write path changes.

## Pros and Cons of the Options

### A — single write identity (chosen)
- Good: one owner-controlled identity for every author-keyed check, query, and dashboard; removes the third-party App from the loop's write path.
- Bad: a one-time author-filter sweep; the fleet token becomes the highest-value credential (accepted behind the injection-hardening precondition).

### B — split identity (fleet token only for scope:ci)
- Good: smallest immediate blast radius.
- Bad: two PR-author identities forever; every author-keyed check must know both — permanent complexity to dodge a one-time sweep.

### C — post-step push
- Good: keeps `app/claude` as the primary author.
- Bad: splits one logical change across two committer identities; the most moving parts.

## Links

- [ADR-0020](0020-fleet-orchestration.md) — the fleet App and its token plumbing.
- [ADR-0021](0021-autonomous-merge.md) — the auto-merge gate whose entry filter repoints.
- [ADR-0034](0034-implementer-reusable-distributed.md) — why the wiring is a one-file change.
- #183 (formulation), #126 / #128 / #138 (security preconditions).
