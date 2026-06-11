# Standard 00 — Terminology

**ADR:** [ADR-0046](../adr/0046-fleet-terminology-glossary.md)

The canonical names this fleet uses for its moving parts. When code, ADRs, runbooks, and standards disagree about what to call something, the loop drifts. This doc is the single source of truth.

`terminology-check` (see `scripts/terminology-check.sh`) enforces that deprecated terms don't reappear in operational files after they've been retired.

## Why this exists

Every session lately has hit some flavor of: "the workflow says `app/claude` but the ADR says `app/jaetill-ai-triage-team` and the runbook says `claude[bot]`." Each is right at *some* point in time; none was current. Six places to update, each can drift independently, none has authority over the others.

This standard makes one place authoritative. The check turns drift from "discovered weeks later in production" into "fails CI on the PR that introduces it."

## Active terms

| Term | Canonical value | Defined by | Last reaffirmed |
|---|---|---|---|
| Fleet App slug | `jaetill-ai-triage-team` | ADR-0020, ADR-0041 | 2026-06-10 |
| Fleet App bot login (REST API form) | `jaetill-ai-triage-team[bot]` | ADR-0041 | 2026-06-10 |
| Fleet App bot login (`gh` CLI form) | `app/jaetill-ai-triage-team` | ADR-0041 | 2026-06-10 |
| Implementer commit author | `claude[bot]` (set by `git config user.name` in `claude-implementer-reusable.yml`) | ADR-0034 | 2026-06-10 |
| Implementer PR creator | The fleet App (via App installation token minted in `claude-implementer-reusable.yml` manual-dispatch job) | ADR-0041 | 2026-06-10 |
| Auto-merger filter source | `.github/workflows/triage-scan.yml` auto-merge job, jq predicate around line 395 | ADR-0021 (filter), ADR-0041 (identity) | 2026-06-10 |
| Autonomous window — overnight | 01:00–04:00 America/Chicago, daily | ADR-0017 | 2026-06-10 |
| Autonomous window — work-hours | 09:00–12:00 America/Chicago, Mon–Fri | ADR-0017 | 2026-06-10 |
| Merge-when-green sweep cron | `15,45 * * * *` (all-day) | ADR-0044 §3 | 2026-06-10 |
| Hold-label prefix | `hold:` (e.g. `hold:adr`, `hold:compositional`, `hold:iac-unverified`) | ADR-0044 | 2026-06-10 |

When a row's canonical value changes, update this doc *first*, then update every consumer, then drop the old value to *Deprecated* below. The PR doing the swap is the one place where they can all change together.

## Deprecated terms

These had a canonical role at some point but have been superseded. They may still appear in **historical contexts** — ADR amendments that record the change, runbook history blocks, this glossary. Their use in **operational contexts** (live workflows, current standards docs other than this one, agent prompts that drive behavior, scripts) is forbidden by `terminology-check`.

| Deprecated | Replaced by | When | Replacement ADR | Allowed contexts |
|---|---|---|---|---|
| `app/claude` (as implementer PR author) | `app/jaetill-ai-triage-team` | 2026-06-10 | ADR-0041 | `docs/adr/`, `docs/runbooks/`, this glossary, commit messages, PR descriptions |
| `IMPLEMENTER_PAT` (as the implementer's git auth secret) | Fleet App installation token (minted at run-time) | 2026-06-10 | ADR-0041 | `docs/adr/`, `docs/runbooks/`, this glossary, commit messages, PR descriptions |
| `claude[bot]` (as implementer PR author — distinct from commit author, which is still `claude[bot]`) | `jaetill-ai-triage-team[bot]` | 2026-06-10 | ADR-0041 | `docs/adr/`, `docs/runbooks/`, this glossary, commit messages, PR descriptions |

**Operational contexts** for the purpose of this check: `.github/workflows/`, `scripts/`, `plugins/ai-team/agents/`, `docs/standards/*.md` *except* this glossary, the implementer's own prompts.

**Allowed contexts** for historical references: `docs/adr/`, `docs/runbooks/`, this glossary, commit messages, PR descriptions. (The check doesn't read commit messages or PR descriptions; the exclusion is by file path.)

**Inline exception:** an operational file that legitimately needs to mention a deprecated term (e.g. a code comment explaining what the term *used* to mean) can add a marker anywhere in the 5 lines preceding the match:

```
# terminology-check: deprecated-app-claude-ok-here
# This comment block explains the legacy filter we replaced.
# The old form was app/claude before ADR-0041.
echo "old form was app/claude before ADR-0041"
```

The marker must name the specific deprecated term to suppress. The 5-line window covers the natural case of a multi-line comment block whose only marker is at the block's start. Bulk-suppression markers and file-level suppressions aren't permitted.

## Adding a new deprecation

When you retire a term:

1. Add a row to the *Deprecated* table here with the date, replacement, replacement ADR, and allowed-contexts list.
2. Add the term to `scripts/terminology-check.sh` (in the deprecated-terms list with its allowed contexts).
3. In the same PR, sweep the operational files for the old term and update them. The check now catches anything you missed.
4. Bump the *Last reaffirmed* date on the new canonical row in the Active table.

The check failing on your own PR after step 3 means there's a reference you forgot. The point of the check is to surface that.

## What this does NOT do

- Does not catch terminology drift in narrative prose (the runbook saying "claude[bot] used to be the author" is fine).
- Does not enforce that ALL terms must be in this glossary — only that the listed deprecated terms don't leak into operational files.
- Does not validate that the canonical value listed here matches the actual current value in code (that's what `terminology-check` would do if we added a positive-match mode; not implemented in V1).
