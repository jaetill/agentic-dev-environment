# {{project_name}}

{{project_description}}

Built on the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment) platform — see that repo for the standards and ADRs that govern this project.

## Quick start

```bash
# Install dependencies
uv sync

# Run with secrets injected from 1Password
op run --env-file=.env.local.template -- uv run python -m {{project_slug}}

# Or run with a local .env.local (gitignored)
uv run python -m {{project_slug}}
```

## Documentation

- Published docs: https://{{github_username}}.github.io/{{project_name}}/
- Architecture overview: [`docs/architecture/overview.md`](docs/architecture/overview.md)
- ADRs: [`docs/adr/`](docs/adr/)
- Runbooks: [`docs/runbooks/`](docs/runbooks/)

## Stack

- **Language:** Python 3.12+
- **Web framework:** FastAPI
- **Package manager:** [uv](https://github.com/astral-sh/uv)
- **Tests:** pytest with tiered coverage (per platform [ADR-0004](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0004-testing.md))
- **Lint/format:** Ruff (pragmatic-strict ruleset)
- **Type-check:** mypy `--strict`
- **Deploy:** AWS Lambda via OpenTofu (per platform [ADR-0007](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0007-iac.md))

## Development

```bash
# Run tests
uv run pytest                              # all tests
uv run pytest tests/unit                   # unit only (fast)
uv run pytest --cov                        # with coverage report

# Lint + format
uv run ruff check                          # lint
uv run ruff format                         # format
uv run mypy src                            # type-check

# Pre-commit (runs subset locally; full battery in CI)
uv run pre-commit run --all-files
```

## Releasing

You don't have to do anything. `release-please` opens a release PR when there are accumulated changes; the `release-captain` AI agent reviews and auto-merges. Per platform [ADR-0010](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0010-release-management.md).

## License

{{license}}
