# ADR-0039: Code merge is autonomous regardless of origin; the human gate moves to test→prod promotion

- **Status:** Accepted — ratified by Jason's directed merge of PR #180, 2026-06-04 (squash 6bf77e7); the gate change is live
- **Date:** 2026-06-03
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, governance, autonomy

> **Amended by [ADR-0043](0043-prod-deploys-gate-on-environment-protection.md):** the interim policy ("treat all merges/releases as test") is **replaced** — the 2026-06-04 deploy-wiring audit found every fleet app deployed straight to prod on merge. ADR-0043 ships the promised prod gate: environment-protection approval on every prod deploy now, evolving per-app to test→prod promotion.

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Amends [ADR-0023](0023-origin-based-autonomy-boundary.md) (retires the origin-based human-merge hold) and [ADR-0021](0021-autonomous-merge.md) (condition 1 is now "linked issue present," not "linked issue is machine-origin"). This is the first half of the human-gate relocation; the prod-promotion gate itself is tracked in #179 and not built here.

## Context and Problem Statement

ADR-0023 set the autonomy boundary at **origin**: machine-origin work (Sentry, CloudWatch, agent-discovered findings) merges itself; human-origin work — anything a person filed, including Jason's own ideas — holds at the merge for a human click (`HHUM`). The intent was sound: the human's scarce resource is product judgment, and an outside party's request to change the product is where that judgment belongs.

In practice the boundary lands in the wrong place. Jason files most of the interesting work himself, so his own reviewed, green PRs pile up behind a merge click that is pure ceremony — he is not deciding *whether the code is good* (the review battery already did), he is just clicking merge on his own ideas. His words: "I don't want to have to merge my own ideas." The merge queue became the loop's bottleneck, and the cockpit's "held" numbers are dominated by work waiting on a rubber-stamp.

The real human decision is not *should this code merge* — it is *should this reach users*. That decision lives at **test→prod promotion**, not at merge. So: where should the human checkpoint sit, and what should merge do in the meantime?

## Decision Drivers

- The human's judgment is irreplaceable at **ship-to-users**, not at merging reviewed code. Merging is what the review battery's verdict is *for*.
- The merge queue is the loop's throughput bottleneck; an autonomy boundary that holds the human's own work defeats the loop's purpose for the person it serves most.
- The firewall must survive untouched: the loop still cannot change its own gates/roster/standards/security without a human-ratified ADR, and architectural decisions still route to the human.
- Don't half-ship. The prod-promotion gate is real work (per-project deploy wiring, a `user-facing` classifier, an environment-protection approval step) and is not yet designed; retiring the merge hold must not silently push unreviewed *user-facing* changes to prod. Until the prod gate exists, treat every merge/release as **test**.

## Considered Options

- **Option A — keep origin at the merge** (ADR-0023 status quo): human-origin work waits for a human merge.
- **Option B — merge is autonomous for all review-passing linked work; relocate the human gate to test→prod** (chosen): drop the origin-based merge hold; the human checkpoint becomes a prod-promotion approval for user-facing features.
- **Option C — merge autonomous, no human gate anywhere:** also drop the prod gate. Rejected — the human *does* want the ship-to-users call on things users interact with.

## Decision Outcome

Chosen option: **Option B.**

**Code merge is autonomous for any PR that (a) links an issue, (b) passes the full review + CI battery, and (c) is not otherwise gated below.** Origin no longer matters at the merge — a bug Jason filed and a Sentry-detected error now merge the same way. ADR-0023's `HHUM` origin hold is retired.

**The human checkpoint moves to test→prod promotion**, keyed on **user impact** rather than origin. For now, "user-facing" = anything a user interacts with via a UI; internal refactors, infra, bug fixes, and self-changes flow to prod without a gate. As apps grow API surfaces, the criteria broaden (future work). **This gate is not built in this ADR** — it is tracked in #179. **Until it exists, all merges and releases are treated as test**, so retiring the merge hold does not push anything to prod unreviewed.

**What still holds at the merge — unchanged:**

- **Architectural decisions** (`requires-adr:*`, ADR-0003's five categories) — still route to the human. Origin decides routine autonomy; an architectural decision is never routine.
- **Compositional self-changes** (`compositional-self-change` — the team's own gates, agent roster, standards, security posture) — still hold for human merge. This is the ADR-0019 firewall and it is the whole point; it is *not* what ADR-0039 relaxes.
- **The review + CI battery** — `code-review`, `security-review` (hard BLOCK), functional and e2e tests — all required, all unchanged. Autonomy is "routine reviewed work ships itself," never "skip the checks."
- **ADR-0035 IaC guard** (`scope:iac` needs a passing `iac-additive-guard`), **ADR-0032 additive self-change guard**, and the **per-run blast-radius cap** — all unchanged.

The governing principle shifts by one axis: **the human's checkpoint sits at the product's edge (does this reach users?), not at the codebase's edge (does this merge?).** Everything the review battery can certify, the system merges on its own.

## Consequences

### Positive

- Jason stops merging his own reviewed ideas; the merge bottleneck clears and the loop's throughput stops depending on his click latency.
- The cockpit's "held by me" bucket can be redefined from "PRs awaiting my merge" to "user-facing features awaiting my prod sign-off" — fewer items, and the right ones.
- One axis still, just the correct one: user-impact at prod, not origin at merge.

### Negative

- There is now a window where reviewed work is merged-to-`main` and (per the interim policy) deployed to **test/dev** with no human in the loop, including work Jason filed. Accepted: the review battery is the quality bar, and nothing reaches **prod** without the #179 gate once it lands.
- Until #179 ships, "everything is test" is a policy assertion, not an enforced gate — if a project's deploy wiring actually promotes to a user-facing prod on merge, this ADR's safety rests on that not being true yet. Implementation note: verify each project's deploy path before relying on the interim policy for that repo.

### Neutral

- ADR-0023's *analysis* (the human's resource is product judgment) is preserved; only the *location* of the checkpoint changes (merge → prod).
- This PR is itself a compositional self-change, so it holds for human merge per the firewall — Jason's merge is the ratification. Consistent: relaxing the origin gate does not relax the firewall that governs relaxing gates.

## Implementation notes

- `.github/workflows/triage-scan.yml` (auto-merge job): removed the `is_machine_origin` computation and the human-origin hold block. Kept the linked-issue sanity check, the `issue_meta` fetch (reused by the ADR-0032 and ADR-0035 gates), and every other gate. Updated the job header comment.
- `docs/diagrams/autonomous-loop-flow.md` (⑤ merge gate): the `MG3` machine-origin branch and the `HHUM` "hold for human merge" sink are removed; the remaining holds are the `requires-adr` and `compositional-self-change` branches.
- Amended-by banners on [ADR-0021](0021-autonomous-merge.md) and [ADR-0023](0023-origin-based-autonomy-boundary.md).
- **Not built here (tracked in #179):** the test→prod promotion gate — per-project deploy wiring audit, the `user-facing` classifier/label, and the manual-approval environment-protection step on prod deploys. Interim policy until then: all merges/releases are test, everything automatic.
- Unchanged: ADR-0021 conditions 2–3 (checks green, no `requires-adr`), ADR-0032 additive auto-lane, ADR-0035 IaC guard, the per-run cap, and the `compositional-self-change` firewall hold.

## Links

- [ADR-0023 — origin-based autonomy boundary](0023-origin-based-autonomy-boundary.md) — the origin merge hold retired here.
- [ADR-0021 — autonomous merge](0021-autonomous-merge.md) — condition 1 amended (linked-issue-present, not machine-origin).
- [ADR-0019 — team self-modification](0019-team-self-modification.md) — the firewall, preserved; compositional self-changes still hold for human merge.
- [ADR-0035 — auto-merge safe-additive IaC](0035-auto-merge-safe-additive-iac.md) — unchanged IaC gate.
- [ADR-0032 — additive self-change auto-lane](0032-additive-self-change-auto-lane.md) — unchanged self-change gate.
- #179 — revisit deploy/release; the test→prod promotion gate this ADR defers.
