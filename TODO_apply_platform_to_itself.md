# TODO: Publish workspace to GitHub — HIGH priority

**Captured:** 2026-05-15 evening, before Jason's break.
**Reframed:** 2026-05-16 after the plugin migration (ADR-0015) landed on all three projects. The original "apply platform to itself" framing still applies, but a more pressing motivation now exists: each subscribing project's `.claude/settings.json` carries an absolute Windows path to the workspace marketplace. That is load-bearing single-machine state — anyone else who clones game-night-pwa, meal-planner, or ai-teacher gets a project that can't load the plugin. Publishing the workspace to GitHub lets the marketplace `source` become `{"source": "github", "repo": "jaetill/agentic-dev-environment"}` and removes the absolute-path dependency across all three projects.

**Status:** Highest-leverage outstanding work item. Architecture question is resolved (ADR-0015).

## The premise

The Agentic Dev Environment workspace is, itself, a project. It contains code (terraform modules, `templates/_shared/test-inbox/` TS package, PowerShell scripts), docs (ADRs, standards, runbooks), and platform templates. The platform that demands rigor of every other project does NOT yet apply that rigor to itself.

Specifically:
- Its `.git` is a stub (HEAD exists, no objects/, no refs/).
- No GitHub remote. Nothing tracks changes.
- No CI. No PR review. No release-please.
- Three projects depend on `templates/_shared/test-inbox/` via `file:` deps; if it breaks, all three break silently.
- ADRs exist but nobody reviews them (no agent pipeline on the workspace).

## What "applying the platform to itself" would look like

1. **`git init` properly** + initial commit of current state.
2. **Publish to GitHub** as `jaetill/agentic-dev-environment` (private or public — decide).
3. **Apply Phases 1-4 of platform adoption** to the workspace itself. This is delicious recursion: use the platform's verbatim agents and standards to bring the workspace into compliance with the platform.
4. **Install a CI workflow** that runs `npm test` against `templates/_shared/test-inbox/` (the only code that has tests currently).
5. **Install `claude-pr-review` + `security-review` + `dep-watcher`** on the workspace. Now every change to a platform agent, hook, or shared component gets reviewed by other platform agents.
6. **`release-please`** to ship versioned platform releases. Projects can then pin against versions instead of file: paths.

## Where the recursion gets interesting

- The agents that review the workspace are the agents being changed. PRs that modify `code-reviewer.md` would be reviewed by the current version of `code-reviewer`. Tests of the platform run against the platform.
- Standard 04 (quality gates) currently has zero teeth on the workspace. After self-application, it has teeth on its own definition.
- The "platform port procedure" memory describes the steps. The workspace would BE the first reference application of the procedure on itself.

## Benefits

- **Bugs in the platform get caught BY the platform.** The Turbopack/`instrumentation-client.ts` trap would have surfaced in a PR review by the very agents that should know about Next.js, IF those agents had been reviewing the templates.
- **Drift detection.** When a project's `.claude/settings.json` drifts from the canonical subscription block (e.g. someone re-introduces locally-committed agent files), drift-detector flags it. Pre-plugin migration, the equivalent drift was between each project's `.claude/agents/` and the workspace's source; now drift detection lives at the subscription/version boundary.
- **Real release cadence.** Today the workspace evolves silently. With release-please, every platform change becomes a versioned event that downstream projects can subscribe to (or pin against).
- **Dogfooding pressure.** When the platform's own usability matters because YOU feel it, you'll fix the rough edges faster.

## Risks / friction

- **Chicken-and-egg.** Initial commit can't go through PR review because the workflows aren't on main yet. Same bootstrap problem game-night-pwa had — handle with a single one-time direct push, then enforce afterward.
- **Recursive complexity.** If a PR modifies an agent definition and the agent reviews the PR, do we use the new agent or the old one? GitHub Actions checks out the PR branch, so the NEW agent reviews itself. Could be fine, could be weird. Worth thinking through before committing.
- **Time investment.** This IS more platform work, exactly what Jason just said he wants less of. The trap is real. Sequencing matters: ship features first, dogfood the platform second.
- **~~Decision interaction with TODO_platform_architecture_review.md~~** — RESOLVED 2026-05-16 by ADR-0015. The outer-team direction is now in place via the plugin migration. What gets dogfooded is now well-defined: the plugin itself (`plugins/ai-team/`), the marketplace, and the workspace's supporting code (terraform modules, test-inbox, scripts, docs).

## Recommended sequencing (updated 2026-05-16)

1. **Initial publication** — `git init`, initial commit, push to `jaetill/agentic-dev-environment` (private to start). Immediately update each of the three projects' `.claude/settings.json` to swap the directory source for the GitHub source — fixes the absolute-path single-machine dep.
2. **Phases 1-4 self-adoption** — apply documentation, AI configuration (the workspace already IS the plugin source, so this is just enabling reviewer agents on workspace PRs), quality gates, CI workflows.
3. **release-please for the plugin** — versioned platform releases so projects can pin (`@v1` rather than `@main`).

Step 1 has the highest leverage: it removes the load-bearing absolute path that currently lives in three projects.

## What's worth thinking about NOW (Jason's "thoughts I can read now")

- **The platform is currently an internal product without an internal customer.** Self-application changes that. The workspace becomes the platform's first user. Useful for catching the "this is hard to use" smells.
- **Versioning matters more than it seems.** Today, "platform v0.1" exists conceptually but not as a tag. As soon as you have a release-please flow on the workspace, every breaking change is visible. That changes the calculus on how/when to make breaking changes to agents, hooks, settings.json.
- **Open question:** should the workspace be PUBLIC on GitHub? Arguments for: portfolio piece, gets feedback, models good practice. Arguments against: exposes solo-dev quirks, doesn't gain you anything if there are no other users. Probably private to start; revisit when there's something polished worth showing.
- **The MCP/plugin angle.** If the platform becomes an MCP server or a Claude Code plugin, "applying the platform to itself" gets a clean answer: the platform IS the agent registry; the workspace just holds the registry. That's the outer-team model again, just phrased as a distribution mechanism. So TODO_platform_architecture_review interacts here.

## Drop the topic now per Jason's instruction; resume later.
