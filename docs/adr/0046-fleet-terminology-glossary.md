# ADR-0046: Fleet terminology glossary and deprecated-term check

- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Jason Tilley
- **Tags:** governance, ci-cd, ai-workflows, terminology

> **Format:** MADR 4.x with the platform's three extensions.

## Context and Problem Statement

Every session lately surfaces a flavor of: "the workflow says `app/claude` but the ADR says `app/jaetill-ai-triage-team` and the runbook says `claude[bot]`." Each reference was correct at *some* point in time; none is current. The result is silent drift — six places reference the old value, the ADR retires the term, and the inconsistency only surfaces weeks later when something breaks.

How do we make deprecated fleet terms visible at the point of reintroduction instead of weeks later in production?

## Decision Drivers

- Terminology drift between ADRs, workflow files, agent prompts, and runbooks has caused real incidents (wrong filter in auto-merger, broken dispatch identity after ADR-0041).
- The current process relies on individual authors remembering that a term was retired — no machine enforcement.
- Historical references to deprecated terms are legitimate (ADR amendment prose, runbook history) — the check must allow them without requiring mass edits.
- A point-in-time glossary decays without a keeper; the check must force the glossary to be updated before any retirement takes effect.

## Considered Options

- **Option A: Canonical glossary doc + CI check against operational files (chosen)** — a single `docs/standards/00-terminology.md` is the source of truth; `scripts/terminology-check.sh` runs on every PR and flags deprecated terms in operational files (`.github/workflows/`, `scripts/`, `plugins/ai-team/agents/`).
- **Option B: Inline comments only** — authors add `# deprecated:` comments near each retired term; no central registry.
- **Option C: No enforcement** — rely on manual review and ADR reading.

## Decision Outcome

Chosen option: **Option A**, because it puts the enforcement at merge time (where it is cheapest to fix), separates historical/operational contexts via file-path allowlists, and the inline-exception marker lets a file legitimately mention a deprecated term without a blanket file-level suppression.

## Consequences

### Positive

- Deprecated terms are caught on the PR that reintroduces them, not weeks later.
- The glossary is the single source of truth — dashboard queries, agent prompts, and runbooks can all cite it.
- The allowed-contexts allowlist means historical ADR prose and runbook history blocks never need suppression markers.

### Negative

- Authors must update the glossary *before* retiring a term in an ADR, adding one step to the ADR workflow.
- The check only covers operational files explicitly listed in `OPERATIONAL_GLOBS`; narrative prose in runbooks is out of scope (doc-keeper covers that).

### Neutral

- PRs that legitimately reference a deprecated term in an operational context (e.g., a comment explaining the legacy path) need an inline `# terminology-check: deprecated-<slug>-ok-here` marker.

## Pros and Cons of the Options

### Option A: Canonical glossary + CI check (chosen)

- ✅ Machine-enforced at merge time
- ✅ Central source of truth, queryable and linkable
- ✅ Inline-exception marker handles legitimate operational references without file-level suppression
- ❌ Requires glossary update before retiring a term

### Option B: Inline comments only

- ✅ No new files
- ❌ No central registry — still need to grep everywhere to find all uses
- ❌ No enforcement at merge time

### Option C: No enforcement

- ✅ Zero overhead
- ❌ Drift is discovered in production, not at merge

## Implementation notes

- Standards doc: `docs/standards/00-terminology.md`
- Check script: `scripts/terminology-check.sh`
- CI job: `terminology-check` in `.github/workflows/validate-platform.yml`
- Initial deprecated terms per ADR-0041: `app/claude` (superseded by `app/jaetill-ai-triage-team`) and `IMPLEMENTER_PAT` (superseded by the fleet App installation token)
- **Implementation:** Implemented 2026-06-11 via #370

## Links

- ADR-0041 — fleet App single-write identity (source of the initial deprecated terms)
- ADR-0026 — agent review pipeline (agent files are an operational context covered by the check)
