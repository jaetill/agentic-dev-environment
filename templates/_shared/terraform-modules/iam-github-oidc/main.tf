# IAM role for GitHub Actions to assume via OIDC.
# Per ADR-0006 §4 — no long-lived AWS keys; CI gets short-lived tokens via OIDC.
#
# This module creates:
# - An IAM OpenID Connect identity provider (one per AWS account; module is idempotent)
# - An IAM role per (project, env) that GitHub Actions can assume
# - A policy attached to that role with the permissions CI needs

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Create the OIDC provider if it doesn't exist (one per account).
# Use `data` source to detect existence; this module assumes you've already
# created the provider via a one-time bootstrap (scripts/bootstrap-tfstate.sh
# also handles this).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM role per (project, env)
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Both sub forms: ref-form for plain branch jobs, environment-form
            # for jobs running in a protected GitHub Environment — gated prod
            # deploys (ADR-0043) present the environment form.
            "token.actions.githubusercontent.com:sub" = concat(
              ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"],
              [for e in var.github_environments : "repo:${var.github_repo}:environment:${e}"]
            )
          }
        }
      }
    ]
  })

  tags = {
    Project   = var.project_name
    Env       = var.env
    ManagedBy = "OpenTofu"
  }
}

# Attach policies — narrowly scoped per env per ADR-0006.
# Default policy: read Secrets Manager + read CloudWatch Logs + per-env Lambda update.
# Override via the `additional_policy_arns` variable for project-specific needs.

resource "aws_iam_role_policy" "default" {
  name = "${var.project_name}-github-${var.env}-default"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecretsForEnv"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project_name}/${var.env}/*"
      },
      {
        Sid    = "WriteCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project_name}-${var.env}*"
      },
      {
        Sid    = "DeployLambdaForEnv"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:GetAlias",
          "lambda:UpdateAlias",
          "lambda:PublishVersion"
        ]
        Resource = "arn:aws:lambda:*:*:function:${var.project_name}-${var.env}*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "additional" {
  count      = length(var.additional_policy_arns)
  role       = aws_iam_role.github_actions.name
  policy_arn = var.additional_policy_arns[count.index]
}
