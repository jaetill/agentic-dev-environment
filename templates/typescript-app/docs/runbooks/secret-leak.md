# Runbook: Secret leak

## When to use this

A secret has been exposed — committed to git, posted publicly, sent in plaintext, etc. Time matters: act fast.

## Prerequisites

- Access to wherever the secret is stored (1Password, AWS Secrets Manager, Vercel env)
- Git history access for cleanup

## Steps

1. **Rotate the secret immediately.**
   - 1Password: change the value
   - Vercel env vars: update via Vercel dashboard → Settings → Environment Variables → Edit
   - Third-party APIs: rotate via the provider's dashboard

2. **Update consumers.** Vercel: trigger a redeploy after env var update. Local dev: `op` will pick up the new value on next `op run`.

3. **Revoke the old credential** if the system supports it.

4. **Audit the leak's blast radius.**
   - Where was the secret exposed (git, log, screenshot, message)?
   - Who could have seen it?
   - What systems/data did it grant access to?
   - Check audit logs for that period (Vercel logs, GitHub audit log, app logs).

5. **Clean up the exposure.**
   - Git: `git filter-repo` to remove the secret from history. Force-push after rotation. (Note: this breaks ADR-0002's no-force-push for this rare cleanup case.)
   - Logs: redact log lines containing the secret.

6. **File a postmortem.**

## Verification

- Old credential is non-functional
- New credential works in all systems
- The exposure has been removed from accessible places
- A postmortem ADR is filed proposing prevention

## Escalation

If the leak involved customer data (PII), there may be legal/compliance reporting obligations.
