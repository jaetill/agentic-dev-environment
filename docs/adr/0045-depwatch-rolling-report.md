# ADR-0045: The dep-watch digest is a rolling file, not a perpetual issue

- **Status:** Accepted — Jason chose the rolling-file option 2026-06-03; activation directed 2026-06-05 after the label-system work (ADR-0044 deliberately did not model `dep-watch`)
- **Date:** 2026-06-05
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, dependencies, signal-to-noise

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Extends [ADR-0027](0027-dep-watch-tier2.md)-era behavior; the dep-watcher's *triage* duties are unchanged — only the digest's medium moves.

## Context and Problem Statement

Each repo's weekly dep-watch run maintained a standing "Weekly dependency report" issue, edited in place forever. A never-closeable issue offends the backlog's hygiene (the human is a completionist; an issue that cannot reach zero is noise), pollutes issue counts and label queries, and required its own cockpit row just to say "1 per repo, as always."

## Decision Outcome

The digest becomes **`docs/dependency-report.md` on the unprotected `reports/dep-watch` branch** of each repo — rewritten wholesale each weekly run (rolling: latest state only; history is the branch's commit log). No PR, no review battery, no merge gate: it is information, not change. The 7 standing digest issues are closed; the `dep-watch` label retires with them (it was deliberately left out of ADR-0044's type axis). Actionable findings (CVEs, EOL packages, major bumps) are untouched — those were always separate `severity:*` issues entering the implementer backlog.

## Consequences

Positive: zero perpetual issues; digest history becomes `git log`; one less label dialect; the cockpit's dep-watch row retires. Negative: the report is one click further away (a branch file, not an issue) — acceptable for a read-only info sink. **Verify on the next Monday run** that each repo's first rolling write lands (new `contents: write` permission + branch creation are first-exercised then).

## Implementation notes

- 7 × `claude-dep-watcher.yml` prompt block rewritten + `contents: write` added (PRs auto-merged per repo).
- 7 standing digest issues closed with pointers.
- Cockpit dep-watch row (header + 8 stats) removed.
