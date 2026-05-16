# ai-team plugin

The Agentic Dev Environment platform packaged as a Claude Code plugin per ADR-0015.

## What ships

- **14 subagents** in `agents/` — architect, code-reviewer, dep-watcher, doc-keeper, drift-detector, e2e-tester, functional-tester, iac-implementer, implementer, incident-responder, release-captain, security-reviewer, test-writer, triage-bot
- **10 slash commands** in `commands/` — adr, brainstorm, digest, postmortem, release-notes, review, scaffold-project, security-review, test, triage. Plugin-namespaced as `/ai-team:<command>`.
- **10 lifecycle hooks** in `hooks/` configured via `hooks/hooks.json` — PreToolUse + PostToolUse + UserPromptSubmit + SessionStart + Stop. See `hooks/README.md`.
- **11 standards skills** in `skills/standards-*/` — source-control, ci-cd, testing, quality-gates, documentation, observability, secrets, iac, release-management, ai-workflows, user-feedback. Each wraps the corresponding `docs/standards/` doc.

## Install

From the workspace root (which is also the local marketplace):

```shell
/plugin marketplace add /absolute/path/to/Agentic-Dev-Environment
/plugin install ai-team@agentic-dev-environment
```

Or for project-scoped install that ships in version control:

```shell
claude plugin marketplace add /absolute/path/to/Agentic-Dev-Environment --scope project
```

Then add to the project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "agentic-dev-environment": {
      "source": {
        "source": "url",
        "url": "file:///absolute/path/to/Agentic-Dev-Environment"
      }
    }
  },
  "enabledPlugins": {
    "ai-team@agentic-dev-environment": true
  }
}
```

(Once the workspace itself is published to GitHub, swap the `url` source for a `github` source like `{"source": "github", "repo": "jaetill/agentic-dev-environment"}`.)

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
