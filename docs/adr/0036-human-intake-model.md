# ADR-0036: Human intake model — formulation → approved, GitHub as the backlog

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, governance, intake, product

> **Extends/amends** [ADR-0017](0017-async-orchestration.md) (the human's role in routing), [ADR-0020](0020-fleet-orchestration.md)/[ADR-0030](0030-all-dispatch-through-promoter.md) (promoter eligibility — now includes approved features), and [ADR-0033](0033-opted-in-features-build-without-plan-gate.md) (a feature's *entry* into the implementable pool moves from open-time to approval-time). Realises the human-owned-`what` half of the intake separation captured in the platform's intake-planning notes; the formulation *mechanism* itself stays a deliberate placeholder.

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR.

## Context and Problem Statement

The loop's execution side (promote → implement → review → merge) is modelled as a detailed process. The **human intake side was a single node** — `OPTIN: "trusted maintainer opts it in"` — silently standing in for everything the human actually does: noticing an idea, deciding it is worth doing, scoping it, and choosing when it enters WIP. The diagram was lopsided because the system was: execution detailed, intake a stub. Two real intake channels (an app-UI "feature request" button and external users; the maintainer's own ideas) had no represented path beyond "a maintainer applies a label."

The question: **what are the human-owned intake states, where do they live, and how does an accepted item cross into the autonomous loop?**

A prior look considered JIRA as the backlog and rejected it as overkill — the backlog lives in **GitHub**. The only firm requirement the maintainer set: *"easily separate issues that need to come to me from ones that are ready to enter WIP."*

## Decision Drivers

- **The human owns the `what`, the loop owns the `how` and the `when`.** Which features to accept, and their shape, is a human product decision; once accepted, execution (including dispatch timing) is autonomous.
- **One glanceable boundary.** "Needs me" vs "ready for WIP" must be a single, legible cut.
- **GitHub is the backlog.** No second system to sync (JIRA was rejected as overkill).
- **Minimal loop change.** Most of the model should be a relabel of the human side, not a rebuild of the loop.
- **Nothing is lost.** A rejected idea is saved and resurrectable, not deleted.

## Considered Options

- **Sub-decision A — intake states:** (1) binary needs-me/ready; (2) **formulation → verdict(parked|approved)**; (3) triage-then-groom as two pre-gates.
- **Sub-decision B — how an approved feature competes for dispatch:** (1) pull-only (human dispatches each); (2) spare-capacity pull; (3) priority-at-approval; (4) **fixed medium tier, dispatched autonomously**.

## Decision Outcome

**Backlog = GitHub Issues.** Intake is a short human-owned lane with **three labels** and one boundary:

- **`needs-formulation`** — the item is being **scoped and discerned** (the maintainer + Claude). This is the entire "needs me" surface. External/app-UI requests land here on capture (non-maintainers can file, not dispatch); the maintainer's own ideas enter here too. The formulation *mechanism* (a future grooming/sprint-planning ritual) is a **deliberate placeholder** — for now the maintainer shapes an item ad hoc and sets the verdict.
- **`parked`** — the verdict can be *no*: the issue is **closed + `parked`**, saved and **reopenable** when a later re-request or the maintainer's second thoughts revive it. Never deleted.
- **`approved`** — shaped and accepted. This is the boundary into the loop.

**An `approved` feature enters the promoter's consideration at the MEDIUM tier and is dispatched autonomously — no human in the dispatch loop.** Ranking: `critical` > `high` > **(`severity:medium` findings = `approved` features)** > `low`/nits. The maintainer's last act is approval; the promoter ranks and dispatches it like any medium-priority work. The maintainer **may** override by requesting **direct dispatch** (apply `ready-for-implementer` → the deterministic `event-dispatch` fast-path, throttled to the shared fleet ceiling), but that is an option, not the norm.

**A confirmed external *bug* rides its real `severity:*`, not `approved`** — `approved`/medium is specifically the feature tier. Formulation still applies to external bugs (someone must confirm a stranger's bug is real) but the output is a severity-tagged defect.

**Feature entry moves from open-time to approval-time (amends ADR-0033).** Opening a raw feature issue no longer auto-dispatches; it awaits formulation→approval. Owner-opened **bug/defect** still build by default (a maintainer-filed defect is already confirmed). So the event-dispatch and implementer `opened` triggers drop `feature-request`; a feature becomes implementable only via `approved` (promoter, medium) or a human `ready-for-implementer` fast-track.

**The only substantive loop change** is teaching the promoter (triage-scan Pass 2) to admit `approved` features into the consideration set at medium. Everything else is the intake lane on the diagram + the three labels + dropping `feature-request` from two `opened` triggers.

## Consequences

### Positive

- "Needs me" vs "ready" is one glance: anything open lacking `approved`/`ready-for-implementer` and carrying `needs-formulation` is the maintainer's; everything past `approved` is the loop's.
- The human owns the product decision (what/whether) without gating execution timing — approve once, walk away.
- No second system; no sync; rejected ideas are recoverable.
- The lopsided diagram is fixed — the intake lane replaces the overloaded `OPTIN`/`INERT` corner.

### Negative

- Approved features compete at medium, so a heavy `severity:high`+ defect stream can delay a feature — by design; the maintainer fast-tracks with direct dispatch when it matters.
- The formulation mechanism is unspecified (placeholder). Until it exists, "approved" is a manual label the maintainer applies after shaping an item ad hoc.
- External-request *volume* management (triage of many app-UI requests) is not yet designed — they simply queue as `needs-formulation`.

### Neutral

- `approved` is the human analog of an agent finding's promotability; the promoter now ranks a mixed pool (agent findings + approved features) by one tier order.
- Direct dispatch is unchanged machinery (the existing human `ready-for-implementer` → event-dispatch path), now framed as the intake override.

## Pros and Cons of the Options

### Sub-decision A — intake states

| Option | Pros | Cons |
|---|---|---|
| Binary needs-me/ready | Fewest labels | Loses *why* an item needs you (decide vs scope) |
| **Formulation → verdict (chosen)** | Matches Wonder→Discernment: shape, then judge; one "needs me" surface; reject is a saved verdict | One more state than binary |
| Triage-then-groom | Explicit accept gate | Two pre-gates; heavier; the accept decision is really the *output* of formulation, not a pre-step |

### Sub-decision B — approved-feature dispatch

| Option | Pros | Cons |
|---|---|---|
| Pull-only | Max human control of *when* | Every feature needs a manual push; "approved" becomes a shelf where features die |
| Spare-capacity pull | Drains when quiet | Features starve whenever defects flow |
| Priority-at-approval | Features can outrank defects | A chore per feature; features can starve real defects |
| **Fixed medium, autonomous (chosen)** | No human in dispatch loop; predictable; fast-track exists for urgency | A high-defect stream can delay a feature (accepted) |

## Implementation notes

- Labels: `needs-formulation`, `parked`, `approved` (intake); `ready-for-implementer` remains the dispatch/fast-track signal.
- Promoter: `.github/workflows/triage-scan.yml` Pass 2 — admit `approved` features, rank at medium.
- Feature entry: `.github/workflows/triage-scan.yml` (`event-dispatch`) and `.github/workflows/claude-implementer-reusable.yml` (`initial`, `initial-iac`) — drop `feature-request` from the owner-`opened` branches.
- Diagram: `docs/diagrams/autonomous-loop-flow.md` — the intake lane.
- The formulation/grooming ritual is intentionally **not** specified here (placeholder).
- **IaC caveat:** `scope:iac` bypasses the promoter (ADR-0030), so an `approved` IaC feature does **not** get the medium-tier auto-promotion — it dispatches via a human `ready-for-implementer` fast-track after formulation. Owner-`opened` IaC bug/defect still build by default; IaC `feature-request` was dropped from `initial-iac`'s opened branch for the same reason.
- **Plan-gate retired.** Moving the *what* to intake makes the in-loop plan-gate redundant, so it is removed: the `initial` job (its only remaining trigger was `plan-approved`), the PLAN PHASE prompt/spec sections, and the `plan-first` / `awaiting-plan-approval` / `plan-approved` labels are all gone. The implementer plans the *how* itself (plan-mode), ungated. **Impacted ADRs** (plan-gate references now historical): [ADR-0017](0017-async-orchestration.md) sub-decision 4, [ADR-0033](0033-opted-in-features-build-without-plan-gate.md) (superseded), and the passing references in [ADR-0021](0021-autonomous-merge.md) / [ADR-0023](0023-origin-based-autonomy-boundary.md) / [ADR-0026](0026-agentic-implementer.md) — the *substance* there (human-origin features are gated by the human) holds; the gate just moved from a mid-stream plan-approval to intake formulation + the existing human-merge checkpoint.

## Links

- [ADR-0017](0017-async-orchestration.md) — async orchestration and the human's routing role.
- [ADR-0020](0020-fleet-orchestration.md) / [ADR-0030](0030-all-dispatch-through-promoter.md) — the promoter and its consideration set (now includes approved features).
- [ADR-0033](0033-opted-in-features-build-without-plan-gate.md) — feature build defaults; this ADR moves a feature's *entry* to approval-time.
- [ADR-0028](0028-nit-sweep-only-on-active-cycles.md) — the spare-capacity pattern considered and rejected for feature dispatch.
