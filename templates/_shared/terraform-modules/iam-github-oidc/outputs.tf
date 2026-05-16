output "role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "ARN of the IAM role GitHub Actions should assume via OIDC"
}

output "role_name" {
  value       = aws_iam_role.github_actions.name
  description = "Name of the IAM role"
}
