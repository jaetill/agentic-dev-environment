# Architecture Decision Records

This project's ADRs (project-specific decisions). Platform-wide ADRs live in the [Agentic Dev Environment](https://github.com/{{github_username}}/agentic-dev-environment/tree/main/docs/adr) repo and govern this project unless overridden by an ADR here.

## Format

All ADRs follow MADR 4.x with three documented extensions per the platform's [ADR-0008](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0008-documentation.md):

1. Neutral consequences (third bucket)
2. Implementation notes (separate section)
3. Bundled sub-decisions (when tightly coupled)

ADR template: copied from the platform's `docs/adr/template.md` at scaffold time.

## When to write a project-level ADR

Per platform [ADR-0008](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0008-documentation.md) §2:

- **Always**: any change in one of the 5 ADR-gated categories (per platform ADR-0003).
- **Always**: any deviation from a platform standard.
- **Strongly recommended**: any decision where future-you would reasonably ask "why was this done this way?"
- **Not needed**: routine bug fixes, refactors that don't change architecture, dep version bumps.

## Index

(ADRs accumulate here. Empty until the first one is written.)
