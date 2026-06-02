# ADR-0023: Origin-based autonomy boundary — gate human-submitted work, autonomously ship machine-detected work

- **Status:** Accepted — approved by Jason 2026-05-25
- **Date:** 2026-05-25
- **Deciders:** Jason Tilley (with AI architectural synthesis)
- **Tags:** ai-workflows, orchestration, governance, autonomy

> **Amended by [ADR-0030](0030-all-dispatch-through-promoter.md):** dispatch routing changed — all implementer dispatch now goes through the promoter (no direct bypass). See the *Impacted ADRs* table in ADR-0030 for the specific change to this ADR.

> **Amended by [ADR-0032](0032-additive-self-change-auto-lane.md):** the compositional-self-change human checkpoint gains a deterministically-gated exception — additive agent output-contract tightenings auto-merge via the `additive-self-change-guard` inside the auto-merge gate; out-of-lane agent edits are still held for human ratification.

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. It re-decides the *axis* of the autonomy boundary and, in doing so, amends ADR-0017, ADR-0019, and ADR-0021; the amendments are enumerated in Implementation notes.

## Context and Problem Statement

The autonomous loop decides what needs a human checkpoint by the **type** of work. ADR-0017 plan-gates features; ADR-0021 auto-merges `defect`/`bug` fixes; ADR-0019 routes every platform-repo change through a human merge. The type axis produces a backwards result in practice: a bug report filed by an outside person flows all the way to a merged commit with no human ever involved, while the human's actual concern — *is an outside party's request something I want in my product?* — has no checkpoint at all.

The human's scarce resource is product judgment, not merge clicks. **What is the right axis for deciding which autonomous work needs a human, and which should run end to end — discovered, fixed, tested, committed — with no human in the loop?**

## Decision Drivers

- The human's checkpoint belongs where their judgment is irreplaceable: an outside party asking to change the product, and the design of a change to the team itself.
- Machine-detected defects (Sentry, CloudWatch, agent code-review) are objective breakage. Fixing them is maintenance the system should simply do.
- Loop pathologies — a fix that is reverted and re-filed in a cycle — are an agent-competence failure. A human gate papers over churn without solving it; better agent logic solves it.
- The team must still not be able to weaken its own safety unsupervised. ADR-0019's floor is narrowed, not removed.
- Architectural decisions remain the human's — ADR-0003's `requires-adr` set is untouched.
- Don't over-build: reuse the existing issue labels, the existing loop, the existing workflows.

## Considered Options

- **Option A — gate by origin.** Human-submitted work is human-gated; machine-detected work is autonomous through commit.
- **Option B — gate by type (status quo).** Features gated, bugs/defects autonomous.
- **Option C — gate by severity / blast-radius.** Large or risky changes gated regardless of origin or type.

## Decision Outcome

Chosen: **Option A — gate by origin.** The autonomy boundary is the *origin* of the work, not its type.

**Machine-origin work runs fully autonomously — discovered, fixed, tested, committed, no human in the loop.** This covers Sentry errors, CloudWatch alerts, and agent-discovered findings (`origin:internal-review`). The quality bar is the CI + AI-review battery — `code-review`, `security-review`, functional and e2e tests. Those required checks stay: they are the system policing itself, and `security-review` remains a hard BLOCK gate. The autonomy is *"routine machine-detected work ships itself"* — it is **not** *"skip the checks."*

**Human-origin work is gated by the human.** Any item a person submits — a feature request, a bug report, or a GitHub issue — is the human's to approve, because it represents an outside party asking to change the product. Human-filed **features** keep the ADR-0017 plan-gate: the human approves the approach before code is written. Human-filed **bugs and issues** do not auto-merge — the human merges, seeing and approving the result. No human-origin work auto-merges under any path.

**Platform self-modification: the safety floor is narrowed, not removed.** ADR-0019 routed *every* platform-repo change through a human merge. Under this ADR, routine and mechanical platform fixes — and all error-driven work on the platform repo — merge autonomously, exactly like project work. The human still approves the **design of a compositional self-change**: a change to the team's own gates, agent roster, standards, or security posture (ADR-0019 sub-decision 3, the competence gate, is retained). The categorical floor — *the system cannot weaken its own safety unsupervised* — is preserved as a narrow, rare touchpoint at the decision stage. ADR-0019 sub-decision 5, the blanket human-merge of every platform PR, is retired.

**Architectural decisions remain the human's, regardless of origin.** ADR-0003's `requires-adr:*` set — destructive migration, new dependency, security-relevant, API contract, schema — still routes to the human, even when the change is a machine-origin fix. Origin decides *routine* autonomy; an architectural decision is never routine.

**Loop pathologies are solved by agent logic, not gates.** A loop that files an issue, fixes it, watches the fix get reverted, and re-files is an agent-competence failure. The implementer, triage-bot, and reviewer agents gain oscillation detection (Implementation notes). The platform does **not** add a human checkpoint to compensate for a churning agent.

The governing principle: **the human's checkpoint sits where their judgment is irreplaceable — an outside party's request to change the product, and the design of a change to the team itself. Everything a machine can detect as objective breakage, the system fixes and ships on its own.**

## Consequences

### Positive

- The human's attention lands only on product direction and team design — the two genuinely irreplaceable calls.
- Machine-detected breakage — the bulk of loop volume — closes end to end with zero human latency.
- A human-filed bug no longer slips to production unreviewed. The backwards asymmetry the type axis created is gone.
- The control model is one axis, decidable from one signal — the issue author and `source:` label — not a type × severity matrix.

### Negative

- A machine-origin change merging unseen is now the explicit norm, not the exception. ADR-0021 already accepted this for `defect`/`bug`; this ADR widens it to all machine-origin work and to routine platform fixes. Bounded by: the review battery, the implementer scope cap (per [ADR-0026](0026-agentic-implementer.md)), `requires-adr` routing, every change being a revertable PR, and `AUTONOMOUS_MERGE=off` as a one-flip stop.
- Loop-churn safety now rests on agent logic that must actually work. If oscillation detection is weak, churn runs unchecked — there is no gate behind it by design. Accepted, and the reason oscillation detection is a hard requirement of this ADR, not a nice-to-have.
- A human-filed bug is now slower — it waits for a human merge — than it was under the type axis. Accepted: that wait *is* the control the human asked for.

### Neutral

- CloudWatch has no issue-filing path today; this ADR makes wiring one in-scope.
- `requires-adr` and the feature plan-gate are unchanged in substance; this ADR re-homes them under the origin axis.
- The change is observable as a relabeling of existing flows more than new infrastructure — the loop, labels, and workflows already exist.

## Pros and Cons of the Options

### Option A — gate by origin (chosen)

- ✅ Puts the human checkpoint where product judgment is irreplaceable and nowhere else.
- ✅ One axis, one signal (author + `source:` label) — simple to implement and to reason about.
- ✅ Closes the type-axis asymmetry where human bug reports shipped unseen.
- ❌ Loop-churn defense moves entirely onto agent logic — no gate as backstop.

### Option B — gate by type (status quo)

- ✅ Already wired; zero migration.
- ❌ Answers the wrong question: a human's product-relevant request (a bug report) ships with no human, while routine machine work waited on type rules.
- ❌ "Feature vs bug" is itself a fuzzy classification the loop must make.

### Option C — gate by severity / blast-radius

- ✅ Intuitively targets "risky" changes.
- ❌ Conflates *risk* with *who should decide*; a tiny human feature request and a tiny machine fix look identical to a severity gate.
- ❌ The scope cap + `requires-adr` already bound blast radius; severity-gating adds a second, redundant axis.

## Implementation notes

This ADR is itself a compositional self-change — it rewrites the team's gates — so per the floor it establishes it is human-ratified (Jason merges its PR) **before** any of the following is implemented.

- **ADR-0021** — auto-merge gate condition 1 changes from "closes a `defect`/`bug` issue" to "machine-origin": the linked issue carries `source:sentry`, `source:cloudwatch`, or `origin:internal-review` and is not human-authored. Condition 4 (platform repo excluded) is replaced by the narrowed self-modification rule — routine platform fixes qualify; compositional self-changes do not.
- **ADR-0017** — sub-decisions 3 (routing) and 4 (feature handling) re-expressed on the origin axis. The feature plan-gate is retained, explicitly for human-origin features. Human-origin bugs/issues gain a human-merge checkpoint (they previously skipped straight through).
- **ADR-0019** — sub-decision 5 (blanket human merge of every platform PR) retired. Sub-decision 3 (competence gate — human ratifies the design of compositional self-changes) retained as the narrowed floor.
- **ADR-0016** — gains a finding-lifecycle rule for oscillation/loop detection (a fourth rule alongside calibration, deferral, and Sentry-priority).
- **Agent definitions** (`implementer.md`, `triage-bot.md`, `code-reviewer.md`, `security-reviewer.md`) — origin-awareness in routing; oscillation detection: before acting on a finding, check git/issue history for a prior fix-and-revert of the same finding; on a detected cycle, halt and escalate rather than re-fix.
- **Workflows** — `claude-implementer.yml` and `triage-scan.yml`: the routing and auto-merge gate queries move to the issue author + `source:` signal.
- **CloudWatch → autonomous path** — CloudWatch alarms file `source:cloudwatch` issues that receive the same autonomous pickup as `source:sentry`. Natural home: the Grafana ops cockpit (ADR-0022) or an SNS → repository-dispatch Lambda. New wiring.
- **Branch protection** — `required_conversation_resolution` OFF fleet-wide (it silently blocks autonomous merge). `enforce_admins` and `required_signatures` are **retained as independent security controls**: `enforce_admins: true` forces even admin tokens (including the fleet app token) through the PR + AI-review battery; `required_signatures` provides cryptographic provenance that detects any direct-push bypass. Removing both simultaneously would let a workflow bug, prompt-injection exploit, or compromised fleet app private key push unsigned commits to `main` with no audit trail — a compounding gap. Only `required_conversation_resolution` (the autonomous-merge blocker) is turned off. Standard 01 §6 and `scripts/configure-branch-protection.ps1` updated; ADR-0002's "Strict" branch-protection sub-decision is amended to match.
- **Standards** — Standard 10 (AI workflows) gains the origin-based routing; Standard 01 §6 corrected.

## Links

- [ADR-0003 — CI/CD & approval model](0003-ci-cd.md) — AI shipping authority and the `requires-adr` set, both retained.
- [ADR-0016 — finding lifecycle](0016-finding-lifecycle-calibration-deferral.md) — amended: gains oscillation detection.
- [ADR-0017 — async orchestration](0017-async-orchestration.md) — amended: routing/feature-handling re-expressed on the origin axis.
- [ADR-0019 — team self-modification](0019-team-self-modification.md) — amended: blanket human-merge retired; competence gate retained as the narrowed floor.
- [ADR-0021 — autonomous merge](0021-autonomous-merge.md) — amended: auto-merge gate keyed to machine-origin.
- [ADR-0022 — ops cockpit](0022-ops-cockpit-dashboard-host.md) — candidate home for the CloudWatch issue-filing path.
- Mission command / *commander's intent* — the human owns intent; the team executes within it.
