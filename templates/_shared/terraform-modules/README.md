# Shared Terraform modules

Reusable OpenTofu/Terraform modules consumed by per-project IaC. Versioned via Git tags (`modules/v1.0.0`, etc.) — projects MUST pin to a specific tag, never source from `main` (per ADR-0007 §2).

## Modules

| Module | Purpose | Status |
|---|---|---|
| `iam-github-oidc/` | IAM role for GitHub Actions OIDC authentication (per ADR-0006) | Skeleton |
| `lambda-base/` | Lambda function + API Gateway with sensible defaults | Skeleton |
| `observability-baseline/` | CloudWatch log groups, X-Ray sampling, Container/Lambda Insights, Grafana data sources (per ADR-0009) | Skeleton |
| `vpc/` | VPC pattern with public/private subnets and NAT gateway | TODO |
| `ecs-service/` | ECS Fargate service with sensible defaults | TODO |
| `secrets-baseline/` | Per-env Secrets Manager + Parameter Store baseline | TODO |

## Versioning

Module versions are independent of the platform's overall version. Tag format: `modules/v<MAJOR>.<MINOR>.<PATCH>`. Breaking changes bump MAJOR; non-breaking enhancements bump MINOR; bug fixes bump PATCH.

When a new tag is created, downstream projects don't auto-upgrade — they pin a version. The `dep-watcher` agent surfaces module updates in dependency PRs.

## Consuming a module

```hcl
module "vpc" {
  source = "git::https://github.com/<you>/agentic-dev-environment.git//templates/_shared/terraform-modules/vpc?ref=modules/v1.0.0"

  cidr = "10.0.0.0/16"
  name = "${var.project}-${var.env}"
}
```

## Adding a new module

1. Create a directory `templates/_shared/terraform-modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `README.md`.
2. Test in isolation with Terratest (per ADR-0004 §8).
3. Tag a release: `git tag modules/v1.0.0`.
4. Document the module in this README.
