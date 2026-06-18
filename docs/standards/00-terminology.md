# Fleet Terminology Glossary

**Status:** 🟩 Live  
**Backed by:** [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) (Fleet App write-identity decisions)  
**Last reaffirmed:** 2026-06-18

Canonical reference for fleet-specific identifiers, names, and secrets. When a term is retired, move it to the Deprecated table and sweep operational files for stale references in the same PR.

> **CI enforcement:** a `terminology-check` gate that blocks PRs reintroducing deprecated terms in operational files is not yet wired into CI. Until it is, deprecated-term sweeps are manual — apply the same discipline proactively.

## Canonical terms

| Term | Kind | Value / Pattern | Notes | ADR |
|---|---|---|---|---|
| Fleet App slug | GitHub App name | `jaetill-ai-triage-team` | Owner-controlled first-party App that drives dispatch, merge, and the implementer's write path. | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| Implementer bot identity | GitHub actor | `jaetill-ai-triage-team[bot]` | GitHub actor that opens implementer PRs and pushes code. Used in author-keyed filters (auto-merge, cockpit panels). | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| Implementer author filter | `gh` / GraphQL filter | `app/jaetill-ai-triage-team` **or** `jaetill-ai-triage-team[bot]` | Older `gh` CLI versions render the bot login as `app/jaetill-ai-triage-team`; newer versions use `jaetill-ai-triage-team[bot]`. The auto-merger uses `test("jaetill-ai-triage-team")` to match both. | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| Implementer auth secrets | GitHub Secrets | `FLEET_APP_ID` + `FLEET_APP_PRIVATE_KEY` | Mint per-run installation tokens for the fleet App. Primary auth path for implementer pushes and cross-repo dispatches. (`CLAUDE_CODE_OAUTH_TOKEN` remains the OAuth token for claude-code-action review runs.) | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |

## Deprecated terms

Do not reintroduce these in new operational files (workflows, scripts, agent prompts). Historical references in ADRs and comments documenting old behaviour are permitted — annotate them with `# deprecated-ref: <reason>` when the surrounding file is operational so the intent is clear.

| Deprecated term | Kind | Replaced by | Deprecated | ADR |
|---|---|---|---|---|
| `app/claude` | GitHub author identity | `app/jaetill-ai-triage-team` / `jaetill-ai-triage-team[bot]` | 2026-06-10 | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| `IMPLEMENTER_PAT` | GitHub Secret (primary implementer auth) | `FLEET_APP_ID` + `FLEET_APP_PRIVATE_KEY` | 2026-06-10 | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |
| `claude[bot]` as implementer write identity | GitHub actor | `jaetill-ai-triage-team[bot]` | 2026-06-10 | [ADR-0041](../adr/0041-fleet-app-single-write-identity.md) |

**Notes on still-present legacy uses:**

- `IMPLEMENTER_PAT` — still appears in reusable workflows as a legacy fallback (`${{ secrets.IMPLEMENTER_PAT || github.token }}`). The fallback is intentional for backwards compatibility until all app repos migrate. Do not use it as the *primary* auth route in new workflows.
- `claude[bot]` — the Claude GitHub App (`claude[bot]`) remains active as the *reviewer* identity (code-reviewer, security-reviewer, etc. via `CLAUDE_CODE_OAUTH_TOKEN`). Only its role as the *implementer's write identity* is deprecated. `claude[bot]` in a review workflow is not stale usage.
