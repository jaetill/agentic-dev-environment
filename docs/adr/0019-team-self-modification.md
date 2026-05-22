# ADR-0019: Team self-modification — the platform repo as the team's self, and the project→platform feedback loop

- **Status:** Accepted — feedback credential widened and re-typed by [ADR-0020](0020-fleet-orchestration.md)
- **Date:** 2026-05-21
- **Deciders:** Jason Tilley (with AI architectural review)
- **Tags:** ai-workflows, orchestration, governance, security

> **Format:** MADR 4.x with the platform's three extensions. This is a **bundled-sub-decision** ADR — six coupled decisions about how the team modifies its own process and how flaws reach it from the field.

## Context and Problem Statement

[ADR-0017](0017-async-orchestration.md) defined how autonomous work is scheduled and routed *within* a repo. It did not address a structural fact: the platform repo (`agentic-dev-environment`) is not a project — it is the team's own definition. The agents, their roles, the gates, the workflows: that is `ai-team`, and it lives here. Every other repo is a *project* the team works on.

A real engineering team that hits a glitch in *how it works* fixes its own process — it adjusts gates, reviews, roles, workflow. The team must be able to do the same to `ai-team`. But nothing today supports it:

- The loop has no concept of "this is a flaw in the team, not in the project."
- An agent that hits a process flaw while working a project comments locally; the observation is lost (observed concretely on issue #24 — the implementer authored a correct fix, could not push it, and left only a comment).
- The loop cannot push `.github/workflows/` changes at all (issue #24 — `GITHUB_TOKEN` lacks the `workflows` permission).
- The platform repo does not run the `claude-pr-review` agent gate on its own PRs — so a change to the team currently gets *less* review than a routine project feature, despite propagating fleet-wide.

How should the team modify its own process — safely, competently, and with flaws discovered in the field actually reaching it?

## Decision Drivers

- **Self-improvement is a first-class capability**, not a risk to lock down. A team that cannot fix its own process is half a team.
- **One-directional boundary.** Projects must never be able to rewrite the team.
- **Self-changes are higher-stakes than project changes** — they propagate to every project — so they need *more* review, not less.
- **Competence.** A self-change must be grounded in best practice, not improvised. The team must recognise when a change is beyond its current knowledge.
- **Human ratification is the safety floor.** The team proposes; the human merges.
- **Don't over-build.** Reuse the existing loop and existing primitives (issues, labels, reusable workflows).

## Considered Options

A bundle of six sub-decisions:

1. **Boundary** — who may modify `ai-team`?
2. **Feedback channel** — how does a flaw discovered in a project reach the team?
3. **Competence gate** — how does the team decide it is qualified to make a given self-change?
4. **Review depth** — how heavily is a self-change reviewed?
5. **Ratification** — who approves a self-change?
6. **Credential model** — how is the boundary enforced mechanically?

## Decision Outcome

1. **Boundary → the platform repo is the team's self.** The loop may modify `ai-team` — agent definitions, reusable workflows, standards, templates — but only in the platform repo, through the normal gated PR flow. Projects never modify team code; a project's own application code and its own build/test CI are project work, but the caller stubs and anything sourced from the platform are not.

2. **Feedback channel → pull.** A project agent that classifies a problem as a team flaw labels *its own* project issue `process-flaw` (using the token it already has — no cross-repo write). `triage-bot`, on its scheduled scan, pulls those markers across the project repos and files the corresponding issue on the platform repo. The existing platform loop (promoter → implementer) acts on it. This is the team's retro: it collects the field's process notes on its rounds.

3. **Competence gate → classify the self-change.** *Mechanical* changes (a permission, a typo, a missing tool grant, applying an already-decided pattern) → the implementer does them directly. *Compositional / standards / security-touching* changes (the agent roster, what a role does, a gate, a standard, the security posture) are architecture decisions: the architect researches authoritative best practices for team composition, standards, and security, proposes with tradeoffs, and a human ratifies *before* implementation. When an agent is unsure it has the knowledge to make a self-change well, it must not improvise — it researches or escalates. A flaw reported through the feedback channel also gets a **generality assessment**: a single project's report is n = 1, so the architect must abstract it from that project's specifics and establish the fix serves the whole fleet — or route a project-local issue to that project's knowledge layer rather than mutating the shared team. [Standard 12](../standards/12-self-modification.md) is the operational procedure.

4. **Review depth → the platform repo reviews itself.** Every self-modification PR runs the full `claude-pr-review` reusable, including `security-review` as a hard gate. The platform repo gains its own caller stub for the reusable.

5. **Ratification → the human merges, always.** The team may *propose* any change to itself; a human *ratifies* by merging. The platform repo never gets auto-merge. This one asymmetry is the entire safety floor — a team that could rewrite its own gates and approve that itself has none.

6. **Credential model → two scoped tokens.** An *implementer PAT* (Contents + Workflows write, scoped to the platform repo only) lets the team modify itself — and *only there*. A *feedback read-token* (Issues:read across the project repos, held in the platform repo) lets `triage-bot` pull flaw markers. No project ever holds a token that can change the team. The one-directional boundary becomes a fact of which tokens exist where, not a rule an agent must remember.

The bundle is internally consistent: sub-decisions 1, 2, and 6 make self-modification *possible and bounded*; 3, 4, and 5 make it *safe and competent*. The governing principle: **the team proposes changes to itself; a human ratifies; and a self-change is treated as architecture/governance work, not a routine patch.**

## Consequences

### Positive

- The team genuinely improves its own process — gates, roles, workflow — instead of waiting for the human to notice and hand-fix.
- A flaw discovered in the field (a project) reaches the team as a tracked, actionable issue rather than a lost comment.
- The project→team boundary is enforced by credentials, not convention — a project *cannot* change the team even if an agent misjudges.
- Self-changes get the security-review gate they never had.

### Negative

- Latency: a process flaw waits for the next triage-scan window, not seconds. Accepted — process flaws are rarely emergencies, and a blocking one can be filed `severity:critical` to bypass the window.
- The competence gate routes compositional/standards/security flaws through a heavier path (architect + research + human) than a routine bug. Accepted — that is the point; an improvised change to the team is the expensive mistake.
- Classification (mechanical vs. compositional) is a judgment call agents will sometimes miss. Failure modes are bounded: a false escalation is a junk issue the human closes; a false "mechanical" produces a PR the security-review gate and the human merge are positioned to catch.
- A flaw reported from one project can be over-generalized into a fleet-wide change that does not fit the others. Mitigated by the generality assessment (Standard 12), which defaults an unproven flaw to project-local.

### Neutral

- Propagation back to projects is unchanged — it rides the existing reusable-workflow (ADR-0018) and plugin (ADR-0015) channels.
- The two PATs are a human action to create; the loop cannot self-provision credentials (correctly).

## Pros and Cons of the Options

### Sub-decision 2: Feedback channel

| Option | Pros | Cons |
|---|---|---|
| **Pull — triage-bot scans projects** (chosen) | One read-only token, centrally held; projects need no new credential; fits triage-bot's existing scan role | A flaw waits for the next triage window |
| Push — project agent files the platform issue directly | Immediate; simplest logic | A write-capable token in every project repo |
| Human relay | No new credential at all | Defeats the autonomy goal — the human becomes the relay |

### Sub-decision 3: Competence gate

| Option | Pros | Cons |
|---|---|---|
| **Classify mechanical vs. architecture** (chosen) | Human judgment + best-practice research land on the changes that need them; routine fixes stay fast | Classification is a judgment call agents can miss |
| Treat every self-change as routine | Fastest | The team improvises changes to its own composition and gates — the expensive mistake |
| Treat every self-change as architecture | Safest | Buries trivial fixes under research + ADR ceremony |

### Sub-decision 6: Credential model

| Option | Pros | Cons |
|---|---|---|
| **Two scoped tokens** (chosen) | The one-directional boundary is enforced by which tokens exist where, not by convention | Two credentials to create and rotate |
| One broad PAT / App-wide permission | Fewer credentials | A project could push code to the platform repo; the boundary reverts to convention only |

The remaining sub-decisions (1 boundary, 4 review depth, 5 ratification) had no seriously considered alternative — a team that cannot modify its own self, a self-change reviewed more lightly than a project feature, or self-changes with no human ratification each contradict a decision driver directly.

## Implementation notes

- Operational procedure: [Standard 12 — self-modification](../standards/12-self-modification.md). Written with this ADR.
- Wiring, which follows acceptance of this ADR (a compositional self-change must be human-ratified before implementation — sub-decision 3 applied to this ADR itself):
  - `process-flaw` label (platform repo + project repos).
  - `claude-implementer.yml` — the `initial` job checks out with the implementer PAT so it can push workflow-file changes; the implementer prompt gains the competence-gate classification.
  - `triage-scan.yml` / `triage-bot.md` — a pull-scan pass over the project repos for `process-flaw` markers, using the feedback read-token.
  - A platform-repo caller stub invoking `claude-pr-review.yml` on `pull_request`.
- Two PATs are created by the human (credentials are out of the loop's reach): the implementer PAT and the feedback read-token. Scopes specified alongside this ADR.
- Issue #24 is the canonical first instance: a flaw in the team (`doc-keeper` could not push), fixed on the team. Its mechanical fix (reviewer-mode conversion) shipped separately as it applies an already-decided pattern.

## Links

- [Standard 12 — self-modification](../standards/12-self-modification.md) — the operational procedure.
- [ADR-0017 — async orchestration](0017-async-orchestration.md) — scheduling/routing this ADR extends.
- [ADR-0011 — AI workflows](0011-ai-workflows.md) — the agent roster being modified.
- [ADR-0015 — platform as plugin](0015-platform-as-plugin.md) — the `ai-team` plugin and its propagation channel.
- [ADR-0018 — workflow distribution](0018-workflow-distribution.md) — reusable workflows; the `GITHUB_TOKEN` cascade rule.
- Issue #24 — the flaw that motivated this ADR.
