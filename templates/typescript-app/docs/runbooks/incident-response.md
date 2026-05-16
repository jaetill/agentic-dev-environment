# Runbook: Incident response

## When to use this

The `incident-responder` agent has paged you (P0 alert), or you've otherwise observed prod is broken.

## Prerequisites

- Vercel dashboard access
- Sentry dashboard access
- Grafana Cloud dashboard access (for metrics)
- Project repo open

## Steps

1. **Acknowledge.** Stop other work. Note the time you started.

2. **Triangulate the cause.** In ~5 minutes, determine likely cause:
   - Recent deploy? → Most likely cause; rollback per [`rollback.md`](rollback.md).
   - Sudden traffic spike? → Vercel auto-scales; check edge cache hit rate.
   - Dependency failure (DB, third-party)? → Check status pages.
   - Bad config? → Check the most recent env var changes in Vercel.

3. **Mitigate.** In order of safety:
   - **Promote previous deployment** (Vercel dashboard one-click).
   - **Disable feature flag** if a specific feature is implicated.
   - **Take offline** as last resort (set alias to maintenance page).

4. **Verify mitigation worked.** Wait 5 min minimum.

5. **Document while it's fresh.** Open a postmortem draft (`/postmortem` slash command).

## Verification

- The alert that fired no longer fires
- HTTP 5xx rate, p99 latency back to baseline
- No new errors in Sentry for the affected paths
- Grafana dashboards green

## Rollback

If your mitigation made things worse, get back to a known state — usually the last successful deploy.

## Escalation

For solo: that's you. If the incident exceeds 30 min and you're stuck, document the state thoroughly and consider taking offline.

## Postmortem

Within 48 hours of resolution, draft a postmortem (`/postmortem` slash command).
