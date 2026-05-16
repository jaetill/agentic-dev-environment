# {{project_name}}

{{project_description}}

This project is built on the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment) platform. The platform's [10 standards](https://github.com/{{github_username}}/agentic-dev-environment/tree/main/docs/standards) define source control, CI/CD, testing, quality gates, documentation, observability, secrets, IaC, releases, and AI workflows.

## What's here

- [Architecture overview](architecture/overview.md) — high-level shape of the system
- [ADRs](adr/index.md) — architecture decision records for this project
- [Runbooks](runbooks/index.md) — operational playbooks
- [API reference](api/index.md) — auto-generated from code

## Stack

- Python 3.12+ FastAPI service deployed to AWS Lambda
- OpenTofu for infrastructure
- Sentry + AWS X-Ray + CloudWatch + Grafana for observability

## Status

(Project-specific status — what's live, what's pending, recent releases.)
