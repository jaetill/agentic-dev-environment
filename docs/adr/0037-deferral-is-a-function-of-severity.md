# ADR-0037: Deferral is a function of severity — retire the `deferred-until-adjacent` label

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, agents, signal-to-noise

> **Format:** MADR 4.x with the platform's bundled-sub-decision extension. Amends [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) Rule 2 (deferral policy) and adjusts the label-keyed mechanics in [ADR-0028](0028-nit-sweep-only-on-active-cycles.md) and [ADR-0029](0029-promoter-owns-nit-adjacency.md). The deferral *behavior* (don't fix low-value findings in isolation; bundle opportunistically; drain via the active-cycle sweep) is unchanged — only its *encoding* changes.

## Context and Problem Statement

ADR-0016 created a `deferred-until-adjacent` label to mark findings that should not be dispatched on their own — they ride along when adjacent work touches their file (ADR-0029) or get drained by the active-cycle cleanup sweep (ADR-0028). The intent was "a nit isn't worth its own implementer run."

In practice the label drifted into a **second axis orthogonal to severity**. ADR-0016 Rule 2 (and four reviewer agents — code-reviewer, security-reviewer, drift-detector, dep-watcher) let *Medium* findings "carry the deferral label sparingly" (defense-in-depth hardening, cosmetic drift, peripheral dep churn). Once a Medium could be deferred and a Low could in principle be promoted, "deferred" stopped being derivable from severity and became a standalone flag — which then needed its own queryable set, its own ops-cockpit panel, and produced a confusing split between "Low/Nit not yet labeled" and "Low/Nit labeled deferred" that are the same lifecycle position one promoter pass apart.

This is redundant state. The rest of the system already assumes deferral tracks severity: ADR-0028's own decision driver is *"nothing exploitable is ever a nit"* (exploitable ⇒ High+ ⇒ auto-pickup, never deferred; only no-attack-path hardening lands at Low). The label was encoding, as data, a fact that severity already determines.

Should deferral remain a separate label, or collapse onto severity?

## Decision Drivers

- **One axis for "how much does this matter": severity.** A second, overlapping axis is the thing to eliminate.
- **Don't strand or mis-handle real work.** The change must not let a genuine Medium silently never-dispatch, nor let a nit consume a dedicated run.
- **Keep the drainage mechanics intact.** Adjacency bundling (ADR-0029) and the active-cycle sweep (ADR-0028) must keep working — only their *selector* may change.
- **Derivable beats stored.** If a property is a pure function of another field, compute it; don't materialize it as a label that can disagree.

## Considered Options

Two tightly-coupled sub-decisions:

- **Sub-decision 1 — the deferral axis:** keep the Medium-defer exception (deferral orthogonal to severity) **vs.** make deferral a pure function of severity (Low/Nit defer, Medium+ never).
- **Sub-decision 2 — the marker:** keep the `deferred-until-adjacent` label as the queryable set **vs.** retire it and query `severity:low,severity:nit` directly.

## Decision Outcome

We chose the bundle:

- **Sub-decision 1 → deferral is a pure function of severity.** Low and Nit findings defer, by definition. Medium and above never defer. The "deferred Medium" exception is removed from ADR-0016 Rule 2 and from every reviewer agent. A Medium that isn't worth a solo run is, by definition, a Nit — file it as one. (Urgency-vs-importance has no separate axis in this system; the exception was faking one.)
- **Sub-decision 2 → retire the `deferred-until-adjacent` label.** The deferred set is exactly `is:open is:issue label:severity:low,severity:nit -label:ready-for-implementer`. Every consumer (adjacency bundle, sweep target, sweep drain, release-notes query, cockpit panels) queries by severity instead of the label.

The bundle is internally consistent because the label is only safely derivable from severity *once the Medium exception is gone* — Sub-decision 2 depends on Sub-decision 1.

## Consequences

### Positive

- One axis. Deferral can no longer disagree with severity, because it *is* severity.
- The ops-cockpit "undispositioned Low/Nit" vs "Deferred pool" split collapses to a single `severity:low,severity:nit` row — no orthogonal state to track, no diagram drift.
- One fewer label to apply, query, and keep consistent across eight agents.
- Aligns the deferral definition with the rubric ADR-0028 already assumes ("nothing exploitable is ever a nit").

### Negative

- **Loss of "deferred Medium."** A reviewer can no longer mark a Medium as "real but low-urgency, fix opportunistically." It must either be a Medium (dispatched on its rank) or a Nit (deferred). Accepted: that capability was the orthogonal axis we're removing; the honest call is to pick a severity.
- **One-time reclassification.** Existing open issues carrying `deferred-until-adjacent` on a Medium need a severity decision (down to nit or left as a dispatchable medium). Handled as a migration step, not ongoing cost.

### Neutral

- The drainage *mechanics* are unchanged: promoter-selected same-file bundling (ADR-0029), active-cycle sweep (ADR-0028), quarterly sweep / 180-day re-triage (ADR-0016) all still run — they just select `severity:low,severity:nit` instead of the label.
- The label may linger on already-filed issues; it becomes inert (nothing queries it). A one-line cleanup can strip it, or it can be left to age out.

## Pros and Cons of the Options

### Sub-decision 1: the deferral axis

| Option | Pros | Cons |
|---|---|---|
| Keep Medium-defer exception | Lets a reviewer express "important but not urgent" | Creates a second axis; label no longer derivable; the root of the cockpit/panel confusion |
| **Deferral = f(severity)** (chosen) | One axis; derivable; matches ADR-0028's rubric | Loses "deferred Medium" — must pick nit or medium |

### Sub-decision 2: the marker

| Option | Pros | Cons |
|---|---|---|
| Keep the label | Explicit set; stable across severity-scheme changes | Redundant with severity; extra state to keep consistent; spawns the extra panel |
| **Retire, query severity** (chosen) | No redundant state; fewer labels; panels collapse | Touches every consumer once (this ADR's implementation) |

## Implementation notes

Canonical replacement for the deferred-set selector, everywhere:

```
label:deferred-until-adjacent   →   label:severity:low,severity:nit -label:ready-for-implementer
```

(`label:a,b` is GitHub's OR; `-label:ready-for-implementer` excludes fast-tracked low/nits.)

- **Workflows:**
  - `.github/workflows/triage-scan.yml` — promoter adjacency-bundle selection (same-file) and spare-capacity sweep target (repo with most open low/nit).
  - `.github/workflows/claude-implementer-reusable.yml` — Mode-C drain query + `bundle_issues` description + the implementer's "drop → leave it" wording.
  - `.github/workflows/claude-implementer.yml` — `bundle_issues` input description.
- **Agents (`plugins/ai-team/agents/`):** `code-reviewer`, `security-reviewer`, `drift-detector`, `dep-watcher` — delete the Medium-defer EXCEPTION clause; `doc-keeper`, `triage-bot` — Low/Nit no longer needs the label; `implementer` — adjacency wording; `release-captain` — release-notes query → `--search "label:severity:low,severity:nit"`.
- **Standards:** `docs/standards/10-ai-workflows.md` + the plugin mirror `plugins/ai-team/skills/standards-ai-workflows/standard.md`.
- **Diagram:** `docs/diagrams/autonomous-loop-flow.md` — the `PROMO → DEFER` edge label, the `DEFER` node, and the terminal-states table.
- **Observability:** `infra/ops-cockpit/dashboard.json` — collapse the "undispositioned Low/Nit" and "Deferred pool" rows into one `severity:low,severity:nit` row (follow-on apply).
- **Migration:** reclassify any open Medium currently carrying `deferred-until-adjacent` (down to nit, or strip the label and let it dispatch on its medium rank).

## Links

- [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) — original deferral policy; Rule 2 amended here.
- [ADR-0028](0028-nit-sweep-only-on-active-cycles.md) — active-cycle sweep; selector changes to severity.
- [ADR-0029](0029-promoter-owns-nit-adjacency.md) — promoter-owned adjacency bundling; selector changes to severity.
- [Standard 10 — AI workflows](../standards/10-ai-workflows.md)
