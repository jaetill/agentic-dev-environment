# ADR-0035: Auto-merge safe-additive IaC behind a deterministic plan guard

- **Status:** Accepted
- **Date:** 2026-05-31
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, autonomy, ci-cd, aws, iac, security

> **Extends [ADR-0026](0026-agentic-implementer.md)** (the iac-implementer and its bounds), **[ADR-0021](0021-autonomous-merge.md)** (autonomous merge), and **[ADR-0023](0023-origin-based-autonomy-boundary.md)** (origin-based autonomy boundary). It is the IaC analog of **[ADR-0032](0032-additive-self-change-auto-lane.md)**: a deterministic guard opens a bounded auto-merge lane for a class the prior policy held for a human.

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR.

## Context and Problem Statement

The `iac-implementer` (ADR-0026) writes `tofu plan`-only PRs and never applies; the design's entire safety argument rests on a **human applying after merge**. Walking the loop's `scope:iac` node surfaced two facts that, together, make that argument false as built:

1. **The auto-merge gate (ADR-0021/0023) does not exclude `scope:iac`.** An IaC PR authored by `app/claude`, linked to a *machine-origin* issue (drift-detector / `origin:internal-review`), with a green check battery, satisfies every gate condition and **squash-merges autonomously**.
2. **Merge to `main` cascades to `tofu apply`.** The scaffolded `deploy.yml` triggers on `push: [main]` and runs `deploy-dev`, which executes `tofu apply -auto-approve`. So for a machine-origin IaC PR, auto-merge **is** auto-apply on the dev environment — there is no human in the loop, and the loop diagram never modeled an apply step at all.

So the question: **should machine-origin IaC changes be allowed to auto-merge — and therefore auto-apply on dev — and if so, under what mechanically-verifiable safety conditions?** The human-merge checkpoint the IaC design assumed is, in practice, a rubber stamp (the maintainer has stated he will not review IaC diffs and will merge them as-is). A checkpoint that is not actually exercised is not a safety control; the safety must move into a deterministic guard.

## Decision Drivers

- **Close the leak honestly.** Today a machine-origin IaC PR can auto-merge with *no* IaC-specific safety check — neither the unexercised human gate nor a deterministic one. That is the worst state: unguarded.
- **The guard must prove apply-safety, not merge-safety.** Because merge == apply on dev, "safe to merge" must mean "safe to apply": no destroys, no replacements, no public/blast-radius exposure, no leaked secrets.
- **Writer != approver.** The safety property cannot rest on the iac-implementer asserting its own change is safe. The verdict must come from an independent, deterministic check over machine-emitted plan output.
- **Conservative by default.** Over-holding routes to a human (safe). A missed unsafe plan is the dangerous failure, so every ambiguity, parse error, or missing plan holds.
- **Consistent autonomy trajectory.** This mirrors ADR-0032: a narrow, guarded auto-lane for the safe sub-class, everything else held.

## Considered Options

- **Option A — Exclude `scope:iac` from auto-merge entirely.** Every IaC PR holds for a human merge. Restores the checkpoint in form.
- **Option B — Auto-merge safe-additive IaC behind a deterministic plan guard.** A machine-origin IaC PR auto-merges only when an independent guard classifies its `tofu plan` as safe-additive (no destroy/replace, within the 5-resource cap, no exposure); everything else holds.
- **Option C — Auto-merge all machine-origin IaC (status quo by omission).** No IaC-specific guard.

## Decision Outcome

Chosen option: **Option B**, because the human checkpoint Option A restores is exactly the rubber stamp this decision exists to replace — reinstating it in form without function is theater, and it permanently parks routine additive infra work (log groups, alarms, retention bumps) on a human who will not look. Option C is the unguarded status quo. Option B moves the safety into a deterministic guard that actually runs.

**As built:**

- **The guard** — `scripts/iac-auto-merge-guard.sh` — classifies `tofu show -json <plan>` output. It returns `IN_LANE` (exit 0) only if **all** hold; otherwise `HOLD` (exit 1):
  1. **No destroys/replaces.** Every `resource_changes[].change.actions` is a subset of `{create, update, no-op, read}`. Any `delete` (standalone or as part of a replace) holds.
  2. **Within cap.** At most **5 substantive** resource changes (no-op/read excluded), matching the iac-implementer's own cap.
  3. **No exposure.** No planned `after` opens a hole: SG ingress `0.0.0.0/0` or `::/0`; S3 public ACL or a disabled public-access-block; IAM `Allow Action:* on Resource:*`; a plaintext value under a secret-ish key.
- **In-place `update` is permitted** (the "moderate" choice), not just pure-additive `create`. An update can flip a security rule, so predicate 3 (exposure) is the load-bearing check and is applied to the `after` of every create *and* update.
- **The guard runs as an independent PR check** (`iac-additive-guard`, the `iac-guard.yml` reusable workflow), in the credentialed context that already plans — never as the agent's self-assessment.
- **The central gate requires it.** `triage-scan.yml` auto-merge holds any `scope:iac` PR whose `iac-additive-guard` check is absent or not passing. Until a repo wires the guard workflow, its IaC PRs simply hold — i.e. the leak is closed immediately and conservatively, with no auto-merge regression.

## Consequences

### Positive

- The leak is closed: an unguarded machine-origin IaC auto-merge is no longer possible — the gate now requires an affirmative deterministic verdict, not merely "all present checks green."
- Routine additive infra (a log group, an alarm, a retention bump) flows end-to-end without parking on a human who would only rubber-stamp it.
- Safety is mechanical and auditable: the verdict is a script over machine-emitted plan JSON, reproducible and independent of the authoring agent.

### Negative

- **Plan != apply (TOCTOU).** The guard inspects a plan; the deploy job re-plans at apply time, so reality can drift between PR verdict and apply. For additive-only, <=5-resource changes the window is small; the belt-and-suspenders fix is to apply the *saved* plan artifact rather than re-planning. Tracked as a follow-up, not a blocker.
- **Plan-env vs apply-env.** The iac-implementer plans `terraform/envs/prod`; merge auto-applies `dev` first. The change *shape* (predicates 1-3) is env-independent when modules are shared, but a divergent dev module could behave differently. Noted; out of scope here.
- The exposure scan is a denylist (SG/S3/IAM/secret heuristics). A novel exposure vector it doesn't enumerate could pass. Mitigated by predicates 1-2 bounding blast radius and by the destructive-change-detector + `requires-adr:*` labels still gating the named-risk categories.

### Neutral

- App-repo propagation (a thin `iac-guard.yml` caller per repo, passing the repo's read-only AWS role) is ADR-0018 distribution work, handled as the ADR-0034-style follow-on. Until propagated, behavior is strictly safer than before (all scope:iac holds).
- Human-origin IaC PRs are unaffected — they already hold at the machine-origin check upstream of the guard.

## Pros and Cons of the Options

### Option A: exclude scope:iac from auto-merge

- ✅ Pro: Simplest; restores the checkpoint in form.
- ❌ Con: The checkpoint is an unexercised rubber stamp — form without function.
- ❌ Con: Permanently parks routine additive infra on a human who will not review it.

### Option B: deterministic safe-additive auto-lane (chosen)

- ✅ Pro: Moves safety into a check that actually runs, over machine-emitted plan output.
- ✅ Pro: Closes the unguarded leak immediately; conservative until propagated.
- ✅ Pro: Consistent with ADR-0032's guarded-auto-lane pattern.
- ❌ Con: Plan != apply window; denylist exposure scan is not exhaustive.

### Option C: auto-merge all machine-origin IaC

- ✅ Pro: Maximum throughput.
- ❌ Con: No apply-safety guard on an irreversible AWS mutation — unacceptable.

## Implementation notes

- Guard: `scripts/iac-auto-merge-guard.sh` (15-case fixture suite; create/update/no-op pass, every destroy/replace/over-cap/exposure case and missing-plan hold).
- Check workflow: `.github/workflows/iac-guard.yml` (reusable; checks out PR head, plans, runs the guard, sets the `iac-additive-guard` conclusion).
- Gate: `.github/workflows/triage-scan.yml` auto-merge job — `scope:iac` PRs require `iac-additive-guard` passing.
- Agent spec: `plugins/ai-team/agents/iac-implementer.md` — human-merge language amended for the additive auto-lane.
- Diagram: `docs/diagrams/autonomous-loop-flow.md` — IaC merge-gate branch, guard node, and the previously-missing apply step.
- Standards: `docs/standards/10-ai-workflows.md` — IaC auto-merge guard noted.

## Links

- [ADR-0026](0026-agentic-implementer.md) — the iac-implementer and its `tofu plan`-only, no-apply, <=5-resource bounds.
- [ADR-0021](0021-autonomous-merge.md) — autonomous merge of implementer PRs (the gate this extends).
- [ADR-0023](0023-origin-based-autonomy-boundary.md) — origin-based autonomy boundary (machine vs human origin).
- [ADR-0032](0032-additive-self-change-auto-lane.md) — the additive-self-change auto-lane this mirrors for IaC.
- [ADR-0017](0017-async-orchestration.md) — orchestration and routing context.
- HashiCorp, *Terraform: machine-readable plan output* — `https://developer.hashicorp.com/terraform/internals/json-format` — the `resource_changes[].change.actions` schema the guard parses.
