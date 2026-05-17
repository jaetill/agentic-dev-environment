# Native `terraform test` for iam-github-oidc — plan-only, fast (~5s).
# Per ADR-0004 §8 and Terratest 2026 best practice: static + plan-only tests
# in HCL; integration tests in Go (Terratest) under tests/integration/.
#
# Run: cd templates/_shared/terraform-modules/iam-github-oidc && tofu test

variables {
  project_name  = "test-project"
  env           = "dev"
  github_repo   = "example/test-project"
  github_branch = "main"
}

# Mock the OIDC provider data source so we don't need a real AWS account.
# Note: `url` is a required INPUT to the data source (the lookup key), not a
# computed attribute — OpenTofu rejects it in `defaults` ("Invalid mock/override
# field 'url'"). Only computed attributes (arn, client_id_list, thumbprint_list)
# can be mocked.
mock_provider "aws" {
  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      client_id_list  = ["sts.amazonaws.com"]
      thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
    }
  }

  # Also override aws_iam_role so the policy attachment can be planned without
  # generating random strings for the role id.
  mock_resource "aws_iam_role" {
    defaults = {
      arn       = "arn:aws:iam::123456789012:role/test-mock-role"
      unique_id = "AROAIEXAMPLEMOCKID12"
    }
  }
}

run "validates_required_inputs" {
  command = plan
  assert {
    condition     = aws_iam_role.github_actions.name == "test-project-github-dev"
    error_message = "Role name should follow the <project>-github-<env> pattern"
  }
}

run "trust_policy_scopes_to_branch" {
  command = plan
  assert {
    condition     = strcontains(aws_iam_role.github_actions.assume_role_policy, "repo:example/test-project:ref:refs/heads/main")
    error_message = "Trust policy must scope to the configured repo + branch"
  }
}

run "default_policy_grants_secrets_access_for_env_only" {
  command = plan
  assert {
    condition     = strcontains(aws_iam_role_policy.default.policy, "test-project/dev/*")
    error_message = "Default policy must scope Secrets Manager access to <project>/<env>/*"
  }
}

run "rejects_invalid_env" {
  command = plan
  variables {
    env = "production"   # not in [dev, staging, prod]
  }
  expect_failures = [var.env]
}

run "additional_policies_attach" {
  command = plan
  variables {
    additional_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess",
    ]
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.additional) == 1
    error_message = "additional_policy_arns should produce one attachment per element"
  }
}
