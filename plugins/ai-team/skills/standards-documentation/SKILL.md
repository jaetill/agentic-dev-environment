---
name: standards-documentation
description: Use when the user asks how docs are written and organized — ADRs, runbooks, MkDocs, READMEs. Covers MADR 4.x ADRs + tight 6-section runbooks + MkDocs Material site.
---

# Standard 05 — Documentation

ADRs: MADR 4.x format in `docs/adr/`. Numbered, immutable once Decided, superseded rather than rewritten.

Runbooks: tight 6-section template (When this fires / Symptoms / Diagnose / Mitigate / Resolve / Postmortem links).

Site: MkDocs Material, served from `docs/`. Auto-deployed on merge.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-documentation/standard.md`

## See also

- ADR-0008 (the reasoning)
- [[standards-ai-workflows]] — `/adr` slash command drafts ADRs from this template
