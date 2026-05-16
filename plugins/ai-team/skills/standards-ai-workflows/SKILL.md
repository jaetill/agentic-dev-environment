---
name: standards-ai-workflows
description: Use when the user asks about AI agent roles, model tiers, subagent orchestration, hook policy, or slash commands. Covers Head agent + 12 specialist subagents + tiered models + Mixed-strictness hook policy.
---

# Standard 10 — AI workflows

Head agent (Sonnet) coordinates work; specialist subagents are invoked for narrow tasks. Tiered model assignment: Haiku for classification/triage, Sonnet for implementation/review, Opus reserved for hard architectural calls.

Mixed-strictness hook policy: PreToolUse hooks BLOCK destructive ops (rm -rf /, credential exposure, protected paths). PostToolUse hooks AUDIT and warn. UserPromptSubmit and SessionStart inject context.

Subagents catalog: architect, code-reviewer, dep-watcher, doc-keeper, drift-detector, e2e-tester, functional-tester, iac-implementer, implementer, incident-responder, release-captain, security-reviewer, test-writer, triage-bot.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-ai-workflows/standard.md`

## See also

- ADR-0011 (the reasoning)
- This plugin's `agents/` directory — the 14 subagents
- This plugin's `hooks/hooks.json` — the hook policy implementation
