# Reusable workflows

GitHub Actions reusable workflows referenced by per-project CI configurations. Defining them centrally means: change here once, every project gets the new version.

## Planned workflows

| Workflow | Purpose | Standard |
|---|---|---|
| `ci-python.yml` | Lint, type-check, test, security scan, build for Python | CI/CD + Quality gates |
| `ci-typescript.yml` | Same, for Node/TS | CI/CD + Quality gates |
| `ci-iac.yml` | `terraform validate` / `cdk synth`, tflint, tfsec/checkov | CI/CD + IaC |
| `claude-pr-review.yml` | Trigger code-reviewer + security-reviewer subagents on every PR | AI workflows |
| `claude-auto-adr.yml` | Detect significant changes; draft an ADR via architect subagent | Documentation + AI workflows |
| `release-please.yml` | Automated semver releases from Conventional Commits | Release management |
| `security-scan.yml` | Trivy / Snyk / npm audit / pip-audit scheduled scan | Quality gates |
| `dep-update-review.yml` | dep-watcher subagent reviews Dependabot/Renovate PRs | AI workflows |

These are placeholders. Each will be authored alongside its corresponding standards decision.
