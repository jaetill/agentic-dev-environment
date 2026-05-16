# {{project_name}}

{{project_description}}

Built on the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment) platform — see that repo for the standards and ADRs that govern this project.

## Quick start

```bash
# Install dependencies
pnpm install

# Run dev server with secrets injected from 1Password
op run --env-file=.env.local.template -- pnpm dev
```

Visit [http://localhost:3000](http://localhost:3000).

## Documentation

- Published docs: https://{{github_username}}.github.io/{{project_name}}/
- Architecture overview: [`docs/architecture/overview.md`](docs/architecture/overview.md)
- ADRs: [`docs/adr/`](docs/adr/)
- Runbooks: [`docs/runbooks/`](docs/runbooks/)

## Stack

- **Language:** TypeScript (strict mode + extras per platform [ADR-0005](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0005-quality-gates.md))
- **Framework:** Next.js 15 (App Router)
- **Package manager:** pnpm
- **Tests:** Vitest with tiered coverage (per platform [ADR-0004](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0004-testing.md)) + Playwright for e2e
- **Lint:** ESLint flat config + typescript-eslint
- **Format:** Prettier
- **ORM:** Drizzle (Postgres)
- **Errors:** Sentry
- **Logging:** pino with OTEL fields
- **Deploy:** Vercel (default) — terraform/ for AWS-side resources if needed

## Development

```bash
# Run tests
pnpm test                                  # all tests (CI mode)
pnpm test:watch                            # watch mode
pnpm test:coverage                         # with coverage report
pnpm test:e2e                              # Playwright (requires app running)

# Lint + format + typecheck
pnpm lint                                  # ESLint
pnpm lint:fix
pnpm format                                # Prettier (write)
pnpm format:check                          # Prettier (check only)
pnpm typecheck                             # tsc --noEmit

# Database
pnpm db:generate                           # generate migration from schema
pnpm db:migrate                            # apply pending migrations
pnpm db:studio                             # browse the DB locally
```

## User feedback

This project implements [Standard 11](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/standards/11-user-feedback.md):

- `POST /api/feedback` — custom in-app feedback form
- `POST /api/sentry-feedback` — Sentry User Feedback webhook receiver

Both create GitHub Issues with `feedback:*` labels; the platform's `triage-bot` agent classifies them on its daily scan.

## Releasing

You don't have to do anything. `release-please` opens a release PR when there are accumulated changes; the `release-captain` AI agent reviews and auto-merges. Per platform [ADR-0010](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0010-release-management.md).

## License

{{license}}
