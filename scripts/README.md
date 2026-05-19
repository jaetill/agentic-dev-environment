# Scripts

Bootstrap and maintenance utilities for the platform.

## Existing scripts

| Script | Purpose |
|---|---|
| `bootstrap-tfstate.sh` | One-time-per-account setup for S3 + DynamoDB tofu state backend |
| `bootstrap-grafana.sh` | Cross-account IAM role for Grafana Cloud CloudWatch pull |
| `generate-apigw-rest-tf.ps1` | Introspect a deployed REST API and emit Terraform HCL + import blocks (used during Phase 6 retrofits — saves hours per API vs. hand-writing 50+ resources) |
| `initial-commit.sh` | First-commit bootstrap for a new project |
| `new-project.sh` | Scaffold a new project from template, initialize git, wire gates |
| `sentry-create-alert.ps1` | Idempotent Sentry issue alert rule creator |
| `sentry-create-project.ps1` | Idempotent Sentry project creator |
| `test-inbox-push-secrets.ps1` / `test-inbox-run.ps1` | Email-test fixture helpers per ADR-0014 |
| `validate-platform.sh` | CI helper — validates platform internal consistency |

## Planned scripts

| Script | Purpose | Status |
|---|---|---|
| `new-project.sh` | Scaffold a new project from a template into a target directory; initialize git, push to GitHub, wire up gates | Planned |
| `apply-standards.sh` | Retrofit an existing project to the current platform standards (idempotent; reports diffs before applying) | Planned (deferred — see ADR-0001) |
| `update-projects.sh` | Pull platform updates into all known scaffolded projects (with confirmation per project) | Planned |
| `validate-platform.sh` | CI helper — verify that templates, workflows, and standards docs are internally consistent | Planned |

All scripts will be POSIX-shell where reasonable, Python where shell becomes painful. No project-specific logic in scripts; logic lives in templates and workflows.
