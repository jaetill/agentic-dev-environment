# Standard 12 — Team Self-Modification

> **Status:** Adopted via [ADR-0019](../adr/0019-team-self-modification.md).
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

## The competence gate

Before the team changes itself, it must decide whether it is *qualified* to make that specific change. Every self-change is classified:

### Mechanical

A permission fix, a typo, a missing tool grant, or applying a pattern the team has already decided and used elsewhere. The implementer makes the change directly, through the normal gated PR flow.

### Compositional / standards / security-touching

Anything that changes the agent roster, what a role does, a gate, a review, a standard, or the security posture. This is an **architecture decision, not a patch.** It must:

1. Go to the architect, not straight to the implementer.
2. Be grounded in authoritative best practice — see *Grounding* below. The team **researches** the relevant best practice before proposing; it does not improvise.
3. Be proposed as an ADR (and paired standard) with options and tradeoffs.
4. Be ratified by a human before implementation.

**When in doubt, escalate.** If an agent cannot confidently classify a change as mechanical — or cannot confidently say it has the knowledge to make a compositional change well — it treats the change as compositional and escalates. An unmade self-change is recoverable; an improvised one is the expensive mistake.

## Grounding — the best practices a self-change must respect

A compositional self-change is evaluated against established practice:

- **Team composition.** Each role has a single, clear responsibility; role overlap and ambiguous ownership are defects. The roster stays small and each agent's cognitive load bounded. (*Team Topologies*, Skelton & Pais.)
- **Standards.** A standard must be enforceable, minimal, and carry its rationale. It must not encode a preference the team cannot or will not enforce. (Google SRE; ThoughtWorks; the Microsoft Engineering Playbook; Martin Fowler — the authoritative sources named in the platform `CLAUDE.md` decision process.)
- **Security.** Least privilege; separation of duties; defense in depth; a human in the loop for privileged actions. The controlling principle: **the team must never be able to weaken its own controls unsupervised.** Any self-change that touches a gate, a credential, or a permission is security-touching by definition.

## Review and ratification

- Every self-modification PR runs the full `claude-pr-review` reusable, with `security-review` as a hard gate.
- A self-change reaches `main` only by a **human merge**. The team proposes; the human ratifies. The platform repo is never granted auto-merge.

## Why

A team that cannot improve its own process is half a team; a team that can rewrite its own gates and approve that itself has no safety floor. This standard keeps both true at once: the team may propose any change to itself, and a human always ratifies. Full rationale in [ADR-0019](../adr/0019-team-self-modification.md).
