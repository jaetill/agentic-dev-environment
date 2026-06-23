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

# Optional data-plane-read Deny overlay (#297).
#
# Pragmatic least-privilege hardening for drift-detection roles. Consumers that
# create a drift role with `additional_policy_arns =
# ["arn:aws:iam::aws:policy/ReadOnlyAccess"]` inherit ~41 data-exfil content
# reads (per Tempest SideChannel's analysis of ReadOnlyAccess). A drift role
# only ever runs `tofu plan -refresh-only`, which needs describe/list/get-config
# actions but NOT bulk object/record reads or credential issuance. This overlay
# keeps ReadOnlyAccess (so the plan still sees everything it must) and layers an
# explicit Deny on the exfil subset. An explicit Deny always wins over the
# ReadOnlyAccess Allow, so the role can still detect drift but can no longer be
# abused to read data-plane content.
#
# Inline (role-scoped) on purpose — a managed policy would need an
# account-unique name/ARN and would collide across repos sharing an account.
# Default OFF (count gated on var.deny_data_plane_reads) so existing consumers
# are unchanged until they opt in; see DENY-OVERLAY-297.md for per-repo rollout.
#
# IMPORTANT — DO NOT add these to the Deny list. `tofu plan -refresh-only` and
# common Terraform data sources legitimately need them; denying them breaks
# drift detection with AccessDenied:
#   - apigateway:GET                 (refresh reads API Gateway resources)
#   - lambda:GetFunction             (refresh reads Lambda function state)
#   - ec2:DescribeInstanceAttribute  (refresh reads EC2 attributes)
#   - ssm:GetParameter / ssm:GetParameters / ssm:GetParametersByPath / ssm:GetDocument
#       (possible aws_ssm_parameter / aws_ssm_document data sources)
# A future reader should NOT "complete" the list with these — that is the trap.
resource "aws_iam_role_policy" "deny_data_plane_reads" {
  count = var.deny_data_plane_reads ? 1 : 0

  name = "${var.project_name}-github-${var.env}-deny-data-plane-reads"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDataPlaneContentReads"
        Effect = "Deny"
        # Data-plane content reads / credential issuance — granted by
        # ReadOnlyAccess but not needed by a refresh-only drift plan.
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3-object-lambda:GetObject",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:GetRecords",
          "dax:Query",
          "dax:Scan",
          "cassandra:Select",
          "athena:GetQueryResults",
          "athena:GetQueryExecution",
          "athena:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "kendra:Query",
          "datapipeline:QueryObjects",
          "es:ESHttpGet",
          "config:SelectResourceConfig",
          "cloudtrail:LookupEvents",
          "logs:StartQuery",
          "chime:Retrieve*",
          "connect:GetFederationToken",
          "gamelift:GetInstanceAccess",
          "ec2:GetPasswordData",
          "ec2:GetConsoleOutput",
          "ec2:GetConsoleScreenshot",
          "ecr:GetAuthorizationToken",
          "codeartifact:GetAuthorizationToken",
          "cognito-identity:GetCredentialsForIdentity",
          "cognito-identity:GetOpenIdToken",
          "cognito-identity:GetOpenIdTokenForDeveloperIdentity",
          "cognito-idp:GetSigningCertificate",
          "sts:GetSessionToken"
        ]
        Resource = "*"
      }
    ]
  })
}
