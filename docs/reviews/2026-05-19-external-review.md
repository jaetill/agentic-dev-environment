# External review — 2026-05-19

Joint review of the Agentic Dev Environment platform by Jason's friend (engineer) and Gemini. Shared with Jason on 2026-05-19; persisted here for future-reference and so that PR work touching agents, hooks, or distribution can cite specific findings.

## What both reviewers agreed on

This is a genuine harness, not a showcase project. The test of any harness is whether it constrains behavior at runtime — not whether it looks good in a README. This one passes:

- The hooks are real enforcement code, not architecture diagrams. The `audit-bash` → `audit.log` loop means every agent action is observable.
- The standards docs are load-bearing agent instructions, not decorative documentation. An agent with no standard to reference hallucinates conventions; these agents don't have to.
- The plugin model ([ADR-0015](../adr/0015-platform-as-plugin.md)) is the right architectural call. Copy-paste distribution guarantees drift by project #3. A versioned plugin with a marketplace source eliminates that.

The "documentation as the OS for agents" framing is the key insight Gemini surfaced: without the 11 standards docs, 14 agents produce 14 inconsistent styles. The docs are what make the agents replaceable when a better model ships — the SDLC intelligence lives in the repo, not in the model's head.

## Where the two reviewers diverged slightly

Gemini flagged the 14-agent count as a complexity trap. The friend pushed back: these agents run on-demand, not concurrently. The real risk isn't cognitive overload from 14 personalities — it's whether the individual agent prompt definitions are actually well-written. They didn't fully evaluate that (would require reading every `agents/*.md`).

## Weaknesses both reviewers flagged

1. **Self-application gap** — the platform doesn't yet enforce on itself. Acknowledged in a detailed TODO, but "step 3 is always next" is a real risk.
2. **Absolute-path marketplace** — load-bearing single-machine state until the GitHub publication lands. Their highest-priority outstanding work item, correctly identified.
3. **Unvalidated agent quality** — good architecture around mediocre prompts still produces mediocre output. That's the part this review couldn't fully assess without deeper dives into each agent definition.

## Bottom line

> Adopt it, don't build simpler. The simpler version you'd build from scratch would be a subset of this without the enforcement teeth. The platform has clearly thought harder about the failure modes than most.

## What Jason and Claude did about it (2026-05-19)

In the same evening session this review was shared:

- **Self-application gap** — refreshed [`TODO_apply_platform_to_itself.md`](../../TODO_apply_platform_to_itself.md) to reflect that most self-application work has actually landed (workspace on GitHub, all 8 projects subscribe via `github` source, validate-platform / claude-pr-review / release-please workflows in place). What remains is small: cut first tagged release, verify a couple of CI triggers.
- **Absolute-path marketplace** — resolved earlier in the same evening. All 8 subscribing projects' `.claude/settings.json` use `{"source": "github", "repo": "jaetill/agentic-dev-environment"}`.
- **Unvalidated agent quality** — addressed by spawning a code-review-style audit of all 14 agent definitions, captured at [`docs/reviews/2026-05-19-agent-definition-audit.md`](2026-05-19-agent-definition-audit.md). Net outcome: 0 Critical, 2 Medium, 6 Low, 4 Nit — near-clean. Mediums + 4 quick-win Lows landed in PR #13.
- **Hook executable-bit bug (separate report from the friend's Claude session, same evening)** — fixed in [PR #11](https://github.com/jaetill/agentic-dev-environment/pull/11): all 16 `.sh` files in the repo flipped from `100644` to `100755`. The bug was specifically the kind of failure that self-application alone wouldn't catch — needed an external user on a non-Windows host to surface it.

## When to consult this review

- When making structural changes to the agent roster (split/merge/add/remove agents).
- When considering removing or weakening hook enforcement.
- When the question "do we still need the 11 standards docs?" comes up.
- When deciding whether to publish the workspace publicly — the "adopt it, don't build simpler" framing is the strongest endorsement on file.
