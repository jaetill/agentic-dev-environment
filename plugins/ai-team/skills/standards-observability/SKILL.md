---
name: standards-observability
description: Use when the user asks about logging format, metrics, tracing, alerting, or dashboards. Covers JSON structured logs + CloudWatch + Sentry + Grafana + AWS X-Ray.
---

# Standard 06 — Observability

Structured JSON logs (no plain text). CloudWatch for AWS-side logs, Sentry for application errors, Grafana for dashboards (Grafana Cloud pulls CloudWatch + custom metrics per ADR-0013), AWS X-Ray for distributed traces.

Three signals: logs, metrics, traces. SLOs defined per service; alerts route to the on-call channel.

**Read the full standard for any operational question:** `${CLAUDE_PLUGIN_ROOT}/skills/standards-observability/standard.md`

## See also

- ADR-0009 (the reasoning)
- ADR-0013 (Grafana Cloud + CloudWatch pull)
- [[standards-release-management]] — observability gates a release as healthy
