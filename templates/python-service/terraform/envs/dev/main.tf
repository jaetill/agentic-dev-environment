# Dev environment — Lambda + API Gateway for {{project_name}}
# Per platform ADR-0007 (IaC) — directory-per-env, S3+DynamoDB backend, OpenTofu.

module "iam_github_oidc" {
  source = "git::https://github.com/{{github_username}}/agentic-dev-environment.git//templates/_shared/terraform-modules/iam-github-oidc?ref=modules/v1.0.0"

  project_name   = var.project_name
  env            = "dev"
  github_repo    = "{{github_username}}/{{project_name}}"
  github_branch  = "main"
}

module "lambda_service" {
  source = "git::https://github.com/{{github_username}}/agentic-dev-environment.git//templates/_shared/terraform-modules/lambda-base?ref=modules/v1.0.0"

  project_name = var.project_name
  env          = "dev"
  function_name = "${var.project_name}-dev"
  handler       = "{{project_slug}}.main.app"
  runtime       = "python3.12"
  memory_size   = 512
  timeout       = 30

  environment_variables = {
    DEPLOY_ENV  = "dev"
    LOG_LEVEL   = "DEBUG"
    SENTRY_DSN  = data.aws_secretsmanager_secret_version.sentry_dsn.secret_string
    OTEL_EXPORTER_OTLP_ENDPOINT = data.aws_secretsmanager_secret_version.otel_endpoint.secret_string
  }
}

module "observability" {
  source = "git::https://github.com/{{github_username}}/agentic-dev-environment.git//templates/_shared/terraform-modules/observability-baseline?ref=modules/v1.0.0"

  project_name      = var.project_name
  env               = "dev"
  log_retention_days = 7   # per ADR-0009 §1
  lambda_function_name = module.lambda_service.function_name
}

# Secrets read at runtime
data "aws_secretsmanager_secret" "sentry_dsn" {
  name = "${var.project_name}/dev/sentry_dsn"
}
data "aws_secretsmanager_secret_version" "sentry_dsn" {
  secret_id = data.aws_secretsmanager_secret.sentry_dsn.id
}

data "aws_secretsmanager_secret" "otel_endpoint" {
  name = "${var.project_name}/dev/otel_endpoint"
}
data "aws_secretsmanager_secret_version" "otel_endpoint" {
  secret_id = data.aws_secretsmanager_secret.otel_endpoint.id
}
