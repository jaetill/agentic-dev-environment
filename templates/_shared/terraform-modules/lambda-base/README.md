# Module: lambda-base

Lambda function + API Gateway HTTP API with sensible defaults — alias-based blue-green deploys per [ADR-0007](../../../../docs/adr/0007-iac.md) and observability per [ADR-0009](../../../../docs/adr/0009-observability.md).

## What it creates

- **Lambda function** with versioning enabled (`publish = true`)
- **Lambda alias `live`** (alias-based blue-green; instant rollback by re-pointing the alias per ADR-0007)
- **API Gateway HTTP API** with `$default` stage, catch-all proxy integration to the live alias (optional via `create_api_gateway`)
- **Throttling** on the stage (default 1000 req/s sustained, 2000 burst)
- **CORS** baseline
- **CloudWatch Log Group** with env-appropriate retention (7d/30d/90d per ADR-0009)
- **API Gateway access logging** to the same log group
- **IAM execution role** with logs + X-Ray + Lambda Insights baseline
- **Lambda Insights** via the AWS-published layer
- **X-Ray active tracing** enabled
- **Optional VPC config**
- **Optional Secrets Manager access** scoped to a list of secret ARNs

## Usage

```hcl
module "lambda" {
  source = "git::https://github.com/<you>/agentic-dev-environment.git//templates/_shared/terraform-modules/lambda-base?ref=modules/v1.0.0"

  function_name           = "${var.project_name}-${var.env}"
  env                     = var.env
  handler                 = "myproject.main.handler"
  runtime                 = "python3.12"
  memory_size             = 512
  timeout                 = 30
  deployment_package_path = "../../../dist/lambda.zip"

  release_version = var.release_version

  environment_variables = {
    LOG_LEVEL                  = var.env == "prod" ? "INFO" : "DEBUG"
    OTEL_EXPORTER_OTLP_ENDPOINT = data.aws_secretsmanager_secret_version.otel_endpoint.secret_string
  }

  secret_arns = [
    aws_secretsmanager_secret.app.arn,
    aws_secretsmanager_secret.db.arn,
  ]

  cors_allow_origins = var.env == "prod" ? ["https://app.example.com"] : ["*"]

  tags = {
    Project = var.project_name
    Env     = var.env
  }
}
```

## Inputs (key)

| Variable | Type | Default | Description |
|---|---|---|---|
| `function_name` | string | (required) | Lambda function name (typically `<project>-<env>`) |
| `env` | string | (required) | dev / staging / prod (drives log retention) |
| `handler` | string | (required) | e.g., `myproject.main.handler` |
| `runtime` | string | `python3.12` | Lambda runtime |
| `memory_size` | number | `512` | MB |
| `timeout` | number | `30` | seconds |
| `deployment_package_path` | string | (required) | Path to the .zip |
| `release_version` | string | `unknown` | App version (env var) |
| `environment_variables` | map(string) | `{}` | Non-secret env vars |
| `secret_arns` | list(string) | `[]` | Secrets Manager ARNs the function reads |
| `additional_policy_arns` | list(string) | `[]` | Extra managed policies |
| `additional_layers` | list(string) | `[]` | Extra Lambda layers |
| `vpc_config` | object | `null` | Optional VPC config |
| `create_api_gateway` | bool | `true` | Set false for event-driven Lambdas |
| `cors_allow_origins` | list(string) | `["*"]` | CORS origins (narrow for prod) |
| `throttle_rate_limit` | number | `1000` | req/s sustained |
| `throttle_burst_limit` | number | `2000` | burst |
| `tags` | map(string) | `{}` | Resource tags |

## Outputs (key)

| Output | Description |
|---|---|
| `function_name` | Lambda function name |
| `function_arn` | Function ARN |
| `live_alias_arn` | ARN of the `live` alias used for deploys |
| `api_gateway_url` | Public URL (null if `create_api_gateway = false`) |
| `log_group_name` | CloudWatch Log Group |
| `execution_role_arn` | Execution role ARN (for additional policy attachments) |

## Deploy flow

This module assumes the deployment package (`.zip`) is built before `tofu apply`:

```bash
# Build (in project root)
uv build && cd dist && zip -r lambda.zip * && cd ..

# Apply
cd terraform/envs/dev
tofu plan -var "lambda_zip_path=../../../dist/lambda.zip"
tofu apply ...
```

The `live` alias points at the new function version after each apply. Rollback:

```bash
aws lambda update-alias \
  --function-name <name> \
  --name live \
  --function-version <previous-version-number>
```

This is what `health-watch.yml` + `auto-rollback.yml` do automatically (per ADR-0003).

## Lambda Insights layer

The module attaches the Lambda Insights extension layer. Defaults: x86_64, version 53.

To bump the version (when AWS releases a newer one — check the [official AWS docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versions.html)):

```hcl
module "lambda" {
  # ...
  insights_layer_version = 75   # whatever the current version is
}
```

For arm64 Lambdas:

```hcl
module "lambda" {
  # ...
  insights_layer_arch    = "arm64"
  insights_layer_version = 35   # arm64 has its own version sequence
}
```

The `dep-watcher` agent surfaces version updates as a routine PR.

## Notes

- **Version pinning.** Always source this module from a tagged ref (`?ref=modules/v1.0.0`) per ADR-0007. Sourcing from `main` is forbidden.
- **OTEL.** If you use the AWS OTEL Lambda layer, set `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument` in `environment_variables`. This module's default sets that env var; if you don't use OTEL, it's harmless.
- **CORS.** `["*"]` is the default for ease; narrow it for production via `cors_allow_origins`.
- **Cold-start.** Default 512 MB / 30s timeout is sized for typical Python services. Adjust per project.
