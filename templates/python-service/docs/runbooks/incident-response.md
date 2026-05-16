# Runbook: Incident response

## When to use this

The `incident-responder` agent has paged you (P0 alert), or you've otherwise observed prod is broken.

## Prerequisites

- Access to AWS console + Grafana Cloud + Sentry
- Project repo open
- Authenticated to AWS for the affected environment

## Steps

1. **Acknowledge.** Stop other work. Open this runbook and the platform's CLAUDE.md. Note the time you started.

2. **Triangulate the cause.** In ~5 minutes, determine likely cause:
   - Recent deploy? → Most likely cause; go to step 3 (rollback).
   - Sudden traffic spike? → Check autoscaling; consider scale-up.
   - Dependency failure (RDS, third-party)? → Check status pages.
   - Bad config? → Check the most recent IaC apply.
   - Data quality? → Check whether prod data is corrupted.

3. **Mitigate.** In order of safety:
   - **Auto-rollback** to last healthy deploy (try first; usually `incident-responder` already attempted).
   - **Alias swap** for Lambda (see [`rollback.md`](rollback.md)).
   - **Scale up** if it's a capacity issue.
   - **Restart** if it's a stuck-process issue (only for stateless services).

4. **Verify mitigation worked** by watching the metric that fired the alert. Wait 5 min minimum.

5. **Document while it's fresh.** Open a postmortem draft (`/postmortem` slash command).

## Verification

- The alert that fired no longer fires
- HTTP 5xx rate, p99 latency, synthetic smoke test all back to baseline
- No new errors in Sentry for the affected paths
- Grafana dashboards green

## Rollback

If your mitigation made things worse, get back to a known state — usually the last successful deploy, even if it had the bug that started this incident. Worse-than-broken is unacceptable.

## Escalation

For solo: that's you. If the incident exceeds 30 min and you're stuck:

- Take the service offline (HTTP 503 maintenance page) if data integrity is at risk
- Document the state thoroughly
- Sleep on it if non-critical; resume in the morning with fresh eyes

## Postmortem

Within 48 hours of resolution, draft a postmortem (`/postmortem` slash command). Per platform standards: blameless, with a real root cause and prevention steps. If prevention requires architectural change, file an ADR.
