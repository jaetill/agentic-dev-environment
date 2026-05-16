# lambda-base — Lambda function + API Gateway HTTP API with sensible defaults.
# Per ADR-0007 (IaC) and ADR-0009 (Observability).
#
# Provides:
#   - Lambda function with versioning enabled
#   - Lambda alias `live` (alias-based blue-green deploys per ADR-0007)
#   - API Gateway HTTP API ($default stage, catch-all proxy integration)
#   - CloudWatch Log Group with env-appropriate retention
#   - Lambda Insights via the AWS layer + IAM permissions
#   - X-Ray active tracing
#   - Sensible IAM execution role with logs/X-Ray/Insights permissions

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Lambda Insights layer ARN by region. Default is x86_64 + a recent version;
  # override `insights_layer_version` and `insights_layer_arch` for arm64 or newer versions.
  # See: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versionsx86-64.html
  #      https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versionsarm64.html
  insights_layer_name = var.insights_layer_arch == "arm64" ? "LambdaInsightsExtension-Arm64" : "LambdaInsightsExtension"
  insights_layer_arn  = "arn:aws:lambda:${data.aws_region.current.name}:580247275435:layer:${local.insights_layer_name}:${var.insights_layer_version}"

  # Per-env log retention per ADR-0009 §1
  retention_by_env = {
    dev     = 7
    staging = 30
    prod    = 90
  }
  log_retention_days = lookup(local.retention_by_env, var.env, 7)
}

# ============================================================
# IAM execution role
# ============================================================

resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Logs + X-Ray + Lambda Insights baseline
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "insights" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}

# Project-supplied additional policies (e.g., Secrets Manager read for this env's secrets)
resource "aws_iam_role_policy_attachment" "additional" {
  count      = length(var.additional_policy_arns)
  role       = aws_iam_role.lambda_exec.name
  policy_arn = var.additional_policy_arns[count.index]
}

# Inline policy for the project's secrets manager access (per ADR-0006 — narrowly scoped)
resource "aws_iam_role_policy" "secrets_access" {
  count = length(var.secret_arns) > 0 ? 1 : 0
  name  = "${var.function_name}-secrets"
  role  = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = var.secret_arns
    }]
  })
}

# ============================================================
# CloudWatch Log Group (created upfront per ADR-0009 retention policy)
# ============================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = local.log_retention_days
  tags              = var.tags
}

# ============================================================
# Lambda function
# ============================================================

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = var.handler
  runtime       = var.runtime
  memory_size   = var.memory_size
  timeout       = var.timeout
  publish       = true # required for alias versioning

  filename         = var.deployment_package_path
  source_code_hash = filebase64sha256(var.deployment_package_path)

  layers = concat([local.insights_layer_arn], var.additional_layers)

  tracing_config {
    mode = "Active" # X-Ray active tracing per ADR-0009
  }

  environment {
    variables = merge(
      {
        DEPLOY_ENV       = var.env
        RELEASE_VERSION  = var.release_version
        AWS_LAMBDA_EXEC_WRAPPER = "/opt/otel-instrument" # if using OTEL layer; harmless otherwise
      },
      var.environment_variables
    )
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
  tags       = var.tags
}

# Alias-based blue-green deploys per ADR-0007 §5
resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Production traffic alias for ${var.function_name}"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

# ============================================================
# API Gateway HTTP API ($default stage, catch-all proxy integration)
# ============================================================

resource "aws_apigatewayv2_api" "this" {
  count         = var.create_api_gateway ? 1 : 0
  name          = var.function_name
  protocol_type = "HTTP"
  description   = "HTTP API for ${var.function_name}"
  tags          = var.tags

  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  count                  = var.create_api_gateway ? 1 : 0
  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.live.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  count     = var.create_api_gateway ? 1 : 0
  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda[0].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  count       = var.create_api_gateway ? 1 : 0
  api_id      = aws_apigatewayv2_api.this[0].id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttle_burst_limit
    throttling_rate_limit  = var.throttle_rate_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.lambda.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
    })
  }

  tags = var.tags
}

resource "aws_lambda_permission" "apigw" {
  count         = var.create_api_gateway ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_alias.live.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}
