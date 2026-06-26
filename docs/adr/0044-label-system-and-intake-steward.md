# ADR-0044: The label system — axes, resting states, and the intake-steward

- **Status:** Accepted — designed jointly across the 2026-06-05 permutation-table sessions; Jason approved the full package in-session ("i like it. create the ADR, i approve the ADR, merge it")
- **Date:** 2026-06-05
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, labels, intake, orchestration

> **Format:** MADR 4.x with the platform's three extensions. Bundled-sub-decision ADR — one coherent system in six coupled decisions. Method note: every decision below was derived from a fleet-wide **permutation table** (every `creator × exact-label-set` with counts, across issues AND PRs) plus a live autopsy of the 18 "in flight" items — empirical archaeology, not taxonomy a priori.

> **Amended by [ADR-0047](0047-firewall-gates-on-capability-delta.md):** the `hold:adr` and `hold:compositional` resting states are unchanged as *labels*, but what *earns* them is narrowed to a deterministic capability delta — `hold:compositional` is applied by `additive-self-change-guard.sh` on a real capability/control change, not by the advisory `compositional-self-change` label.

> **Amended (2026-06-23, #227 phase B — PR #571):** reconciles this ADR's origin axis with what was actually built. (1) The origin axis is kept **granular**: `origin:sentry` and `origin:cloudwatch` remain distinct values — their absence on live issues is app-dormancy (development has been on the platform, not the apps), not a decision to collapse them; real Sentry/CloudWatch traffic resumes with app development. (2) Two origin values that `claude-pr-review.yml` actually mints and this ADR's original table omitted are **retained, not deleted**: `origin:production-signal` (drift / dependency-advisory machine signals — narrower than the now-distinct Sentry/CloudWatch) and `origin:external-request` (external user feedback — feedback widget / human prompt — distinct from the maintainer's `origin:human`). The "dead vocabulary" framing in Context below refers only to the *zombie workflow's* emission of `origin:external-request`, not to the value itself. (3) Phase B repointed every in-repo consumer onto the axes and deleted the superseded dialect labels fleet-wide — `source:*`, `bug`, `defect`, `feature-request`, `component:*`, `awaiting-dispatch`, `type:chore`, `deferred-until-adjacent`; `triage:*` was already gone. The Sentry alert-rule cutover (`source:sentry` → `origin:sentry`) is out-of-repo and lands when app development resumes.

## Context and Problem Statement

The fleet's 289 open issues collapse into only 19 creator×label-set permutations — but those 19 hide five label *dialects* minted by different actors across eras: the canonical agent-finding shape (`defect, origin:internal-review, severity:*` — 82% of volume), the intake states (ADR-0036), PR-side gate labels (`requires-adr:<subtype>`, `compositional-self-change`), release-please's `autorelease: pending`, and a dead vocabulary (`awaiting-dispatch`, `component:*`, `type:chore`, `origin:external-request`) minted by **splendor's zombie `claude-triage-bot.yml`** — the one surviving pre-ADR-0030 per-repo triage workflow, still firing on issue events outside every window.

The dialects have real costs, all observed live this week: the in-flight autopsy found **zero of 18 `ready-for-implementer` issues actively being built** (the label had become a costume over five kinds of stuck); ten PRs awaiting Jason's ADR ratification were invisible to the "Waiting on Jason" dashboard because `requires-adr:api-contract` exact-matches nothing that queries `requires-adr`; an external user's issue (filed bare) was invisible rather than safely parked; and label mutations silently failed twice (`approved` didn't exist as a label on the platform repo — `gh issue edit` errors swallowed).

Root cause, in one sentence: **no actor owns admission, and no law governs what a label means.**

## Decision Drivers

- A dashboard query must be able to trust a label: exact-match, one meaning, one owner.
- Work must never rest in an unlabeled state (the in-flight autopsy) — and labels must never outlive the states they name (the stranded `ready-for-implementer`s).
- The intake model (ADR-0036) promised externals surface to the human; today they vanish.
- Vocabulary must not grow by improvisation (the zombie's dialect) — growth needs a rule.
- Token economy: deterministic before LLM, always (ADR-0040's precedent).

## Considered Options

- **Keep the flat ad-hoc label set (status quo)** — let each actor mint labels as needed.
- **Axis system + label law + intake-steward (chosen)** — orthogonal axes, one value per axis, labels only for resting states, and an agent that owns admission.
- **Axis system without an admission owner** — define the axes but leave labeling to the existing actors (no steward).

## Decision Outcome — six sub-decisions

### 1. The label law

**A label names a resting state or a queryable fact — nothing else.** Concretely: (a) any state where work can rest across cycles MUST have an exact-match label, applied by the actor that put it to rest; (b) transient states get no labels; (c) **strip-on-exit** — the actor that moves work out of a state removes its label (the implementer strips `ready-for-implementer` on any exit that produces no PR; ADR-0042's conflict-retry strip is the same pattern); (d) **label mutations are verified writes** — read back after every edit (two silent failures this week); (e) a new label value earns existence **only if something routes on it differently** (the anti-dialect rule).

### 2. The axes

Five orthogonal axes; one value per axis per issue (scope optional):

| Axis | Values | Notes |
|---|---|---|
| `type:` | `feature` \| `defect` \| `process-flaw` | Each routes differently: feature → formulation/approval; defect → promoter; process-flaw → Pass-3 platform pull. `chore` folded into `defect` (routes identically); `dep-watch` not modeled (the digest mechanism is being retired separately). |
| `origin:` | `human` \| `internal-review` \| `sentry` \| `cloudwatch` \| `production-signal` \| `external-request` | **Absorbs the `source:*` dialect** (`source:sentry`→`origin:sentry`, `source:cloudwatch`→`origin:cloudwatch`). Machine-origin = anything ≠ `origin:human`/`origin:external-request`. `sentry`/`cloudwatch` are auto-pickup origins (ADR-0016); `production-signal` covers drift / dep-advisory; `external-request` is external user feedback (routes to `needs-formulation`). Applied **deterministically from author identity** — never by LLM judgment. *(Amended 2026-06-23, #227 — values reconciled with the live minter; see amendment note above.)* |
| `severity:` | `critical`…`nit` (existing ladder) | Unchanged. `triage:*` remnants migrate per-issue. Features carry none — `approved` confers medium rank at promotion (ADR-0036). |
| state family | `needs-formulation`, `approved`, `ready-for-implementer`, `hold:<reason>`, `conflict-retry:<n>` | Resting states only, per the label law. |
| `scope:` | `ci` \| `iac` (optional; absent = app code) | Load-bearing (ADR-0035 IaC gate; CI-deliverability skip). **Wins over the zombie's `component:*`.** |

### 3. Merge-when-green and `hold:<reason>` — decided now, built as phase B

The windowed merge is retired: **a green, ungated implementer PR merges when it goes green, any time** — post-ADR-0039/0043 the human checkpoint lives at deploy approval, so merge needs no quiet-hours protection, and the "green PR idles 13h for a window" resting state is deleted rather than labeled (which also makes a `ready-for-merger` label unnecessary — dwell ≈ 0). The gates that still hold a green PR apply **`hold:<reason>`** (`hold:adr`, `hold:compositional`, `hold:iac-unverified`, `hold:checks-escalated`) so every remaining resting state is exact-match queryable and "Waiting on Jason" stops lying. Implementation is phase B (gate + workflow changes), tracked by approved issues filed with this ADR.

### 4. The intake-steward — admission has an owner

A new agent, **`intake-steward`**, owns the gap between "issue exists" and "issue is admissible": it applies `origin:*` deterministically from author identity; ensures `type:*` where derivable (agent findings are defects by construction; mapping table below); migrates dialect labels; routes **non-maintainer filings and unlabeled maintainer filings to `needs-formulation`** so they surface in the human's Formulation panel (fixing the invisible-external gap — inert stays correct, *unseen* does not); and lints agent filings against the axes at the door.

**Hard constraint (trust boundary):** the steward may never apply a privileged label — no `ready-for-implementer`, no `approved`, no auto-pickup origins on issues it didn't deterministically derive them for. It classifies and surfaces; promotion stays the promoter's, approval stays the human's.

**v1 is a pure deterministic script** (`scripts/intake-steward.sh`) run by a central platform workflow (`intake-steward.yml`, cron + manual full-sweep) — no LLM, no per-repo deployment (fleet App token, same pattern as urgent-poll). LLM duties (type/severity *proposals* for ambiguous human filings) are a permitted future tightening once a case demands judgment.

### 5. Migration — two steps, never breaking a consumer

Old labels with **live consumers** (Sentry's alert rules mint `source:sentry`; auto-pickup matchers read it; `defect` appears in agent contracts) are not renamed in place. Instead: **(step 1, now)** the steward *adds* the axis labels alongside the old ones and strips only consumerless dead labels (`awaiting-dispatch`, `component:*` after adding `scope:*`, `type:chore`, the stray `deferred-until-adjacent`); **(step 2, phased)** consumer-repoint issues (filed `approved` with this ADR) update each reader — Sentry alert-rule config (out-of-repo, human-touched), `implementer.md` auto-pickup, event-dispatch/urgent-poll matchers, cockpit queries — after which the superseded labels are deleted fleet-wide.

### 6. The zombie is retired

`splendor/.github/workflows/claude-triage-bot.yml` is deleted. Its instinct (triage at admission) was right and is succeeded by the steward; its vocabulary was a fossil dialect and is migrated by sub-decision 5.

## Consequences

**Positive:** every permutation in the table becomes a legal sentence or a lint error; dashboards inherit exact-match truth (the ten invisible ADR-held PRs become `hold:adr` counts); externals surface; the steward catches dialect drift at the door instead of archaeology later.

**Negative:** a dual-label transition period (old + axis labels coexist) until phase-B repoints land — queries written during the window must prefer the axis labels; the steward is one more standing workflow to keep healthy (mitigated: deterministic, no LLM, observable via its run history).

**Neutral:** PR-side gate labels (`requires-adr:<subtype>`, `compositional-self-change`, `autorelease: pending`) are unchanged by this ADR except that `hold:*` (phase B) will mirror them into the queryable state family.

## Implementation notes

- This PR: `plugins/ai-team/agents/intake-steward.md`, `.github/workflows/intake-steward.yml`, `scripts/intake-steward.sh`, this ADR.
- Separate splendor PR: delete `claude-triage-bot.yml`.
- Phase-B approved issues filed with this ADR: merge-when-green + `hold:*` gate change; consumer repoints (Sentry config, auto-pickup matchers, cockpit queries); superseded-label deletion.
- Amends/extends: [ADR-0016](0016-finding-lifecycle-calibration-deferral.md) (label vocabulary), [ADR-0036](0036-human-intake-model.md) (fills the formulation-mechanism placeholder; capture now enforced by the steward), [ADR-0021](0021-autonomous-merge.md)/[ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md) (merge timing, phase B), [ADR-0030](0030-all-dispatch-through-promoter.md) (the zombie was its last unconverted holdout).

## Pros and Cons of the Options

### Keep the flat ad-hoc label set
- Good: no migration.
- Bad: five competing dialects, dashboards that can't trust a label, immortal/invisible states, no owner for admission — the status quo this ADR exists to end.

### Axis system + label law + intake-steward (chosen)
- Good: every permutation is a legal sentence or a lint error; dashboards inherit exact-match truth; externals surface; drift is caught at the door.
- Bad: a dual-label transition window and one more standing workflow (deterministic, observable).

### Axis system without an admission owner
- Good: cleaner vocabulary with less machinery.
- Bad: leaves the root cause — human/external/agent filings still reconcile to nothing, so idle-forever issues persist.

## Links

- The permutation tables and in-flight autopsy: 2026-06-05 session; key exhibits — splendor#40's 68-second zombie enrichment, the silent `approved` failures, KOEfficient's invisible filing.
- [ADR-0040](0040-promoter-closes-stale-citation-findings.md) — the deterministic-before-LLM precedent the steward v1 follows.
