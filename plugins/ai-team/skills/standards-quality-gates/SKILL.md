---
name: standards-quality-gates
description: Use when the user asks about lint configs, type-check rules, formatting, security scanning, or pre-merge gates. Covers Pragmatic-strict linters + mypy strict / TS strict + full security stack.
---

# Standard 04 — Quality gates

Pragmatic-strict configuration: Ruff (Python), Prettier + ESLint (JS/TS), `tofu fmt` (Terraform). Type-checking strict (mypy strict, TS strict). Security stack: secret scanning, dependency audit, SAST.

Gates enforced in CI; pre-commit hooks mirror them locally. Auto-fix where possible, error otherwise.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-quality-gates/standard.md`

## See also

- ADR-0005 (the reasoning)
- [[standards-ci-cd]] — gate enforcement happens in CI
- [[standards-secrets]] — secret scanning is part of the gate stack
