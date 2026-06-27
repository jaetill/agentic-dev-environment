---
paths:
  - "docs/adr/**"
  - "docs/standards/**"
---

# ADR & standards authoring

- **Draft ADRs from [`docs/adr/template.md`](../../docs/adr/template.md), never freehand.** The template carries the sections the checker enforces (`Considered Options`, `Pros and Cons of the Options`). A fast ADR that skips them freezes the fleet's merges hours later (the 2026-06-02 and 2026-06-05 freezes had this anatomy: a non-conforming ADR on `main` reddened every subsequent PR because `validate`/`adr-format-check` run against the whole tree).
- **ADRs with `Status: Ratified` or `Implemented` must carry an `- **Implementation:**` line** — enforced by `adr-format-check` (PR #362). The ratification-without-implementation gap is the silent failure that produced 2026-06-10's auto-merger inconsistency.
- **Don't write a standards doc without the matching ADR**, and don't ship a standard that hasn't been decided — placeholder pages are fine; fabricated content isn't.
- **Use the canonical glossary at [`docs/standards/00-terminology.md`](../../docs/standards/00-terminology.md)** as the source of truth for fleet-specific terms. When you retire a term, update the glossary first, then sweep operational files (workflows, scripts, agent prompts) for stale references in the same PR.
