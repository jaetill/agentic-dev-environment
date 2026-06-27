---
paths:
  - "templates/_shared/**"
  - "infra/**"
  - "**/*.tf"
---

# Shared components & fleet infrastructure

**Template-propagation principle:** updates to a shared component are template work — change the component, not the downstream consumer. When a project diverges from its template, that's a signal to update the template, not to create a one-off.

## Platform components

Reusable components consumed by scaffolded projects. Each lives under `templates/_shared/` and is consumed via `file:` path (terraform modules) or `file:` npm dep (test-inbox) until the workspace publishes versioned releases.

| Component | Purpose | ADR |
|---|---|---|
| [`templates/_shared/terraform-modules/`](../../templates/_shared/terraform-modules/) | Shared OpenTofu/Terraform modules — IAM OIDC, Lambda base, observability baseline | [ADR-0007](../../docs/adr/0007-iac.md) |
| [`templates/_shared/test-inbox/`](../../templates/_shared/test-inbox/) | E2E-testing of email-bearing workflows (Cognito invites, magic links, notifications). Gmail-API-backed, Playwright fixture | [ADR-0014](../../docs/adr/0014-email-workflow-testing.md) |

## Fleet infrastructure

Standalone infrastructure living in `infra/` — fleet-level singletons, not reusable template modules.

| Component | Purpose | ADR |
|---|---|---|
| [`infra/ops-cockpit/`](../../infra/ops-cockpit/) | Grafana Cloud ops cockpit — loop run health, fleet issue/PR flow, human TODOs. Terraform-managed, self-refreshing. | [ADR-0022](../../docs/adr/0022-ops-cockpit-dashboard-host.md) |
