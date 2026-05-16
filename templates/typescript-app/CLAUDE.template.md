# CLAUDE.md — {{project_name}}

This project inherits from the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment) platform. The platform's standards (11) and ADRs (12+) define how this project is operated. This file holds **project-specific** context only.

## What this project is

{{project_description}}

## Stack at a glance

- TypeScript (strict) + Next.js 15 App Router
- Deployed to Vercel; AWS-side resources (DB, etc.) via OpenTofu if needed
- Three environments: dev, staging, prod
- Live data: {{has_live_data}} ({{describe_live_data}})

## Project-specific conventions

{{project_specific_conventions}}

## Critical-tier paths (require 90% coverage + mutation testing per ADR-0004)

- `src/lib/auth/`
- `src/lib/payments/` (if applicable)
- `src/lib/db/migrations/`
- (Add others specific to this project)

## Tier overrides (in vitest.config.ts)

- **Critical (90/80):** `src/lib/auth/**`, payment paths
- **Standard (80/70):** default
- **User-facing API (85/75):** `src/app/api/feedback/**` (per Standard 11)
- **Utility (60/50):** `src/lib/utils/**`

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
