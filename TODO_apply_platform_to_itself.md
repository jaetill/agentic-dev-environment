# TODO: Apply platform to itself — mostly done

**Captured:** 2026-05-15 evening.
**Reframed:** 2026-05-16 after the plugin migration (ADR-0015) landed.
**Refreshed:** 2026-05-19 — the bulk of this work has landed. What remains is small.

## Status — what landed

| Item | Status |
|---|---|
| `git init` + initial commit | ✅ Done. Workspace is on GitHub at `jaetill/agentic-dev-environment`. |
| Publish to GitHub | ✅ Done. Repo live; PRs merging routinely. |
| Eliminate absolute-path single-machine dep | ✅ Done. All 8 subscribing projects use `{"source": "github", "repo": "jaetill/agentic-dev-environment"}` in their `.claude/settings.json`. |
| Phase 1 — Documentation | ✅ Done. `docs/adr/` (16 ADRs), `docs/standards/` (11 standards), `docs/runbooks/`, `docs/reviews/` all present. |
| Phase 2 — AI configuration | ✅ Done. The workspace IS the plugin source (`plugins/ai-team/`), and `.claude/` is wired. |
| Phase 3 — Quality gates | ✅ Done. `validate-platform.yml` runs `adr-format-check`, `agent-frontmatter-check`, `link-check` on every PR. |
| Phase 4 — CI workflows | ✅ Done. 19 workflows present: `claude-pr-review.yml`, `claude-implementer.yml`, `release-please.yml`, `validate-platform.yml`, `test-modules-plan.yml`, `test-modules-integration.yml`, etc. |
| `release-please` setup | ✅ Done (PR #9, 2026-05-19). Config + workflow live; bumps `plugins/ai-team/.claude-plugin/plugin.json` via `extra-files`. |
| Sentry hook bug fix that motivated this exercise (exec bits) | ✅ Done (PR #11, 2026-05-19). |
| Agent-definition audit | ✅ Done (PR #13, 2026-05-19). `docs/reviews/2026-05-19-agent-definition-audit.md`. |

## Outstanding work

### 1. Cut the first release (low effort, real signal)

`release-please` is set up but no release exists. The next conventional-commit push to `main` should open a release PR automatically. Since merge-then-release-PR has been the cadence, the release PR is probably already open — verify and merge it. After that, projects can pin against `@v0.1.0` (or whatever release-please chooses) instead of `@main`.

**Check:** `gh pr list --search "release-please"` on this repo.

### 2. Verify `claude-pr-review` actually triggers on workspace PRs

PR #13's check list showed `validate`, `adr-format-check`, `agent-frontmatter-check`, `link-check`, `module-plan-tests`. **No `claude-pr-review`.** Either:

- It's configured but path-filtered to not trigger on agent-definition changes (possibly correct — reviewer doesn't need to review reviewer prompts);
- Or it's not wired to fire on this workspace's PRs at all.

Skim `.github/workflows/claude-pr-review.yml` to confirm intent. If the intent is "review every PR," fix the trigger. If the intent is "review only application-code PRs," document the carve-out.

### 3. Verify `test-inbox` JS tests actually run in CI

`templates/_shared/test-inbox/` has a Vitest config and tests. The `ci-typescript.yml` workflow is present, but I haven't verified it actually runs the test-inbox suite on workspace PRs. If it doesn't, a breaking change to `test-inbox` would silently propagate to the 3 projects that depend on it via `file:` paths.

**Check:** look at `ci-typescript.yml` paths filter; trigger a no-op PR touching `templates/_shared/test-inbox/`.

## Decisions deferred

- **Public vs private repo.** Currently private. Arguments for public: portfolio piece, gets feedback, models good practice. Arguments against: exposes solo-dev quirks. Revisit when there's something polished worth showing — probably after first tagged release.
- **Versioning cadence.** After first release, decide whether to pin projects against the version tag (`@v0.1.0`) or stay on `@main`. Pinning gives stability; `@main` gives free updates. Likely mixed: critical projects pin, exploratory ones float.

## What this exercise actually proved

The "apply the platform to itself" framing turned out to be self-fulfilling. Once the plugin lived in this workspace and the workspace had CI, every fix the platform's agents recommended for OTHER projects became immediately applicable to this workspace too. The PR #11 hook executable-bit fix would not have been caught without an external user; that's an example of the kind of bug self-application alone wouldn't catch. So self-application is necessary-but-not-sufficient.

## Reference

- [ADR-0015](docs/adr/0015-platform-as-plugin.md) — the distribution-mechanism decision this work falls out of.
- [docs/reviews/2026-05-19-agent-definition-audit.md](docs/reviews/2026-05-19-agent-definition-audit.md) — the audit that proved the self-application is working.
- `reference_platform_application_procedure.md` (memory) — the procedure being dogfooded.
