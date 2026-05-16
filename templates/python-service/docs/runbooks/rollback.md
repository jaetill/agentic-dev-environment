# Runbook: Manual rollback

## When to use this

The auto-rollback failed (per platform ADR-0003), and prod is in a degraded state. The `incident-responder` agent has paged you.

## Prerequisites

- AWS CLI authenticated to prod
- OpenTofu installed
- The previous known-healthy release tag (look at the `last-healthy` tag, or check the most recent prior release before the broken one)
- 1Password CLI (`op`) for secrets access

## Steps

1. **Identify the previous healthy version.**
   ```bash
   git tag --sort=-creatordate | head -5
   # The current bad version is at the top; the one before is your target.
   ```

2. **Checkout that tag:**
   ```bash
   git fetch --tags
   git checkout v<previous>
   ```

3. **Re-run the deploy** following the [`deploy.md`](deploy.md) procedure with the previous tag.

4. **For Lambda specifically (faster):** swap the alias.
   ```bash
   aws lambda update-alias \
     --function-name {{project_slug}}-prod \
     --name live \
     --function-version <previous-version-number>
   ```
   This is near-instant (sub-second) compared to a full Terraform apply.

5. **If the alias swap doesn't work** (rare; AWS API throttling): proceed with the full Terraform deploy from step 3.

## Verification

Same as deploy:

- HTTP 200 from `/health` and `/ready`
- No 5xx in CloudWatch for 5 min post-rollback
- Sentry release `v<previous>` is the active one

## Rollback (of the rollback)

If the rollback breaks something else, escalate. Don't try to "patch forward" during an incident.

## Escalation

If you can't get back to a healthy state within 30 minutes, declare a major incident, document the state, and consider DB rollback (if you have a recent backup). For solo work, the goal at this point is mitigation (taking the service offline if necessary) rather than fast recovery.
