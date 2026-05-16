# Architecture overview

(One-page architecture summary. Replace placeholders with real content as the project takes shape.)

## Context

What does this system do, and for whom? What's the user-visible value? What's the business value?

## Container view (C4 level 2)

```mermaid
graph TB
    User[User] -->|HTTPS| API[API Gateway]
    API -->|invoke| Lambda[Lambda: {{project_slug}}]
    Lambda -->|read/write| DB[(PostgreSQL)]
    Lambda -->|secrets| SM[Secrets Manager]
    Lambda -->|logs| CW[CloudWatch Logs]
    Lambda -->|errors| Sentry[Sentry]
    Lambda -->|traces| XRay[AWS X-Ray]
```

## Components

- **API Gateway:** routes HTTPS requests to Lambda. Throttled per env per AWS Budgets (ADR-0007).
- **Lambda:** the FastAPI service. Cold-start <1s; runtime in Python 3.12.
- **PostgreSQL:** RDS instance per env. Master password auto-rotated 30 days (ADR-0006).
- **Secrets Manager:** holds DB connection string, third-party API tokens. App reads at startup; cached per process.
- **Observability:** structured JSON logs to CloudWatch; errors to Sentry with releases tracked; traces via OTEL → X-Ray; dashboards in Grafana Cloud (ADR-0009).

## Key design decisions

- All ADRs live under [`docs/adr/`](../adr/index.md). Significant decisions have an ADR; routine code changes don't.
- Inherited standards from the platform are linked, not duplicated.

## Non-functional targets (SLOs per ADR-0009 §8)

- Availability: 99.5%
- p99 latency: <500ms
- Error rate: <0.5%

## Out of scope

What this system *doesn't* do (so future-self knows where the boundaries are).
