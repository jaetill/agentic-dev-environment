# dev environment

Per platform [ADR-0007](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0007-iac.md) — directory-per-env, S3+DynamoDB backend, OpenTofu.

## Apply

```bash
op run --env-file=../../../.env.local.template -- tofu init
op run --env-file=../../../.env.local.template -- tofu plan
op run --env-file=../../../.env.local.template -- tofu apply
```

In CI, this runs via the platform's `terraform-deploy-dev.yml` reusable workflow with AWS OIDC.

## State

S3 key: `{{project_name}}/dev/terraform.tfstate` in `{{account_prefix}}-tfstate-{{aws_account_id}}`. Versioning + encryption enabled.

## Modules used

- `iam-github-oidc` — IAM role for GitHub Actions to assume via OIDC
- `lambda-base` — Lambda function + API Gateway with sensible defaults
- `observability-baseline` — log groups, X-Ray sampling, Container/Lambda Insights, Grafana data sources
