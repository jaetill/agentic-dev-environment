# Fleet Terminology Glossary

**Status:** 🟩 Live  
**ADR:** [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) (Fleet App write-identity decisions)  
**Last reaffirmed:** 2026-06-18

Canonical reference for fleet-specific identifiers, names, and secrets. When a term is retired, move it to the Deprecated table and sweep operational files for stale references in the same PR.

> **CI enforcement:** `terminology-check` runs in the `validate` job and blocks PRs that reintroduce deprecated terms in operational files (`scripts/`, `.github/workflows/`, `plugins/ai-team/agents/`). Sweeps for stale terms must still be performed manually when a new deprecation is added.

## Canonical terms

| Term | Kind | Value / Pattern | Notes | ADR |
|---|---|---|---|---|
| Fleet App slug | GitHub App name | `jaetill-ai-triage-team` | Owner-controlled first-party App that drives dispatch, merge, and the implementer's write path. | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| Implementer bot identity | GitHub actor | `jaetill-ai-triage-team[bot]` | GitHub actor that opens implementer PRs and pushes code. Used in author-keyed filters (auto-merge, cockpit panels). | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| Implementer author filter | `gh` / GraphQL filter | anchored: `^(app/)?jaetill-ai-triage-team(\[bot\])?$` | Matches BOTH `gh` serializations (`app/jaetill-ai-triage-team` from older CLI, `jaetill-ai-triage-team[bot]` from newer) while REJECTING App-slug-substring spoofs like `jaetill-ai-triage-team-staging` (#355). The auto-merger and Mode B fix-iteration both use this anchored `test(...)` form — a bare substring `test("jaetill-ai-triage-team")` is the deprecated, spoofable predecessor; do not reintroduce it. | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| Implementer auth secrets | GitHub Secrets | `FLEET_APP_ID` + `FLEET_APP_PRIVATE_KEY` | Mint per-run installation tokens for the fleet App. Primary auth path for implementer pushes and cross-repo dispatches. (`CLAUDE_CODE_OAUTH_TOKEN` remains the OAuth token for claude-code-action review runs.) | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |

## Deprecated terms

Do not reintroduce these in new operational files (workflows, scripts, agent prompts). Historical references in ADRs and comments documenting old behaviour are permitted — suppress the `terminology-check` CI gate by adding `# terminology-check: deprecated-<slug>-ok-here` on any of the 5 lines preceding the deprecated term, where `<slug>` is the term's slug from the table above (e.g. `deprecated-app-claude-ok-here`). The inline-exception window is 5 lines, so a marker at the top of a short comment block covers the reference below it.

| Deprecated term | Slug | Kind | Replaced by | Deprecated | ADR |
|---|---|---|---|---|---|
| `app/claude` | `app-claude` | GitHub author identity | `app/jaetill-ai-triage-team` / `jaetill-ai-triage-team[bot]` | 2026-06-10 | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| `IMPLEMENTER_PAT` | `implementer-pat` | GitHub Secret (primary implementer auth) | `FLEET_APP_ID` + `FLEET_APP_PRIVATE_KEY` | 2026-06-10 | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| `claude[bot]` as implementer write identity | `claude-bot` | GitHub actor | `jaetill-ai-triage-team[bot]` | 2026-06-10 | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |

**Notes on still-present legacy uses:**

- `IMPLEMENTER_PAT` — fully retired (#363). All usages were removed (PR #526), and the reusable's `workflow_call` secret declaration plus every fleet caller's forwarding were removed in #363 phase B. `terminology-check` now enforces it as a hard error. The remaining step is deleting the secret from each repo's settings (maintainer action).
- `claude[bot]` — the Claude GitHub App (`claude[bot]`) remains active as the *reviewer* identity (code-reviewer, security-reviewer, etc. via `CLAUDE_CODE_OAUTH_TOKEN`). Only its role as the *implementer's write identity* is deprecated. `claude[bot]` in a review workflow is not stale usage.
