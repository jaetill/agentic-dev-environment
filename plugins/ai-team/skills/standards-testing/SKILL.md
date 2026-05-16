---
name: standards-testing
description: Use when the user asks about test types, coverage targets, when to write tests, flake handling, or per-stack test shapes. Covers Per-stack test pyramid + tiered coverage (90/80/60) + immediate flake fix-or-remove.
---

# Standard 03 — Testing

Tiered coverage: 90% for critical (auth, payments, data integrity), 80% for typical, 60% for low-risk. Per-stack test shapes (Python/Node/web/Lambda). Flakes fixed or removed in same PR — never re-run-to-green.

Test pyramid: unit > integration > e2e. E2E only for happy-path user journeys.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-testing/standard.md`

## See also

- ADR-0004 (the reasoning)
- [[standards-quality-gates]] — coverage gates enforced in CI
- [[playwright-e2e]] — Playwright-specific patterns
