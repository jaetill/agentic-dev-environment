---
name: standards-iac
description: Use when the user asks about infrastructure-as-code conventions — OpenTofu, Terraform, state backends, module structure, drift detection. Covers OpenTofu + S3+DynamoDB state + directory-per-env + drift detection.
---

# Standard 08 — Infrastructure as Code

OpenTofu (not Terraform; LGPL fork is the standard). Remote state in S3 with DynamoDB locking. Directory per environment: `terraform/envs/<env>/`. Shared modules under `templates/_shared/terraform-modules/`.

Drift detection runs weekly via scheduled GitHub Action — `tofu plan -refresh-only`. Non-zero exit triggers `drift-detector` agent for classification.

Never `tofu apply` outside CI. Never `terraform import` without an ADR.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-iac/standard.md`

## See also

- ADR-0007 (the reasoning)
- [[standards-secrets]] — IAM grants for Secrets Manager
- [[aws-lambda-nodejs]] — Lambda-specific deployment patterns
