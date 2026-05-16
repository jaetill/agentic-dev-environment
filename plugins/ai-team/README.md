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

The repo is private, so the consumer needs read access to `jaetill/agentic-dev-environment` (via their authenticated `gh` token).

For development against an un-pushed local checkout, use the `directory` source instead:

```json
"source": { "source": "directory", "path": "/absolute/path/to/Agentic-Dev-Environment" }
```

## Permissions

The plugin ships hooks but cannot ship `permissions.deny` rules (plugin `settings.json` only supports `agent` and `subagentStatusLine`). Each subscribing project should include this block in its `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [],
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(sudo rm*)",
      "Bash(git push --force*)",
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
