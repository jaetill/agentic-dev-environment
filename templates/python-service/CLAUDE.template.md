# CLAUDE.md — {{project_name}}

This project inherits from the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment) platform. The platform's standards (10) and ADRs (11+) define how this project is operated. This file holds **project-specific** context only.

## What this project is

{{project_description}}

## Stack at a glance

- Python 3.12+ FastAPI service
- Deployed to AWS Lambda + API Gateway via OpenTofu
- Three environments: dev, staging, prod
- Live data: {{has_live_data}} ({{describe_live_data}})

## Project-specific conventions

{{project_specific_conventions}}

## Critical-tier paths (require 90% coverage + mutation testing per ADR-0004)

- `src/{{project_slug}}/auth/`
- `src/{{project_slug}}/payments/` (if applicable)
- `src/{{project_slug}}/migrations/`
- (Add others specific to this project)

## Utility-tier paths (60% coverage acceptable)

- `src/{{project_slug}}/utils/`
- `src/{{project_slug}}/lib/helpers/`

## Project-specific runbooks

- (List runbooks beyond the platform defaults)

## SLO targets (per ADR-0009 §8)

- Availability: 99.5% (≈3.6h downtime/month)
- p99 latency: <500ms on primary endpoints
- Error rate: <0.5%

## Active concerns

(Things the head agent should know about. Examples: known intermittent issue with X; pending migration from Y to Z; deprecation of feature W.)

## Source of truth

When inheriting platform standards conflict with project needs:

1. Check whether a project-level ADR documents the deviation.
2. If not, file an ADR proposing the deviation; do not silently diverge.
3. The platform's standards win unless this project's ADR explicitly overrides for documented reasons.

This file is bounded at ≤200 lines per [ADR-0008](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0008-documentation.md).
