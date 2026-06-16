# ADR-0047: The merge-time firewall gates on capability delta, not change structure

- **Status:** Accepted — ratified by Jason 2026-06-16 (directed: "I want that ADR amendments made. consider them ratified. push them."). This ADR *amends the self-change firewall* ([ADR-0019](0019-team-self-modification.md) / [ADR-0023](0023-origin-based-autonomy-boundary.md)), which is human-ratified by design; the ratifying human directed it.
- **Date:** 2026-06-16
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, autonomy, self-modification

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. Generalizes [ADR-0032](0032-additive-self-change-auto-lane.md)'s narrow single-agent-file lane into a capability-delta lane covering every self-change, and narrows the `requires-adr` and `compositional-self-change` triggers to match the already-ratified intent of [ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md) and `docs/standards/10-ai-workflows.md` ("routine/mechanical platform-repo fixes are eligible like any project fix").

## Context and Problem Statement

ADR-0039 moved the human checkpoint off the code merge (to test→prod, ADR-0043), keeping only two merge-time holds: `requires-adr:*` (architectural decisions) and `compositional-self-change` (the ADR-0019 firewall — the team's gates, roster, standards, security posture). The stated policy (ADR-0039 §"what still holds"; `standards/10-ai-workflows.md` condition 4) is narrow: *only* compositional self-changes hold; "routine/mechanical platform-repo fixes are eligible like any project fix."

The **enforcement** is far broader than the policy, and the gap is the reason the merge queue dams:

- `scripts/additive-self-change-guard.sh` classifies **any** changed file under `.github/workflows/`, `scripts/`, `plugins/ai-team/`, or `docs/` as compositional → `hold:compositional`. A SHA-pin of a third-party action, an `errexit` added to a script, a frontmatter typo fix, or a path-traversal guard all hold for a human — none of them change a gate, roster, standard, or security posture.
- The `compositional-self-change` and `requires-adr:*` labels are applied by an LLM agent (implementer/architect) on **structure** ("this touches a workflow" / "this touches the schema"), defensively, well beyond the policy. A security fix that adds an `owner_email` column to *enforce* an existing ownership model trips `requires-adr:schema`; an additive auth guard on an existing route trips `requires-adr:api-contract`.

The empirical cost (2026-06-16 fleet scan): of ~22 `hold:compositional` platform PRs, only ~4 actually touch the merge machinery; the other ~18 are security-neutral-to-positive hardening held for no risk reason. On ai-teacher, ~10 additive ownership/auth security fixes are frozen behind `hold:adr`. Because the issues those PRs would close stay open, the promoter re-dispatches them and the loop manufactures duplicate, now-conflicting PRs — the dam is self-amplifying.

The question: **what is the deterministic test for "a human must see this before it merges"?**

## Decision Drivers

- The firewall's purpose ([ADR-0019](0019-team-self-modification.md)) is to stop the loop from **expanding its own capability or weakening its own controls** without a human. Risk lives in *capability and control deltas*, not in *which file* changed.
- Fail closed: a misclassification must hold a safe change (a false hold — recoverable, the status quo), never auto-merge a risky one.
- Deterministic before LLM (ADR-0040 precedent): the gate must not rest on an agent's structural self-label.
- Don't relax the firewall — *sharpen* it. The four genuinely gate-touching PRs must still hold.
- Reconcile, don't re-decide: ADR-0039 already chose the narrow policy; this ADR makes enforcement match it.

## Considered Options

- **Option A — keep structural gating** (status quo): any platform-path or schema/contract touch holds for a human.
- **Option B — capability-delta gate** (chosen): a deterministic guard holds a self-change for human ratification iff it (a) touches gate/governance machinery, (b) weakens a security control, (c) adds an external dependency or egress, or (d) is a destructive/irreversible data migration. Everything else — additive guards, additive columns, SHA-pins, cosmetic/doc/agent-logic changes — auto-merges when green. The same capability lens narrows when the agents apply `requires-adr` / `compositional-self-change`.
- **Option C — drop the merge-time firewall entirely**, rely only on review + the prod gate (ADR-0043). Rejected — the loop must not be able to rewrite its own gates or broaden its own permissions unwatched, even with review.

## Decision Outcome

**Chosen: Option B.** The merge-time firewall gates on a **capability delta**, computed deterministically over the PR's changed files and diff by an externally-enforced guard (`scripts/capability-delta-guard.sh`, the generalized successor to `additive-self-change-guard.sh`). A green, reviewed PR **holds for human ratification (`hold:compositional`) iff at least one of:**

1. **Gate / governance machinery** — a changed file is one of the firewall's own surfaces: the auto-merger / promoter / dispatch (`triage-scan.yml`, `claude-implementer*.yml`, `urgent-poll.yml`), the review gates (`pr-review.yml`, `claude-pr-review.yml`), the guards themselves (`scripts/*guard*.sh`, `iac-guard.yml`), intake admission (`intake-steward.*`), deploy/branch protection (`deploy-prod.yml`, `emergency-deploy.yml`, `scripts/configure-*protection*`), `CODEOWNERS`, the rail-enforcer agents (`triage-bot`, `architect`, `security-reviewer`), or governance text (`docs/adr/**`, `docs/standards/**`).
2. **Control weakening** — an added *or removed* line carries protected vocabulary (the ADR-0032 guardrail denylist: auto-merge eligibility, scope cap, `FLEET_MAX`/throttle, severity calibration, the self-change/competence gate, origin/human checkpoint, permission/token/secret, model tier, inter-agent routing) — extended with IAM-broadening and check-disabling terms.
3. **New external dependency or network egress** (`requires-adr:new-external-dep` territory, ADR-0003).
4. **Destructive/irreversible data migration** (`DROP`, `ALTER COLUMN ... DROP`, mass delete — the existing ADR-0003 deterministic detector, unchanged).

Otherwise the change is **in-lane** and auto-merges when green, subject to a generous changed-line cap (blast-radius backstop, not a risk test) and the unchanged review + CI battery, the ADR-0035 IaC guard, and the per-run cap.

**The guard is authoritative, not the label.** The auto-merge gate runs the capability-delta guard on every candidate PR; `hold:compositional` is applied by the guard's verdict, not by trusting an LLM-applied `compositional-self-change` label. The label survives as a queryable/advisory hint, but the deterministic guard decides.

**`requires-adr` narrows to genuine architectural decisions.** The implementer/architect apply `requires-adr:schema` / `requires-adr:api-contract` only for a *new* data store/entity/relationship, a *new or changed public* API contract, or a destructive migration — never for an additive, restrictive change that *enforces an already-decided model* (adding `owner_email` to scope a query; adding an auth guard to an existing route). Enforcing an existing ownership model is implementation, not architecture.

The governing principle: **the human ratifies capability expansion and control weakening; the system ships everything the review battery can certify as routine.**

## Consequences

### Positive

- The ~18 hardening platform PRs and the ~10 additive ai-teacher security fixes become auto-mergeable when green; the dam clears and the duplicate-generation feedback loop stops (issues close on merge, so they aren't re-dispatched).
- The firewall gets *sharper*, not weaker: the ~4 PRs that actually touch the auto-merger still hold, now by a deterministic path rule instead of an LLM's guess.
- Enforcement matches the ratified policy (ADR-0039 / standard 10) — closing one of the "code says X, ADR says Y" inconsistency classes.

### Negative

- A broader auto-lane is a larger trusted surface than ADR-0032's single-file lane. Mitigated: fail-closed (any gate-path or guardrail-vocabulary hit holds), the denylist runs over added *and* removed lines, and auto-merged self-changes are logged to the standing `agent-self-change-log` issue for after-the-fact visibility.
- The deny-by-vocabulary rule will sometimes hold a genuinely-safe change (e.g., a SHA-pin of an action whose name contains `token`). Accepted as the safe failure; a narrow positive carve-out for pure `uses: …@<sha>` pins is included to keep the common hardening case in-lane.

### Neutral

- `compositional-self-change` as a label is demoted from gate-trigger to advisory; dashboards continue to read `hold:compositional`, which is now guard-applied.
- The prod gate (ADR-0043) and the IaC cascade (ADR-0035) are untouched — this ADR governs only the merge-time firewall.

## Pros and Cons of the Options

### Option A — structural gating (status quo)

- ✅ Pro: trivially conservative; any platform/schema touch is seen.
- ❌ Con: enforcement contradicts the ratified policy; dams the merge queue and manufactures duplicate conflicting PRs; the human's Discernment is spent rubber-stamping hardening.

### Option B — capability-delta gate (chosen)

- ✅ Pro: gates on actual risk; matches ratified intent; deterministic and fail-closed; sharpens rather than weakens the firewall; clears the dam.
- ❌ Con: larger trusted surface than ADR-0032; vocabulary denylist yields occasional safe-holds (mitigated by the pin carve-out + the log).

### Option C — drop the merge-time firewall

- ✅ Pro: maximal throughput; simplest.
- ❌ Con: lets the loop rewrite its own gates / broaden its own permissions with no human in the loop — the one thing ADR-0019 exists to prevent. Rejected.

## Implementation notes

- **Guard** — `scripts/capability-delta-guard.sh` (generalizes `additive-self-change-guard.sh`; the old name is kept as the invoked path or repointed in `triage-scan.yml`). Deterministic, no LLM: gate-machinery path denylist (narrow, enumerated), guardrail-vocabulary denylist over `git diff` added+removed lines (extended with IAM-broadening / check-disabling terms), destructive-migration detector, a pure-SHA-pin positive carve-out, and a generous changed-line backstop cap. Verdict: `HOLD` (→ `hold:compositional`) or `IN_LANE`. Unit-tested in `scripts/test-capability-delta-guard.sh` (SHA-pin in-lane, gate-machinery held, control-weakening held, additive column in-lane, destructive migration held, cosmetic in-lane).
- **Auto-merge gate** — `.github/workflows/triage-scan.yml`: the compositional hold is decided by the guard's verdict on every candidate PR (not by the `compositional-self-change` label); the `requires-adr:*` → `hold:adr` check is unchanged (architectural decisions still gate); the ADR-0035 IaC and ADR-0021/0024 checks-green gates are unchanged.
- **Agent labeling** — `plugins/ai-team/agents/implementer.md` and `architect.md`: narrow when `requires-adr:*` / `compositional-self-change` are applied to the capability-delta definition above; routine hardening is not compositional, and additive-restrictive schema/contract changes do not require an ADR.
- **Standards** — `docs/standards/10-ai-workflows.md` (auto-merge condition 4) and `docs/standards/12-self-modification.md`: define "compositional" as the capability delta; add the term to `docs/standards/00-terminology.md`.
- **Loop diagram** — `docs/diagrams/autonomous-loop-flow.md` ⑤ merge gate: the compositional branch is the capability-delta guard (generalizes the ADR-0032 `CG` branch).
- **Amended-by banners** — [ADR-0032](0032-additive-self-change-auto-lane.md) (lane generalized), [ADR-0023](0023-origin-based-autonomy-boundary.md) and [ADR-0019](0019-team-self-modification.md) (firewall predicate sharpened), [ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md) and [ADR-0044](0044-label-system-and-intake-steward.md) (the two merge-time holds narrowed to capability delta).

## Links

- [ADR-0032](0032-additive-self-change-auto-lane.md) — the single-agent-file additive lane this generalizes.
- [ADR-0019](0019-team-self-modification.md) — the firewall whose predicate this sharpens.
- [ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md) — merge autonomy; the policy this enforcement now matches.
- [ADR-0043](0043-prod-deploys-gate-on-environment-protection.md) — the human prod gate, untouched.
- [ADR-0003](0003-ci-cd.md) — the five `requires-adr` categories, narrowed in application here.
- [ADR-0040](0040-promoter-closes-stale-citation-findings.md) — the deterministic-before-LLM precedent.
