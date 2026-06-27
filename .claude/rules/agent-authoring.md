---
paths:
  - "plugins/ai-team/agents/**"
---

# AI-team agent authoring

- **New agent files copy an existing agent's frontmatter block** (`name`/`description`/`model`/`tools`/`primary_context`) — `agent-frontmatter-check` requires it.
- **Reviewer agents must verify any SHA, version, package name, file path, or identifier before naming it specifically** (the *Probe-before-pin* discipline in [`code-reviewer.md`](../../plugins/ai-team/agents/code-reviewer.md) and [`security-reviewer.md`](../../plugins/ai-team/agents/security-reviewer.md), added in PR #361). Otherwise name it as a class: "pin to the SHA of the latest v1 tag via `git ls-remote`" beats "pin to v1.12.1 (af26ac7d…)". PR #351 shipped a fabricated SHA from security-reviewer and broke every dispatch for 5 minutes.
