# CLAUDE.md — Agentic Dev Environment

Instructions that apply to AI work inside this repo and (via template propagation) inside every project scaffolded from it.

## What this repo is

This is a meta-environment that defines mature-team engineering practices for solo projects. It contains standards, AI agents, hooks, and templates — not application code.

## Working principles

- **Standards live in `docs/standards/`.** When a question arises about how something should be done, check there first. If the standard doesn't exist yet, surface that to the user before guessing.
- **Decisions are recorded as ADRs in `docs/adr/`.** Significant tradeoffs get an ADR. Use the template in `docs/adr/template.md`.
- **AI agents are the labor.** Subagents are shipped via the `ai-team` plugin defined under `plugins/ai-team/` (per [ADR-0015](docs/adr/0015-platform-as-plugin.md)). Projects subscribe via `.claude/settings.json` rather than copying agent definitions locally. The plugin's subagents are the expected actors for routine tasks (review, scaffolding, testing, doc updates). The human's role is to direct and approve, not author boilerplate.
- **Templates are propagated, not edited downstream.** When a project diverges from its template, that's a signal to update the template — not to create a one-off.

## Communication style with the user

- Lead with the answer, then explain.
- Show tradeoffs explicitly — never hide alternatives the user might want to evaluate.
- Be concise. No filler. No trailing summaries of what was just done; the diff speaks for itself.
- If unsure, say so. Confident-wrong is the fastest way to lose trust.
- Push back when reasoning is sound; drop the position immediately when shown wrong.

## Decision-making

When proposing a standard or technical choice:

1. Research what authoritative sources (Google SRE book, ThoughtWorks, MS Engineering Playbook, Martin Fowler, language-specific style guides) recommend.
2. Present 2–4 viable options with tradeoffs.
3. Make a recommendation with reasoning, but defer to the user's discernment.
4. After decision: write the standards doc and the ADR together.

## Source of truth hierarchy

1. The user's direct instruction (this turn)
2. ADRs in `docs/adr/` (decisions already made)
3. Standards docs in `docs/standards/`
4. This `CLAUDE.md`
5. Per-project `CLAUDE.md` (in scaffolded projects only)

If sources conflict, escalate to the user rather than picking one silently.

## Platform components

Reusable components consumed by scaffolded projects. Each lives under `templates/_shared/` and is consumed via `file:` path (terraform modules) or `file:` npm dep (test-inbox) until the workspace publishes versioned releases.

| Component | Purpose | ADR |
|---|---|---|
| [`templates/_shared/terraform-modules/`](templates/_shared/terraform-modules/) | Shared OpenTofu/Terraform modules — IAM OIDC, Lambda base, observability baseline | [ADR-0007](docs/adr/0007-iac.md) |
| [`templates/_shared/test-inbox/`](templates/_shared/test-inbox/) | E2E-testing of email-bearing workflows (Cognito invites, magic links, notifications). Gmail-API-backed, Playwright fixture | [ADR-0014](docs/adr/0014-email-workflow-testing.md) |

Updates to platform components are template-propagation work: change the component, not the downstream consumer. Per `Working principles` above.

## The autonomous loop

This repo runs an **autonomous agent loop on GitHub Actions cron** — *not* Cowork scheduled tasks. If you are asked whether the "overnight" or "0900" run fired, check GitHub Actions run history (`gh run list`), never the Cowork scheduler.

- **What runs it:** `.github/workflows/triage-scan.yml` (scheduled scan + issue promoter) and `.github/workflows/claude-implementer.yml` (picks up labelled issues). `ci-health.yml` is a supporting watcher. All are GitHub Actions workflows.
- **When it runs:** autonomous work runs only inside two America/Chicago windows — `overnight` (01:00–04:00 daily) and `work-hours` (09:00–12:00 Mon–Fri). All other time is quiet. Windows, routing, and rationale are in [ADR-0017](docs/adr/0017-async-orchestration.md).
- **How to check it:** `gh run list --workflow=triage-scan.yml`. A scheduled run showing `success` with its `triage` job *skipped* is the cron firing outside the window — correct behaviour, not a failure.
- **Full detail:** [docs/runbooks/autonomous-loop.md](docs/runbooks/autonomous-loop.md) — windows, DST handling, manual triggering, routing, known gaps.

## What NOT to do

- Don't create one-off solutions in scaffolded projects when the issue belongs in the template.
- Don't write standards docs without the matching ADR.
- Don't introduce a new tool without an ADR justifying it over alternatives.
- Don't ship a standard that hasn't been decided — placeholder pages are fine; fabricated content isn't.
