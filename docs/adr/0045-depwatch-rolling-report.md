# ADR-0045: The dep-watch digest is a rolling file, not a perpetual issue

- **Status:** Accepted — Jason chose the rolling-file option 2026-06-03; activation directed 2026-06-05 after the label-system work (ADR-0044 deliberately did not model `dep-watch`)
- **Date:** 2026-06-05
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, dependencies, signal-to-noise

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR. Extends [ADR-0027](0027-dep-watcher-autonomous-backlog.md)-era behavior; the dep-watcher's *triage* duties are unchanged — only the digest's medium moves.

## Context and Problem Statement

Each repo's weekly dep-watch run maintained a standing "Weekly dependency report" issue, edited in place forever. A never-closeable issue offends the backlog's hygiene (the human is a completionist; an issue that cannot reach zero is noise), pollutes issue counts and label queries, and required its own cockpit row just to say "1 per repo, as always."

## Decision Drivers

- The backlog must be able to reach zero open issues — a perpetual issue is permanent noise.
- The digest is *information, not change*: it should not consume issue counts, label queries, review, or merge gates.
- Latest state must stay easy to read, and history should be cheap to keep.
- Actionable findings (CVEs, EOL, major bumps) must remain separate `severity:*` issues entering the implementer backlog — unaffected by where the digest lives.

## Considered Options

- **Rolling file on a `reports/dep-watch` branch** — the digest is `docs/dependency-report.md`, rewritten each run; history is the branch's commit log.
- **Keep the perpetual per-repo issue** — one standing "Weekly dependency report" issue edited in place forever (the status quo).
- **A fresh issue each week, auto-closing the prior** — closeable, but churns the backlog and notification stream weekly.

## Decision Outcome

Chosen option: **rolling file on a `reports/dep-watch` branch**, because it makes the informational digest reach zero open issues without weekly churn, while keeping the latest state one fetch away and its history in `git log`.

### Pros and Cons of the Options

**Rolling file on a `reports/dep-watch` branch**
- Good: zero perpetual issues; the backlog can reach zero; history is the commit log; no label/cockpit-row overhead.
- Good: it is information, not change — no PR or review battery is warranted.
- Bad: the report is one click further away (a branch file, not an issue in the default view).

**Keep the perpetual per-repo issue**
- Good: maximally discoverable (shows in the default issue list).
- Bad: a never-closeable issue pollutes counts and label queries and needs its own cockpit row; offends backlog hygiene.

**A fresh issue each week, auto-closing the prior**
- Good: each issue is closeable.
- Bad: weekly open/close churn in the backlog and notifications for a read-only info sink.

## Decision detail

The digest becomes **`docs/dependency-report.md` on the unprotected `reports/dep-watch` branch** of each repo — rewritten wholesale each weekly run (rolling: latest state only; history is the branch's commit log). No PR, no review battery, no merge gate: it is information, not change. The 7 standing digest issues are closed; the `dep-watch` label retires with them (it was deliberately left out of ADR-0044's type axis). Actionable findings (CVEs, EOL packages, major bumps) are untouched — those were always separate `severity:*` issues entering the implementer backlog.

## Consequences

Positive: zero perpetual issues; digest history becomes `git log`; one less label dialect; the cockpit's dep-watch row retires. Negative: the report is one click further away (a branch file, not an issue) — acceptable for a read-only info sink. **Verify on the next Monday run** that each repo's first rolling write lands (new `contents: write` permission + branch creation are first-exercised then).

## Implementation notes

- 7 × `claude-dep-watcher.yml` prompt block rewritten + `contents: write` added (PRs auto-merged per repo).
- 7 standing digest issues closed with pointers.
- Cockpit dep-watch row (header + 8 stats) removed.
