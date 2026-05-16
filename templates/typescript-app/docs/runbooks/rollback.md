# Runbook: Manual rollback

## When to use this

The auto-rollback failed (per platform [ADR-0003](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0003-ci-cd.md)) and prod is in a degraded state. The `incident-responder` agent has paged you.

## Prerequisites

- Vercel access (CLI or dashboard)
- The previous known-healthy deployment URL (find via `vercel list` or in the Vercel dashboard)

## Steps

1. **Identify the previous healthy deployment.**
   In Vercel dashboard: navigate to the project → "Deployments" → find the most recent "Ready" deployment before the broken one.

2. **Promote it to production:**
   - **Dashboard:** click the deployment → "Promote to Production"
   - **CLI:**
     ```bash
     vercel ls {{project_name}}
     vercel alias set <previous-deployment-url> {{project_name}}.vercel.app
     ```

3. **For database rollback if needed:**
   See `db-rollback.md` (project-specific runbook) — Drizzle migrations should be reversible per Standard 11 / ADR-0006 expand-contract pattern.

## Verification

- HTTP 200 from `/api/health` and `/api/ready`
- No 5xx in Sentry for 5 min post-rollback
- Verify the active alias points to the correct deployment

## Rollback (of the rollback)

If the rollback breaks something else, escalate. Don't try to "patch forward" during an incident.

## Escalation

If you can't get back to a healthy state within 30 minutes, declare a major incident. Consider taking the site offline via Vercel's project settings (set the alias to a maintenance page).
