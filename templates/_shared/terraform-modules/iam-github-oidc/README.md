# Module: iam-github-oidc

IAM role for GitHub Actions to assume via OIDC. Per platform [ADR-0006](../../../../docs/adr/0006-secrets.md) §4 — no long-lived AWS keys.

## Usage

```hcl
module "iam_github_oidc" {
  source = "git::https://github.com/<you>/agentic-dev-environment.git//templates/_shared/terraform-modules/iam-github-oidc?ref=modules/v1.0.0"

  project_name  = "game-night"
  env           = "dev"
  github_repo   = "<you>/game-night"
  github_branch = "main"

  # Optional — additional policy ARNs to attach
  additional_policy_arns = [
    "arn:aws:iam::123456789012:policy/MyCustomPolicy",
  ]
}

# Use the role in CI:
output "github_actions_role_arn" {
  value = module.iam_github_oidc.role_arn
}
```

In your CI workflow, configure AWS via OIDC:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ vars.GITHUB_ACTIONS_ROLE_ARN }}
      aws-region: us-east-1
```

## Default policy

The role grants:

- **Secrets Manager:** `GetSecretValue`, `DescribeSecret` for `<project>/<env>/*` only
- **CloudWatch Logs:** create log groups + put events for `/aws/lambda/<project>-<env>*`
- **Lambda:** update + invoke functions named `<project>-<env>*`

For broader permissions (e.g., DynamoDB, S3, RDS), attach additional policy ARNs via `additional_policy_arns`.

## Security notes

- **Branch scoping.** The trust policy restricts the role to assumption from a specific branch (default `main`). PR runs on feature branches will fail to assume the role unless the branch matches. This is intentional — feature-branch CI doesn't need cloud-deploy permissions.
- **Account isolation.** Each environment (dev/staging/prod) typically has its own AWS account; create one role per env per account.
- **Least privilege.** The default policy is narrow. Resist the urge to add `Action: "*"` for convenience; widen permissions explicitly via `additional_policy_arns` per use case.

## Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | string | (required) | Project name (used in role name + ARN scoping) |
| `env` | string | (required) | One of: dev, staging, prod |
| `github_repo` | string | (required) | `<org>/<repo>` |
| `github_branch` | string | `"main"` | Branch allowed to assume the role |
| `additional_policy_arns` | list(string) | `[]` | Extra policy ARNs to attach |

## Outputs

| Output | Description |
|---|---|
| `role_arn` | ARN of the IAM role |
| `role_name` | Name of the IAM role |
