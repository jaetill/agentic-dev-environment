# Runbook: Secret leak

## When to use this

A secret has been exposed — committed to git, posted publicly, sent in plaintext, etc. Time matters: act fast.

## Prerequisites

- Access to wherever the secret is stored (AWS Secrets Manager, 1Password)
- Access to the systems that consume the secret
- Git history access for cleanup

## Steps

1. **Rotate the secret immediately.**
   - AWS Secrets Manager: `aws secretsmanager update-secret --secret-id <name> --secret-string '<new-value>'`
   - 1Password: change the value in the vault
   - Third-party APIs: rotate via the provider's dashboard

2. **Update consumers** to use the new value. For Lambda: update the env var in IaC, redeploy. For local dev: re-pull from the vault.

3. **Revoke the old credential** if the system supports it. AWS access keys: `aws iam delete-access-key`. GitHub PATs: revoke in settings. Etc.

4. **Audit the leak's blast radius.**
   - Where was the secret exposed (git, log, screenshot, message)?
   - Who could have seen it?
   - What systems/data did it grant access to?
   - Check audit logs for that period (CloudTrail, GitHub audit log, app logs).

5. **Clean up the exposure** if recoverable.
   - Git: `git filter-repo` or BFG Repo-Cleaner to remove the secret from history; force-push (note: this requires breaking ADR-0002's no-force-push rule and is the rare exception). Rotated already; this is cleanup.
   - Logs: redact / delete log lines containing the secret.
   - Screenshots / chat: delete; ask anyone who saw it to delete their copies.

6. **File a postmortem.** This is an architectural problem (the leak happened *somehow*); identify the systemic gap and fix it.

## Verification

- Old credential is non-functional (try it; expect auth failure)
- New credential works in all systems that consume it
- The exposure has been removed from accessible places
- A postmortem ADR has been filed proposing prevention

## Rollback

If rotation broke something downstream, you have two paths:

1. Re-issue the SAME credential value (only possible if the system allows you to set a specific value) and continue with cleanup.
2. Accept the breakage and fix it forward.

Path 1 is preferred only if you can verify the leak's blast radius is zero (no malicious access yet observed). Otherwise, path 2.

## Escalation

For solo: act on what you can; document the rest. If the leak involved customer data (PII), you may have legal/compliance reporting obligations depending on jurisdiction and data type. Consult appropriate counsel.

For Game Night specifically: if user accounts were exposed, the user-facing communication plan kicks in.
