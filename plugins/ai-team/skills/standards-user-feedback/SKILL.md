---
name: standards-user-feedback
description: Use when the user asks how user feedback / bug reports / feature requests are captured and triaged. Covers feedback ingestion + Linear-style triage + closing the loop.
---

# Standard 11 — User feedback

Ingestion channels documented per project (issues, email, in-app). Triage by `triage-bot` agent on a schedule. Categories: bug / feature request / question / spam. Severity (P0–P3) assigned for bugs.

Loop closure: every accepted feedback item gets an issue; every shipped item gets a notification back to the reporter where possible.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-user-feedback/standard.md`

## See also

- ADR-0012 (the reasoning)
- This plugin's `agents/triage-bot.md` — handles feedback triage
