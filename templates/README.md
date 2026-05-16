# Templates

Per-stack project scaffolds. Each template is a cookiecutter (or copier) directory that produces a fully-wired project: CI, gates, tests, docs, observability, AI configuration.

## Stacks

| Template | Stack | Status |
|---|---|---|
| `python-service/` | Python (FastAPI / Click / Typer), uv, pytest, Ruff | Skeleton |
| `typescript-app/` | TypeScript (Node + web), pnpm, Vitest, ESLint | Skeleton |
| `aws-iac/` | AWS Terraform or CDK (decision pending in IaC standard) | Skeleton |
| `_shared/` | Assets reused by every template (workflows, pre-commit, .claude/) | Skeleton |

## Building order

Templates can't be authored until standards 1–10 are decided — every template embeds those decisions. The build order is:

1. Decide all standards.
2. Build `_shared/` first (the cross-cutting assets).
3. Build per-stack templates that consume `_shared/`.
4. Verify by scaffolding a real project (Task #17).

## Out of scope (for now)

Go and Rust templates. Will be added if/when Jason picks up either stack.
