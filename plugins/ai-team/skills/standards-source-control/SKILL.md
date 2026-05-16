---
name: standards-source-control
description: Use when the user asks how source control is operated — branching, branch naming, commit messages, signing, merge strategy, branch protection. Covers GitHub Flow + Conventional Commits + SSH signing + squash merge + strict branch protection on main.
---

# Standard 01 — Source control

GitHub Flow. Short-lived feature branches. Squash merge to main. SSH-signed commits. Strict branch protection (PR required, signed commits, linear history).

Branch naming: `<type>/<short-kebab-description>`. Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`.

Commit messages: Conventional Commits (`<type>(scope): subject`). Footer for `BREAKING CHANGE:`.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-source-control/standard.md`

## See also

- ADR-0002 (the reasoning behind these choices)
- [[standards-ci-cd]] — protected branches integrate with CI status checks
- [[standards-release-management]] — uses squash-merge commit titles
