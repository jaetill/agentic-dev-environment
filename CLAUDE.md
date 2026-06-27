# CLAUDE.md — Agentic Dev Environment

Instructions that apply to AI work inside this repo and (via template propagation) inside every project scaffolded from it.

## What this repo is

This is a meta-environment that defines mature-team engineering practices for solo projects. It contains standards, AI agents, hooks, and templates — not application code.

## Path-scoped rules

File-type-specific guidance lives in [`.claude/rules/`](.claude/rules/) and loads only when an agent works with matching files (per the `paths:` frontmatter), keeping this file focused on always-on behaviour:

| Rule file | Loads when touching | Covers |
|---|---|---|
| [`adr-authoring.md`](.claude/rules/adr-authoring.md) | `docs/adr/**`, `docs/standards/**` | Draft-from-template, enforced ADR sections, Implementation line, terminology glossary |
| [`agent-authoring.md`](.claude/rules/agent-authoring.md) | `plugins/ai-team/agents/**` | Frontmatter-copy rule, probe-before-pin |
| [`ci-workflows.md`](.claude/rules/ci-workflows.md) | `.github/workflows/**`, `scripts/**` | First-party `@main` pinning, loud-on-zero sweeps, the autonomous loop |
| [`shared-components.md`](.claude/rules/shared-components.md) | `templates/_shared/**`, `infra/**`, `**/*.tf` | Platform-component & fleet-infra tables, template propagation |

## Working principles

- **Standards live in `docs/standards/`.** When a question arises about how something should be done, check there first. If the standard doesn't exist yet, surface that to the user before guessing.
- **Decisions are recorded as ADRs in `docs/adr/`.** Significant tradeoffs get an ADR. Use the template in `docs/adr/template.md`.
- **AI agents are the labor.** Subagents are shipped via the `ai-team` plugin defined under `plugins/ai-team/` (per [ADR-0015](docs/adr/0015-platform-as-plugin.md)). Projects subscribe via `.claude/settings.json` rather than copying agent definitions locally. The plugin's subagents are the expected actors for routine tasks (review, scaffolding, testing, doc updates). The human's role is to direct and approve, not author boilerplate.
- **Templates are propagated, not edited downstream.** When a project diverges from its template, that's a signal to update the template — not to create a one-off.

## Session hygiene — commit before you stop

Uncommitted work is **invisible to the next session**: an agent sees committed history, never another session's untracked files or unstaged edits. Work left on disk rots silently — and unmerged work piles up because the human-merge gate is the bottleneck. So:

- **Commit WIP before the session ends — always.** Even unfinished, even if it won't be merged yet. Put it on a descriptive branch (`wip/<topic>`); never leave generated files untracked or edits unstaged. A clearly-labelled partial commit ("WIP: `<done>` / `<remaining>`") is recoverable and discoverable (`git branch`, `git log`); an untracked file is neither. If the session produced a file, it gets committed.
- **Inventory unmerged work at session start.** Before starting new work, run `git status` and check open branches/PRs across the repos in play; surface anything stale rather than building on top of forgotten WIP.
- **Branch from a freshly-fetched remote, never from local `main`.** Merges land on the *remote* (via `gh pr merge`), so local `main` goes stale within a session and `git checkout -B <branch> origin/main` after a partial fetch can silently base the branch on an old commit — the commit then lands on stale local `main` and the diff picks up cross-file reversions. Always `git fetch origin main` immediately before `git checkout -B <branch> origin/main`, and after merging a PR run `git branch -f main origin/main` to resync. Verify the new branch's base with `git log -1 --oneline origin/main` before committing. (Cost three recovered mis-bases in the 2026-06-05 session.)
- **Never write through the Linux sandbox mount for a Windows-mounted repo.** The mount can serve stale views; writes through it (`sed -i`, `cp`, shell redirects) can truncate real files. Use the Edit/Write tools for file changes, run `git` via Windows (PowerShell), and verify diffs with Windows `git` — not sandbox `git`.

## Merge discipline — the checks are the proofreader

Two fleet-wide merge freezes (2026-06-02 and 2026-06-05) had the same anatomy: an ADR landed on `main` missing checker-required content, and because `validate`/`adr-format-check` run against the **whole tree**, every subsequent platform PR went red. Both times the gate had caught the problem on the offending PR — and was bypassed with `--admin`. So:

- **Never `--admin`-merge before the checks finish.** The skip-and-block deadlock that justified reflexive `--admin` was fixed by ADR-0024; platform PRs now reach `mergeState: CLEAN` on their own. Wait for `validate`, `adr-format-check`, `agent-frontmatter-check`, and `link-check` to pass, then merge normally. `--admin` is for genuine emergencies and for the human ratifying a held compositional PR — never to outrun a pending check.
- Authoring rules that previously lived here (ADR drafting, agent frontmatter, reviewer probe-before-pin, workflow pinning, loud-on-zero sweeps) now load with their file types — see [Path-scoped rules](#path-scoped-rules) above.

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
4. This `CLAUDE.md` and the path-scoped rules in `.claude/rules/`
5. Per-project `CLAUDE.md` (in scaffolded projects only)

If sources conflict, escalate to the user rather than picking one silently.

## The autonomous loop

This repo runs an **autonomous agent loop on GitHub Actions cron** — *not* Cowork scheduled tasks. If you are asked whether the "overnight" or "0900" run fired, check GitHub Actions run history (`gh run list`), never the Cowork scheduler. Mechanics, windows, and routing load with the workflow files — see [`.claude/rules/ci-workflows.md`](.claude/rules/ci-workflows.md) and [docs/runbooks/autonomous-loop.md](docs/runbooks/autonomous-loop.md).

## What NOT to do

- Don't create one-off solutions in scaffolded projects when the issue belongs in the template.
- Don't write standards docs without the matching ADR.
- Don't introduce a new tool without an ADR justifying it over alternatives.
- Don't ship a standard that hasn't been decided — placeholder pages are fine; fabricated content isn't.
