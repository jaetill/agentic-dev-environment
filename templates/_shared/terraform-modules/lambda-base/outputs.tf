output "function_name" {
  value       = aws_lambda_function.this.function_name
  description = "Lambda function name"
}

output "function_arn" {
  value       = aws_lambda_function.this.arn
  description = "Lambda function ARN (unqualified — points to $LATEST)"
}

output "live_alias_arn" {
  value       = aws_lambda_alias.live.arn
  description = "ARN of the 'live' alias used for deploys"
}

output "live_alias_invoke_arn" {
  value       = aws_lambda_alias.live.invoke_arn
  description = "Invoke ARN for API Gateway integrations"
}

output "execution_role_arn" {
  value       = aws_iam_role.lambda_exec.arn
  description = "ARN of the Lambda execution role"
}

output "execution_role_name" {
  value       = aws_iam_role.lambda_exec.name
  description = "Name of the Lambda execution role"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.lambda.name
  description = "CloudWatch Log Group name"
}

output "log_group_arn" {
  value       = aws_cloudwatch_log_group.lambda.arn
  description = "CloudWatch Log Group ARN"
}

output "api_gateway_id" {
  value       = var.create_api_gateway ? aws_apigatewayv2_api.this[0].id : null
  description = "API Gateway HTTP API ID (null if not created)"
}

output "api_gateway_url" {
  value       = var.create_api_gateway ? aws_apigatewayv2_stage.default[0].invoke_url : null
  description = "Public URL of the API Gateway $default stage (null if not created)"
}

output "api_gateway_execution_arn" {
  value       = var.create_api_gateway ? aws_apigatewayv2_api.this[0].execution_arn : null
  description = "API Gateway execution ARN (for additional Lambda permissions)"
}
