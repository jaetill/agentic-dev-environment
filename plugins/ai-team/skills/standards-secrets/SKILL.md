---
name: standards-secrets
description: Use when the user asks how secrets are stored, rotated, or referenced — API keys, tokens, DB credentials, AWS auth. Covers 1Password CLI + AWS Secrets Manager + AWS OIDC (no static keys).
---

# Standard 07 — Secrets

Tiers:

- **Local dev**: 1Password CLI (`op`) — `op run -- <command>` injects secrets from a vault into env vars for one invocation.
- **AWS runtime**: AWS Secrets Manager — Lambda/ECS pulls at runtime with cached client per ADR-0006.
- **CI/CD auth to AWS**: OIDC via `aws-actions/configure-aws-credentials@v4`. Never static IAM keys.

No secrets in `.env` (file is in protected-paths deny list). No secrets in CI workflow YAML. Github secrets only for tokens that can't be OIDC'd.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-secrets/standard.md`

## See also

- ADR-0006 (the reasoning)
- [[standards-ci-cd]] — OIDC role conventions
- [[standards-iac]] — Secrets Manager IAM grants live in Terraform
