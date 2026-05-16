# Agentic Dev Environment

A personal engineering platform that imposes mature-team SDLC practices across solo projects, with AI agents doing the labor and the human acting as reviewer/approver.

## What this is

A **meta-environment** that sits above individual projects and provides:

1. **Standards as code** — the decisions a mature team would have made (branching, CI/CD, testing, observability, secrets, IaC, releases) written down, version-controlled, and propagated to every project.
2. **An AI team** — subagents (architect, code-reviewer, security-reviewer, testers, doc-keeper, release-captain, dep-watcher, scrummaster, incident-responder) that apply those standards on demand or on triggers.
3. **Hooks** — lifecycle policies that make standards non-optional at the IDE / CLI layer.
4. **Templates** — cookiecutter scaffolds per supported stack (Python, TypeScript/Node, AWS IaC) with all gates pre-wired.
5. **Reusable workflows** — GitHub Actions that mirror the local hooks server-side.
6. **Glue** — scripts to bootstrap new projects and retrofit existing ones.

## Why

Solo development tends to skip the practices that make team development reliable: PR review, ADRs, coverage gates, runbooks, structured logging, etc. The cost of skipping them compounds as projects accumulate. This platform pushes that cost back where it belongs — onto AI agents that don't tire — so the human can stay focused on judgment calls (Wonder + Discernment) rather than execution drudgery.

## Layout

```
.
├── README.md                  this file
├── CLAUDE.md                  AI workflow rules (inherited by every project)
├── docs/
│   ├── standards/             the standards docs (one per concern)
│   ├── adr/                   architecture decision records
│   └── runbooks/              operational playbooks
├── plugins/
│   └── ai-team/               canonical AI configuration (agents, commands, hooks, skills)
├── .claude-plugin/
│   └── marketplace.json       this workspace IS a Claude Code marketplace
├── templates/                 per-stack project templates
│   ├── python-service/
│   ├── typescript-app/
│   ├── aws-iac/
│   └── _shared/
│       ├── github-workflows/  reusable GH Actions referenced by per-stack CI
│       ├── pre-commit/        pre-commit configs
│       ├── terraform-modules/ shared OpenTofu/Terraform modules
│       └── test-inbox/        Gmail-API-backed E2E inbox helper
├── scripts/                   bootstrap + retrofit scripts
└── .github/workflows/         reusable GitHub Actions workflows (consumed by scaffolded projects via `<owner>/agentic-dev-environment/.github/workflows/<file>@<tag>`) + the platform's own CI
```

**Note on AI configuration delivery (per [ADR-0015](docs/adr/0015-platform-as-plugin.md)):**

The platform's AI configuration (subagents, slash commands, hooks, skills) ships as a Claude Code plugin named `ai-team`, defined under `plugins/ai-team/`. The workspace itself is a marketplace (`.claude-plugin/marketplace.json` at the root). Each consuming project subscribes via its `.claude/settings.json` rather than copying files locally — see ADR-0015 for the migration rationale and the canonical subscription block.

**Note on permissions:** the plugin ships agents, commands, hooks, and skills — it does NOT and cannot ship `permissions` rules. The `Read`, `Edit`, `Write`, `Glob`, and `Bash` patterns that govern what tools can actually touch are controlled by your user-level `~/.claude/settings.json` and each project's `.claude/settings.json`, never by the plugin. The plugin's [README](plugins/ai-team/README.md#permissions--important-to-understand) carries the canonical project-level deny block as a recommended baseline.

## Status

**All 11 standards decided** (see [`docs/standards/index.md`](docs/standards/index.md) and [`docs/adr/`](docs/adr/)). Implementation substantially complete:

- ✅ AI configuration as plugin: 14 subagents + 10 slash commands + 12 hooks + 31 skills (`plugins/ai-team/`)
- ✅ python-service template + shared Terraform modules + module tests (native + Terratest)
- ✅ Reusable GitHub Actions workflows
- ✅ Scaffolding scripts
- ✅ Three projects subscribed to the platform plugin (game-night-pwa, meal-planner, ai-teacher)
- 🟦 typescript-app + aws-iac standalone templates: deferred until needed

## Bootstrap (first time on a new clone)

```bash
bash scripts/initial-commit.sh                  # init git, first commit, tag modules/v0.1.0
bash scripts/validate-platform.sh               # verify internal consistency
gh repo create <user>/agentic-dev-environment --public --source=. --push
git push --tags
```

Per-AWS-account, one-time:

```bash
bash scripts/bootstrap-tfstate.sh               # S3 + DynamoDB lock + GitHub OIDC provider
bash scripts/bootstrap-grafana.sh --grafana-org=<id>   # cross-account IAM for Grafana Cloud
```

Then scaffold a project:

```bash
bash scripts/new-project.sh --stack=python-service --name=my-thing
```

## How a project consumes this

(Once templates are built — currently aspirational.)

```bash
# scaffold a new project from a stack template
./scripts/new-project.sh --stack python-service --name my-thing

# retrofit an existing project to current standards
./scripts/apply-standards.sh /path/to/existing-project
```

A scaffolded project inherits the platform's `CLAUDE.md` rules, subscribes to the `ai-team` plugin via its `.claude/settings.json` (per [ADR-0015](docs/adr/0015-platform-as-plugin.md)), and is wired to reusable workflows in this repo.
