---
name: standards-release-management
description: Use when the user asks how releases are cut, versioned, or rolled back — release-please, version bumps, CHANGELOG, emergency overrides. Covers release-please + auto-merge release PRs + emergency override.
---

# Standard 09 — Release management

release-please reads Conventional Commits and opens a release PR per branch (`main`). Release PR contains: version bump, CHANGELOG update, tag prep. Release PRs auto-merge when CI is green.

Emergency override: human can manually bump and push a release tag if release-please is broken, but must open a follow-up issue to fix the automation.

Semver: feat → minor, fix → patch, breaking → major.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-release-management/standard.md`

## See also

- ADR-0010 (the reasoning)
- [[standards-source-control]] — squash commits carry the conventional commit type
- [[standards-ci-cd]] — release PR is gated by the same checks as feature PRs
