# Native `terraform test` for lambda-base — plan-only, fast.
# Run: cd templates/_shared/terraform-modules/lambda-base && tofu test

variables {
  function_name           = "test-fn-dev"
  env                     = "dev"
  handler                 = "myproject.main.handler"
  runtime                 = "python3.12"
  deployment_package_path = "tests/fixtures/empty.zip"
}

mock_provider "aws" {}

run "creates_log_group_with_dev_retention" {
  command = plan
  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 7
    error_message = "dev env should have 7-day retention per ADR-0009 §1"
  }
  assert {
    condition     = aws_cloudwatch_log_group.lambda.name == "/aws/lambda/test-fn-dev"
    error_message = "Log group should follow /aws/lambda/<function_name> pattern"
  }
}

run "creates_log_group_with_prod_retention" {
  command = plan
  variables {
    env = "prod"
  }
  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 90
    error_message = "prod env should have 90-day retention per ADR-0009 §1"
  }
}

run "alias_named_live" {
  command = plan
  assert {
    condition     = aws_lambda_alias.live.name == "live"
    error_message = "Alias must be named 'live' for blue-green per ADR-0007 §5"
  }
}

run "xray_active_tracing_enabled" {
  command = plan
  assert {
    condition     = aws_lambda_function.this.tracing_config[0].mode == "Active"
    error_message = "X-Ray active tracing required per ADR-0009"
  }
}

run "insights_layer_attached" {
  command = plan
  assert {
    condition     = length(aws_lambda_function.this.layers) >= 1
    error_message = "Lambda Insights layer must be attached"
  }
  assert {
    condition     = strcontains(aws_lambda_function.this.layers[0], "LambdaInsightsExtension")
    error_message = "First layer should be the Lambda Insights extension"
  }
}

run "insights_arm64_layer_when_arm64_arch" {
  command = plan
  variables {
    insights_layer_arch = "arm64"
  }
  assert {
    condition     = strcontains(aws_lambda_function.this.layers[0], "LambdaInsightsExtension-Arm64")
    error_message = "arm64 arch should produce arm64 Insights layer ARN"
  }
}

run "api_gateway_optional_skipped_when_disabled" {
  command = plan
  variables {
    create_api_gateway = false
  }
  assert {
    condition     = length(aws_apigatewayv2_api.this) == 0
    error_message = "API Gateway should not be created when create_api_gateway = false"
  }
}

run "api_gateway_created_by_default" {
  command = plan
  assert {
    condition     = length(aws_apigatewayv2_api.this) == 1
    error_message = "API Gateway should be created by default"
  }
}

run "throttling_set_on_default_stage" {
  command = plan
  variables {
    throttle_rate_limit  = 500
    throttle_burst_limit = 1000
  }
  assert {
    condition     = aws_apigatewayv2_stage.default[0].default_route_settings[0].throttling_rate_limit == 500
    error_message = "Throttle rate limit should be applied to the default stage"
  }
}

run "rejects_invalid_env" {
  command = plan
  variables {
    env = "production"
  }
  expect_failures = [var.env]
}

run "secret_access_policy_when_secrets_provided" {
  command = plan
  variables {
    secret_arns = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:test-fn/dev/db-AbCdEf"]
  }
  assert {
    condition     = length(aws_iam_role_policy.secrets_access) == 1
    error_message = "Secrets policy should be created when secret_arns is non-empty"
  }
}

run "no_secret_access_policy_when_no_secrets" {
  command = plan
  assert {
    condition     = length(aws_iam_role_policy.secrets_access) == 0
    error_message = "Secrets policy should not be created when secret_arns is empty"
  }
}
