# Runbook: Terraform/OpenTofu state recovery

## When to use this

Terraform/OpenTofu state is lost, corrupted, or out of sync with reality. Symptoms: `tofu plan` says it'll recreate everything; or `tofu apply` fails with "resource already exists."

## Prerequisites

- AWS CLI authenticated to the affected account
- Access to the S3 bucket that holds state (`<account-prefix>-tfstate-<account-id>`)
- The DynamoDB lock table

## Steps

1. **Take a backup.** Don't make changes without one.
   ```bash
   aws s3 cp s3://<bucket>/<project>/<env>/terraform.tfstate \
     ./recovery/$(date +%Y%m%d-%H%M)-terraform.tfstate
   ```

2. **Check state versioning.** S3 versioning is enabled per ADR-0007. List versions:
   ```bash
   aws s3api list-object-versions \
     --bucket <bucket> \
     --prefix <project>/<env>/terraform.tfstate
   ```
   Identify the last known good version (date before the corruption).

3. **Restore that version:**
   ```bash
   aws s3api copy-object \
     --bucket <bucket> \
     --key <project>/<env>/terraform.tfstate \
     --copy-source <bucket>/<project>/<env>/terraform.tfstate?versionId=<last-good-version-id>
   ```

4. **Run `tofu plan`** to compare restored state to actual cloud state:
   ```bash
   cd terraform/envs/<env>
   tofu init
   tofu plan
   ```

5. **Resolve drift** that appears in the plan (this is the same drift-detection workflow but in recovery mode):
   - For resources that exist in cloud but not in restored state → import them: `tofu import <resource> <id>`.
   - For resources in state but not in cloud → likely deleted; remove from state with `tofu state rm`.
   - For attributes that differ → decide whether IaC or cloud is authoritative; update accordingly.

6. **Verify clean plan.** `tofu plan` should show 0 changes.

## Verification

- `tofu plan` shows 0 changes
- All expected resources exist
- Service health endpoints are green
- DynamoDB lock table shows no stale lock for this state file

## Rollback

If the restored state is itself corrupt: try an even earlier version. S3 versioning preserves the last 30 versions per the IaC standard.

## Escalation

If state can't be recovered from S3 versions, the option is to **rebuild state from scratch** via imports of every resource. This is painful but possible. Estimate ~30 min per ~10 resources. For solo: budget a day if you have ~50 resources.

This runbook is rarely triggered. If you find yourself running it frequently, the underlying issue (concurrent applies? interrupted deploys?) needs an ADR-level fix.
