# Standard 12 — Team Self-Modification

**ADR:** [ADR-0019](../adr/0019-team-self-modification.md)

> **Status:** Adopted via ADR-0019.
> **Scope:** the platform repo (`agentic-dev-environment`) and every agent that may discover or act on a flaw in `ai-team`.

## Principle

The platform repo is the team's *self* — the `ai-team` agents, roles, gates, workflows, standards, and templates. The team may modify itself here, through the gated PR flow. Projects never modify team code: a project may *propose* a change to the team, but may never *make* one.

## What counts as a process flaw

A **process flaw** is a defect in *how the team works*, not a defect in a project. The test is: **where does the fix live?**

- The fix is in a project's own application code or its own build/test CI → it is a project bug. Handle it in the project.
- The fix is in an `ai-team` agent definition, a reusable workflow, a platform standard, or a shared template → it is a process flaw. It cannot be fixed from a project repo and must be escalated.

## Reporting a flaw — the pull channel

An agent that classifies a problem as a process flaw while working in a project repo:

1. Labels *its own* project issue `process-flaw` — using the project's own token, no cross-repo write.
2. States, in the issue or a comment: the symptom, where in `ai-team` the fix likely lives, and what it was attempting.
3. Records the project work item as blocked-on-platform, and proceeds with whatever it can safely complete.

`triage-bot`, on its scheduled scan, pulls `process-flaw` markers across the project repos and files the corresponding issue on the platform repo. From there the platform loop (promoter → implementer) acts on it. This is the team's retro: it collects the field's process notes on its rounds.

## Detecting a flaw — the ci-health channel

The pull channel above depends on an agent or human *noticing* a process flaw and labelling it. Some flaws are never noticed that way — a reusable workflow that breaks fleet-wide, a scheduled job that silently stops. `ci-health.yml` (per [ADR-0020](../adr/0020-fleet-orchestration.md)) is the detection arm: it watches every fleet repo's non-PR workflow runs and, when it finds failures that surface nowhere else, files one consolidated issue on the platform repo labelled `triage:medium` — so the promoter routes it into the same loop.

Detection complements reporting; it does not replace the assessment below. A ci-health-detected breakage still goes through the competence gate and the generality assessment: a project's own build/test CI failing is a project bug; a platform-sourced workflow (`claude-*`, a reusable, `triage-scan`) failing is a process flaw.

## Generality assessment — a project-reported flaw is n = 1

A flaw reported through the pull channel was observed in **one project's** context. Before the team changes `ai-team` in response, it must abstract the report away from that project's stack and codebase and establish that the change serves the whole fleet. One project's experience is a single data point; changing the shared team on n = 1 is overfitting.

The architect performs this assessment and reaches one of three outcomes:

1. **General process flaw** — the team's workflow, a gate, or a role is genuinely wrong, and the fix benefits (or is neutral for) every project → change `ai-team`.
2. **Project-local issue** — the problem is an artifact of the reporting project's stack, codebase, or situation, not the team's process → it is **not** a team change; resolve it in that project's own knowledge/config layer. (Per the platform principle: every project runs the same team and the same rigor — only the *knowledge* differs.)
3. **General flaw, parochial proposed fix** — the flaw is real and general, but the fix as the reporting project framed it is shaped by that project's particulars → change `ai-team`, but with a *generalized* fix, not the project-specific one.

The team must actively reach one of these — it must never default to "a project said our process is broken, so change the process." When generality cannot be established, treat the report as project-local (outcome 2) and state what evidence would be needed to reclassify it.

## The competence gate

Before the team changes itself, it must decide whether it is *qualified* to make that specific change. Every self-change is classified:

### Mechanical

A permission fix, a typo, a missing tool grant, or applying a pattern the team has already decided and used elsewhere. The implementer makes the change directly, through the normal gated PR flow.

### Compositional / standards / security-touching

Anything that changes the agent roster, what a role does, a gate, a review, a standard, or the security posture. This is an **architecture decision, not a patch.** It must:

1. Be filed as a `needs-formulation` + `requires-adr` + `compositional-self-change` intake issue and enter **human formulation** ([ADR-0036](../adr/0036-human-intake-model.md)/[ADR-0038](../adr/0038-self-changes-route-through-formulation.md)) — not built, and not sent to a bespoke architect-stop. The agent that detects it files the issue and stops.
2. Be grounded in authoritative best practice — see *Grounding* below. The team **researches** the relevant best practice before proposing; it does not improvise.
3. Be proposed as an ADR (and paired standard) with options and tradeoffs — the architect drafts it during formulation.
4. Be ratified by a human before implementation — the human approves the formulated item (with its ratified ADR); only then does it build, and it still holds for human merge via the **capability-delta firewall** — the deterministic `additive-self-change-guard.sh`, authoritative over any advisory `compositional-self-change` label ([ADR-0019](../adr/0019-team-self-modification.md)/[ADR-0023](../adr/0023-origin-based-autonomy-boundary.md), preserved by [ADR-0039](../adr/0039-merge-is-autonomous-human-gate-moves-to-prod.md), sharpened by [ADR-0047](../adr/0047-firewall-gates-on-capability-delta.md)).

**When in doubt, escalate.** If an agent cannot confidently classify a change as mechanical — or cannot confidently say it has the knowledge to make a compositional change well — it treats the change as compositional and escalates. An unmade self-change is recoverable; an improvised one is the expensive mistake.

## Grounding — the best practices a self-change must respect

A compositional self-change is evaluated against established practice:

- **Team composition.** Each role has a single, clear responsibility; role overlap and ambiguous ownership are defects. The roster stays small and each agent's cognitive load bounded. (*Team Topologies*, Skelton & Pais.)
- **Standards.** A standard must be enforceable, minimal, and carry its rationale. It must not encode a preference the team cannot or will not enforce. (Google SRE; ThoughtWorks; the Microsoft Engineering Playbook; Martin Fowler — the authoritative sources named in the platform `CLAUDE.md` decision process.)
- **Security.** Least privilege; separation of duties; defense in depth; a human in the loop for privileged actions. The controlling principle: **the team must never be able to weaken its own controls unsupervised.** Any self-change that touches a gate, a credential, or a permission is security-touching by definition.

## Review and ratification

- Every self-modification PR runs the full `claude-pr-review` reusable, with `security-review` as a hard gate.
- **Routine and mechanical platform fixes** — and all **error-driven** (machine-origin) work on the platform repo — merge autonomously via the fleet auto-merge job, exactly like project work. Per [ADR-0021](../adr/0021-autonomous-merge.md) as amended by [ADR-0023](../adr/0023-origin-based-autonomy-boundary.md).
- **Compositional self-changes** — anything that *expands loop capability or weakens a control* (the team's gates, agent roster, standards, or security posture) — keep a human checkpoint at the **design stage**: the architect proposes (with research and tradeoffs), and a human ratifies the design *before* implementation begins (competence gate above). The auto-merge gate then holds the resulting PR via the deterministic capability-delta guard ([ADR-0047](../adr/0047-firewall-gates-on-capability-delta.md)), which decides the hold from the diff — a changed gate/governance file, guardrail vocabulary on an added/removed line, a net-new external action, or a destructive migration — rather than from an advisory label. The categorical floor — *the system cannot weaken its own safety unsupervised* — is preserved as this narrow, rare touchpoint.

## Why

A team that cannot improve its own process is half a team; a team that can rewrite its own gates and approve that itself has no safety floor. This standard keeps both true: the team may propose any change to itself, and a human ratifies the *design* of any change that touches the team's own gates/agents/standards/security. Routine maintenance flows autonomously like project work. Full rationale in [ADR-0019](../adr/0019-team-self-modification.md) (sub-decision 5 narrowed by [ADR-0023](../adr/0023-origin-based-autonomy-boundary.md)).
