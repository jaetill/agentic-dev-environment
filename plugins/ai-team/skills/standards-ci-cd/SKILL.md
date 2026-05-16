---
name: standards-ci-cd
description: Use when the user asks how CI/CD is operated — build matrix, deploy gates, who can ship, what triggers a deploy. Covers AI shipping authority + 5 ADR-gated change categories + GitHub Actions OIDC patterns.
---

# Standard 02 — CI/CD

GitHub Actions. AI agents have shipping authority within scoped change categories (per ADR-0003). All deploys go through OIDC roles — no static IAM keys. One OIDC role per app, scoped to specific repo+branch.

5 change categories the AI may ship without human approval, each gated by specific checks. Everything else requires human-in-loop review.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-ci-cd/standard.md`

## See also

- ADR-0003 (the reasoning)
- [[standards-source-control]] — protected branches require these status checks
- [[standards-secrets]] — OIDC role conventions
