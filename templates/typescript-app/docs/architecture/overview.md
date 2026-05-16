# Architecture overview

(One-page architecture summary. Replace placeholders with real content as the project takes shape.)

## Context

What does this system do, and for whom? What's the user-visible value? What's the business value?

## Container view (C4 level 2)

```mermaid
graph TB
    User[User] -->|HTTPS| Vercel[Vercel Edge]
    Vercel -->|App Router| Next[Next.js App]
    Next -->|Drizzle| DB[(Postgres)]
    Next -->|API| Sentry[Sentry]
    Next -->|OTEL| XRay[AWS X-Ray]
    Next -->|Logs| CW[CloudWatch Logs]
    User -->|Feedback widget| Feedback[/api/feedback]
    Feedback -->|GitHub API| GHIssues[(GitHub Issues)]
    Sentry -->|Webhook| SentryFB[/api/sentry-feedback]
    SentryFB --> GHIssues
```

## Components

- **Vercel:** edge + serverless host. Auto-deploys on tag from `main`.
- **Next.js App:** App Router, React 19, Server Components.
- **Postgres + Drizzle:** ORM-agnostic schema with type-safe queries.
- **Sentry:** error tracking + User Feedback widget for error-attached reports (per Standard 11 Tier 1).
- **`/api/feedback`:** custom feedback endpoint for general bug/feature reports (per Standard 11 Tier 2).
- **GitHub Issues:** unified storage for both feedback tiers; consumed by `triage-bot` agent.
- **CloudWatch Logs / X-Ray:** structured logs + traces (per ADR-0009).
- **Grafana Cloud:** dashboards over CloudWatch + Sentry + X-Ray.

## Key design decisions

- All ADRs live under [`docs/adr/`](../adr/index.md). Significant decisions have an ADR; routine code changes don't.
- Inherited standards from the platform are linked, not duplicated.

## Non-functional targets (SLOs per ADR-0009 §8)

- Availability: 99.5%
- p99 latency: <500ms
- Error rate: <0.5%

## Out of scope

What this system *doesn't* do (so future-self knows where the boundaries are).
