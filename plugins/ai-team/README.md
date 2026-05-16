# ai-team plugin

The Agentic Dev Environment platform packaged as a Claude Code plugin per ADR-0015.

## What ships

- **14 subagents** in `agents/` — architect, code-reviewer, dep-watcher, doc-keeper, drift-detector, e2e-tester, functional-tester, iac-implementer, implementer, incident-responder, release-captain, security-reviewer, test-writer, triage-bot
- **10 slash commands** in `commands/` — adr, brainstorm, digest, postmortem, release-notes, review, scaffold-project, security-review, test, triage. Plugin-namespaced as `/ai-team:<command>`.
- **10 lifecycle hooks** in `hooks/` configured via `hooks/hooks.json` — PreToolUse + PostToolUse + UserPromptSubmit + SessionStart + Stop. See `hooks/README.md`.
- **11 standards skills** in `skills/standards-*/` — source-control, ci-cd, testing, quality-gates, documentation, observability, secrets, iac, release-management, ai-workflows, user-feedback. Each wraps the corresponding `docs/standards/` doc.

## Install

Add this to the consuming project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "agentic-dev-environment": {
      "source": {
        "source": "github",
        "repo": "jaetill/agentic-dev-environment"
      }
    }
  },
  "enabledPlugins": {
    "ai-team@agentic-dev-environment": true
  }
}
```

The workspace repo is public — anyone can subscribe; no GitHub authentication required to resolve the plugin.

For development against an un-pushed local checkout, use the `directory` source instead:

```json
"source": { "source": "directory", "path": "/absolute/path/to/Agentic-Dev-Environment" }
```

## Permissions — important to understand

**The plugin does NOT and CANNOT control tool permissions.**

Anthropic's plugin manifest spec only supports `agent` and `subagentStatusLine` keys in `settings.json` — not the `permissions` block. That means:

- The plugin ships **what gets done**: agents, commands, hooks, skills.
- The plugin does NOT ship **what tools are allowed**: the `Read`, `Edit`, `Write`, `Glob`, `Bash` patterns governing what each agent (and your interactive session) can actually touch.

`permissions.allow` and `permissions.deny` are controlled by **you** — your user-level `~/.claude/settings.json` and the project's own `.claude/settings.json`. Effective permissions for any tool call are the combination of those two sources. The plugin sees them; it does not set them.

Installing this plugin therefore doesn't widen your security posture: the plugin's agents can only do what your own permission rules already allow.

### Recommended project-level deny block

Each subscribing project should include this block in its `.claude/settings.json` as a baseline (this is a starting point — adjust to your taste, but don't skip it):

```json
{
  "permissions": {
    "allow": [],
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(sudo rm*)",
      "Bash(git push --force*)",
      "Bash(git push -f*)",
      "Bash(*DROP TABLE*)",
      "Bash(*TRUNCATE*)",
      "Edit(*.tfstate*)",
      "Edit(.env)",
      "Write(*.tfstate*)",
      "Write(.env)"
    ]
  }
}
```

## See also

- [ADR-0015 — platform as plugin](../../docs/adr/0015-platform-as-plugin.md)
- [Standards index](../../docs/standards/index.md)
