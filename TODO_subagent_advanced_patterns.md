# TODO: Pull Anthropic's Claude Code Advanced Patterns webinar

**Captured:** 2026-05-19
**Trigger:** Held in reserve during the 2026-05-19 agent-definition audit.

## Source

[Claude Code Advanced Patterns webinar](https://www.anthropic.com/webinars/claude-code-advanced-patterns) — Anthropic publishes a PDF alongside the webinar covering advanced subagent and orchestration patterns.

## When to pull

- The agent-definition audit (see `docs/reviews/2026-05-19-agent-definition-audit.md`) recommends rework that touches orchestration (e.g., introducing a head/orchestrator agent, merging or splitting agents).
- We add a new agent to the `ai-team` plugin and want guidance on where it fits in the roster.
- We ever write a multi-agent coordination ADR.

## What to extract

Skim for:

- Recommended team compositions — which agents pair, cluster, or chain.
- Orchestration patterns (head agent vs. peer agents; when to use which).
- Anti-patterns at the agent-roster level (over-specialization, charter collision, redundant authority).
- Real-world frontmatter-field usage — particularly `skills`, `memory`, `background`, `isolation`, which our current 14 agents do not exercise.

## Output if useful

- New ADR (probably `0017-agent-orchestration.md` or similar) if patterns warrant codification.
- Updates to specific `plugins/ai-team/agents/*.md` definitions identified by the audit.
- Possibly a `prompt-engineering` skill at `plugins/ai-team/skills/prompt-engineering/SKILL.md` if the audit's inline rubric proves reusable.
