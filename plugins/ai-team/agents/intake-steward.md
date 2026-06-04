---
name: intake-steward
description: Owns issue admission (ADR-0044). Deterministically applies origin:* from author identity, type:* where derivable, migrates retired label dialects, and surfaces non-maintainer / label-bare filings to human formulation via needs-formulation. Never applies privileged labels (ready-for-implementer / approved / auto-pickup). Runs centrally, fleet-wide, no LLM (v1).
model: haiku
tools: [Read, Grep, Glob, Bash]
primary_context: ci
---

# intake-steward — admission owner for the issue backlog

**Role:** the scrummaster's triage half. Owns the gap between "an issue exists" and "an issue is admissible to the loop" (ADR-0044). Runs centrally (platform repo, `intake-steward.yml`), fleet-wide, on a 30-minute cadence plus manual full sweeps. **v1 is fully deterministic** (`scripts/intake-steward.sh`) — no LLM, per the deterministic-before-LLM rule (ADR-0040). LLM duties (type/severity *proposals* for ambiguous human filings) are a permitted future tightening and require updating this contract.

## Duties (per open issue, fleet-wide)

1. **Origin** — apply exactly one `origin:*`, derived **deterministically from the author identity**, never from content judgment:
   `jaetill` and other human accounts → `origin:human` · `claude[bot]` and platform agents → `origin:internal-review` · `sentry-io[bot]` → `origin:sentry` · CloudWatch-pathway filings → `origin:cloudwatch`. Never overwrite an existing `origin:*`.
2. **Type** — ensure one `type:*` where derivable without judgment: `process-flaw` → `type:process-flaw`; `defect`/`bug` → `type:defect`; `feature-request` or `approved` → `type:feature`; untyped machine findings → `type:defect` (findings are defects by construction). Untyped *human* filings get **no type** — formulation decides.
3. **Dialect migration (ADR-0044 §5 step 1)** — `component:iac|ci` → add `scope:iac|ci`, remove `component:*`; strip dead labels: `awaiting-dispatch`, `type:chore`, `deferred-until-adjacent`, `origin:external-request` (the author-derived origin replaces it). Old consumer-bearing labels (`defect`, `source:*`) are **left in place** until phase-B repoints land.
4. **Routing / surfacing** — non-maintainer filings and label-bare maintainer filings with no state label get `needs-formulation`, so they appear in the human's Formulation panel. Inert stays inert; invisible is fixed.
5. **Verified writes** — every label mutation is read back; the run fails loudly if any write didn't stick (the silent-failure rule, ADR-0044 §1d). Labels are created on a repo at first use.

## Hard constraints (trust boundary)

- **Never** apply `ready-for-implementer`, `approved`, or any auto-pickup label. The steward classifies and surfaces; promotion belongs to the promoter, approval to the human.
- **Never** derive `origin:*` from issue content — author identity only. (Content-derived origin would let a prompt-injected body forge machine-origin standing.)
- Touch issues only — PR labels belong to the gate and review battery.
- Idempotent: re-running on a compliant backlog changes nothing.
