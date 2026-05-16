# Runbook: Manual deploy

## When to use this

You should rarely need this. Per platform [ADR-0003](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0003-ci-cd.md), deploys are fully automated through release-please + the deploy workflow. Use this runbook only if:

- The auto-deploy workflow is broken and a deploy is genuinely time-critical
- You're testing the deploy flow itself
- Recovery from a half-completed deploy

## Prerequisites

- AWS CLI authenticated to the target environment (use `op run` to inject creds)
- OpenTofu installed (or Terraform)
- The release tag you want to deploy (e.g., `v1.4.2`)
- Read access to AWS Secrets Manager for the target env

## Steps

1. **Checkout the release tag locally:**
   ```bash
   git fetch --tags
   git checkout v1.4.2
   ```

2. **Build the Lambda package:**
   ```bash
   uv build
   # or: pip install --target=./build -e .
   cd build && zip -r ../lambda.zip . && cd ..
   ```

3. **Deploy via OpenTofu** to the target environment:
   ```bash
   cd terraform/envs/<env>
   tofu init
   tofu plan -var "lambda_zip_path=../../lambda.zip"
   tofu apply -var "lambda_zip_path=../../lambda.zip"
   ```
   Success looks like: `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.`

4. **Verify via the health endpoint:**
   ```bash
   curl https://<env-domain>/health
   ```
   Expected: `{"status": "ok"}`.

## Verification

- HTTP 200 from `/health` and `/ready`
- No 5xx errors in CloudWatch Logs for 5 minutes post-deploy
- Sentry shows no new releases-tagged errors

## Rollback

See [`rollback.md`](rollback.md). Manual rollback is the same procedure with the *previous* tag.

If the rollback itself fails: see [`iac-recover.md`](iac-recover.md) for state recovery.

## Escalation

For solo: that's you. If you're stuck >30 minutes, document the state, post in the project repo's incident issue, and notify yourself per platform observability standard.
