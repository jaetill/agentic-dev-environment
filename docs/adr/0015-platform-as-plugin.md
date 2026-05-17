# ADR-0015: Package the Agentic Dev Environment platform as a Claude Code plugin

- **Status:** Proposed
- **Date:** 2026-05-16
- **Deciders:** Jason Tilley (with AI architectural review)
- **Tags:** ai-workflows, distribution, plugin, claude-code

## Context and Problem Statement

The platform's agents, hooks, commands, and standards have to date been distributed by **embedding copies** in each consuming project's `.claude/` directory. Each new project incurs a ~3-hour port; updates to the canonical `templates/_shared/claude/` require manually fan-out to every project. The model assumes a templating tool we don't have, and in practice produces silent divergence (game-night-pwa, meal-planner, ai-teacher already drift in small ways from each other and from canonical).

`TODO_platform_architecture_review.md` (captured 2026-05-15) and `PLAN_hybrid_agent_refactor.md` (captured 2026-05-16 after web research) — both consumed and removed after ratification — documented the question: should this stay embedded, move to `~/.claude/` global subagents, or adopt Anthropic's plugin system?

How should the platform be distributed across multiple projects, given that Anthropic now ships a first-class plugin + marketplace system?

## Decision Drivers

- **Reduce per-project adoption cost.** 3-hour port → ~10 minutes.
- **Eliminate silent drift.** One canonical source, version-pinned.
- **Match Anthropic's direction.** Plugins are now the documented mechanism for shared agents/hooks/skills across projects (per https://code.claude.com/docs/en/plugins).
- **Preserve project-specific extensions.** Some projects have legitimate per-project agents, hooks, or skills (meal-planner has 3 custom hooks; ai-teacher has a custom skill). Those must coexist.
- **Path to version pinning.** Today the platform has no versioning surface. Plugins give us `version` in manifest + cache-aware updates.
- **Solo-dev pragmatism.** No team to negotiate with; can adopt a slightly newer feature ahead of "settled" tooling.

## Considered Options

- **Option A: Stay embedded.** Continue copy-into-project model, possibly with a sync script.
- **Option B: Global subagents under `~/.claude/`.** Move all canonical files to user home. Projects override per-file by placing same-named files in their `.claude/`.
- **Option C: Package as Claude Code Plugin distributed via a local Marketplace.** The workspace IS a marketplace; the plugin lives at `plugins/ai-team/`; projects subscribe via `.claude/settings.json`.
- **Option D: GitHub Agentic Workflows.** Move CI agents to GHAW; keep local agents embedded.

## Decision Outcome

Chosen option: **Option C** (Claude Code Plugin + local marketplace), because it is Anthropic's documented mechanism for exactly this use case, supports version pinning via manifest, gives a clean upgrade path (workspace → GitHub published marketplace → versioned releases), and preserves the override pattern via project-specific files in each project's `.claude/`.

## Consequences

### Positive

- **One canonical source.** `plugins/ai-team/` is THE definition of the platform's agents/hooks/commands/skills.
- **~30-minute project adoption** instead of 3 hours. Run two CLI commands, add a marketplace subscription block to `.claude/settings.json`, done.
- **Version pinning.** `plugin.json` declares `version`; consumers stay on a known version until they upgrade.
- **Drift detection by construction.** Projects can no longer drift from the platform's agents/hooks (those files literally don't exist in the project anymore — the plugin provides them at runtime). Project-specific overrides remain visible because they're the ONLY `.claude/agents/*` files in the repo.
- **Skills as first-class.** The plugin format makes skills loadable. The standards docs become 11 invokable skills, plus the 9 stack-knowledge skills extracted in this work (nextjs-turbopack, vite-tailwind4, etc.).
- **Update path is `claude plugin update`** rather than manual file copy.
- **Aligned with Anthropic's direction.** Future improvements to plugin tooling (versioning, dependency constraints, marketplace UX) we get for free.

### Negative

- **Slash commands are now namespaced.** `/review` becomes `/ai-team:review`. The plugin was named `ai-team` (rather than `agentic-dev-environment`, which is the workspace/repo name) specifically to keep this prefix terse.
- **`permissions` block can't ship via plugin.** Anthropic's plugin manifest `settings.json` only accepts `agent` and `subagentStatusLine` keys. Each subscribing project must still carry its own `permissions.deny` block. Mitigated by: keep the canonical block in this ADR + plugin README; projects copy-paste it once.
- **Plugin spec is newer than the alternative.** Some plugin features will evolve. We're an early adopter.
- **Dependency on Anthropic's evolution.** If they change the plugin format we have a migration to do.
- **Hook scripts run from cache directory.** They must use `${CLAUDE_PLUGIN_ROOT}` in `hooks.json` paths. Scripts that internally reference `.claude/audit.log` continue to work because cwd is still the project, not the plugin cache.
- **Local marketplace path is machine-specific.** Until the workspace is published to GitHub, `extraKnownMarketplaces` in each project's `.claude/settings.json` carries an absolute Windows path. Not portable to teammates or CI runners. Mitigated by: publishing the workspace as `jaetill/agentic-dev-environment` on GitHub (separate work, captured in TODO_apply_platform_to_itself.md), at which point the source becomes `{"source": "github", "repo": "jaetill/agentic-dev-environment"}` and is portable.

### Neutral

- **The `templates/_shared/claude/` directory becomes redundant** once the plugin migration is fully landed. Keep it as the historical source for one or two releases, then delete. Until then it's the input to the plugin; the plugin is the output.
- **The Phase 1 categorization analysis is no longer load-bearing** once this ADR is accepted. The categorization captured the decisions that produced this ADR; the canonical record is now this ADR plus the plugin layout itself.
- **GitHub Agentic Workflows (Option D) is orthogonal**, not foreclosed. Adopting plugins doesn't prevent moving CI agents to GHAW later.

## Pros and Cons of the Options

### Option A: Stay embedded

- ✅ Pro: No migration. Status quo works.
- ❌ Con: 3-hour port per project; drift inevitable.
- ❌ Con: No version surface; can't pin or upgrade.
- ❌ Con: Diverges from Anthropic's published direction.

### Option B: Global subagents under `~/.claude/`

- ✅ Pro: Simple. No new tooling required.
- ❌ Con: No version pinning — `~/.claude/agents/` is a single mutable state.
- ❌ Con: Less portable across machines; setup requires manual file placement on each new dev machine.
- ❌ Con: Doesn't address hooks (which must be configured per-project to fire at all).
- ❌ Con: Doesn't address slash commands.

### Option C: Plugin + local marketplace (chosen)

- ✅ Pro: Anthropic's canonical mechanism — explicit support, ongoing evolution.
- ✅ Pro: Version pinning via manifest + cache-aware updates.
- ✅ Pro: Covers agents, hooks, commands, and skills in one mechanism.
- ✅ Pro: Project subscription is a few lines in `.claude/settings.json`.
- ❌ Con: Slash commands namespaced (verbose).
- ❌ Con: Permissions block can't ship via plugin; projects still carry one.
- ❌ Con: Local marketplace path is absolute until workspace is published.

### Option D: GitHub Agentic Workflows

- ✅ Pro: Solves CI shipping authority (separate decision worth making).
- ❌ Con: Doesn't address local agent distribution (orthogonal problem).
- → Defer to a separate ADR.

## Implementation notes

- **Plugin lives at:** `plugins/ai-team/`
- **Marketplace defined at:** `.claude-plugin/marketplace.json` at workspace root (marketplace name: `agentic-dev-environment`; plugin name: `ai-team`)
- **Plugin manifest at:** `plugins/ai-team/.claude-plugin/plugin.json`
- **Components:** 14 agents, 10 commands, 12 hooks (incl. `hooks.json`), 31 skills (11 standards-* + 9 stack-knowledge + plugin-internal)
- **Subscribing projects:** game-night-pwa (merged 2026-05-16, master 0640775), meal-planner (merged 2026-05-16, master 35b3b14), ai-teacher (merged 2026-05-16, main 3fca8a9). All three migration PRs landed same day; rename to `ai-team` followed in chore PR #7 (meal-planner) and equivalent commits on each project's migration branch.
- **Affected memories:**
  - `reference_platform_application_procedure.md` — replaced (new procedure is two commands)
  - `project_platform_port_state.md` — updated to reflect plugin migration

## Links

- [Anthropic plugins docs](https://code.claude.com/docs/en/plugins) — the canonical reference.
- [Plugin marketplaces docs](https://code.claude.com/docs/en/plugin-marketplaces) — local marketplace and source-type reference.
- [Plugins reference (schemas)](https://code.claude.com/docs/en/plugins-reference) — manifest, hooks.json, agent frontmatter.
- `TODO_platform_architecture_review.md` (consumed and removed) — the question this ADR answers.
- `PLAN_hybrid_agent_refactor.md` (consumed and removed) — the earlier draft that proposed global subagents (Option B).
- [TODO_apply_platform_to_itself.md](../../TODO_apply_platform_to_itself.md) — the related dogfooding decision that becomes easier after this ADR.
- ADR-0011 — original AI workflows decision; this ADR extends the distribution mechanism without changing the agent roster or hook policy.
