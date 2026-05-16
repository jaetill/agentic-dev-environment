# {{project_name}}

{{project_description}}

This project is built on the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment) platform. The platform's [11 standards](https://github.com/{{github_username}}/agentic-dev-environment/tree/main/docs/standards) define source control, CI/CD, testing, quality gates, documentation, observability, secrets, IaC, releases, AI workflows, and user feedback.

## What's here

- [Architecture overview](architecture/overview.md) — high-level shape of the system
- [ADRs](adr/index.md) — architecture decision records for this project
- [Runbooks](runbooks/index.md) — operational playbooks
- [API reference](api/index.md) — auto-generated from code (TypeDoc)

## Stack

- TypeScript + Next.js 15 App Router deployed to Vercel
- Drizzle ORM + Postgres
- Sentry + AWS X-Ray + OTEL + Grafana for observability
- User feedback flowing into GitHub Issues via `triage-bot` (per Standard 11)

## Status

(Project-specific status — what's live, what's pending, recent releases.)
