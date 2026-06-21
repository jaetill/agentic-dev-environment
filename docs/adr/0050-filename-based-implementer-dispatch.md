# ADR-0050: Dispatch implementers via the filename-based REST endpoint, not `gh workflow run`

- **Status:** Accepted
- **Date:** 2026-06-21
- **Implementation:** Pending behind ratify-merge of this PR (fixes #432, #410; clears the live CI-health signal #484)
- **Deciders:** Jason
- **Tags:** ci-cd, fleet-orchestration, dispatch, reliability

> **Lifecycle:** `Proposed` → `Accepted` (decided, awaiting human ratify) → `Ratified` → `Implemented`. On ratify-merge, flip Status to `Implemented` and set the Implementation line to `Implemented 2026-06-21 via #<this PR>`.

## Context and Problem Statement

On 2026-06-15 every fleet dispatch in the promoter's work-hours pass failed with `HTTP 500: Failed to run workflow dispatch` against `…/actions/workflows/<id>/dispatches` — across all six targeted repos (agentic-dev-environment, ai-teacher, draft, carto, jaetill-portal). The loop cannot dispatch implementers, so the backlog cannot drain autonomously; the CI-health watcher (#484) is reporting real failed `claude-implementer` runs as a direct consequence. How should the fleet dispatch implementer runs so dispatch is reliable?

The observed root cause: `gh workflow run <name>.yml` first resolves the workflow *name* to an integer *ID*, then calls the **ID-based** dispatch endpoint. GitHub returned HTTP 500 on the ID-based endpoint fleet-wide. The **filename-based** endpoint (`/actions/workflows/<filename>/dispatches`) succeeds for the same dispatch.

## Decision Drivers

- Dispatch is foundational — every other autonomy feature is downstream of it. Reliability dominates.
- The dispatch command is duplicated across five sites (two executable bash steps, three agent-prompt instructions) and must stay uniform fleet-wide (ADR-0034).
- Repos use mixed default branches: `draft`/`carto` are `master`, the rest `main`. A hardcoded `ref` returns HTTP 422 on the `master` repos.
- The change touches gate/governance machinery (a rail-enforcer agent + two gate workflows) → ADR-0047 firewall holds it for human ratification.

## Considered Options

- Option A: Keep `gh workflow run`, retry/backoff on 500.
- Option B: Switch to the filename-based `gh api .../workflows/<filename>/dispatches`, detecting the default branch dynamically.
- Option C: Switch to a `repository_dispatch` event instead of `workflow_dispatch`.

## Decision Outcome

Chosen option: **Option B**, because it is the minimal change that directly avoids the failing ID-based endpoint, uses the same `workflow_dispatch` trigger and inputs already wired into `claude-implementer.yml` (no workflow-trigger redesign), and the filename endpoint is empirically confirmed to serialize and accept the dispatch. The default branch is detected per-repo (`gh api repos/<repo> --jq .default_branch`) so the `master` repos no longer 422.

## Consequences

### Positive

- Dispatch works again fleet-wide; the loop resumes autonomous draining of the ~80-deep backlog.
- Default-branch detection removes the latent `master`-repo 422 class entirely (previously masked by the 500).

### Negative

- The dispatch command is two lines longer (branch lookup + api call) at each of five sites; slightly less terse than `gh workflow run`.
- One extra `gh api` call per dispatch (the default-branch lookup). Negligible at fleet dispatch volume.

### Neutral

- Inputs serialize as JSON strings via the `-f "inputs[key]=value"` bracket notation (verified against the request body). `workflow_dispatch` inputs are strings regardless, so behavior is unchanged.

## Pros and Cons of the Options

### Option A: retry `gh workflow run`

- ✅ Pro: smallest diff.
- ❌ Con: the ID-based endpoint was failing 100% fleet-wide, not transiently — retries do not help a systemic 500.
- ❌ Con: leaves the latent `master`-repo issue unaddressed.

### Option B: filename-based `gh api` dispatch (chosen)

- ✅ Pro: avoids the failing endpoint directly; empirically succeeds.
- ✅ Pro: forces explicit default-branch handling, fixing the `master`-repo 422 too.
- ✅ Pro: same `workflow_dispatch` contract — no trigger redesign, no consumer changes.
- ❌ Con: marginally more verbose per call site.

### Option C: `repository_dispatch`

- ✅ Pro: a different mechanism, also avoids the ID endpoint.
- ❌ Con: requires re-wiring every `claude-implementer.yml` to accept `repository_dispatch` and re-deriving inputs from `client_payload` — large blast radius across the fleet for no extra benefit over B.
- ❌ Con: `repository_dispatch` only targets the default branch and adds an unvalidated-payload surface (cf. #127).

## Implementation notes

- Affected workflows: `.github/workflows/triage-scan.yml` (event-dispatch bash step + the embedded promoter prompt, promotion + cleanup-sweep), `.github/workflows/urgent-poll.yml` (urgent-poll bash step).
- Affected agent: `plugins/ai-team/agents/triage-bot.md` (promoter-pass dispatch + spare-capacity sweep instructions).
- Runbook: `docs/runbooks/autonomous-loop.md` (manual-dispatch examples + the "fleet dispatch did nothing" failure-mode row).
- Validation: dispatch one issue via the new path and confirm the `claude-implementer` run starts (per #432's test plan).

## Links

- GitHub REST — Create a workflow dispatch event: `https://docs.github.com/rest/actions/workflows#create-a-workflow-dispatch-event` — the filename-based endpoint this ADR adopts.
- #410 — the originating process-flaw report (HTTP 500 observed fleet-wide).
- #432 — the formulation ticket carrying the proposed fix.
- ADR-0034 — implementer reusable-distributed (why the dispatch command must stay uniform fleet-wide).
- ADR-0047 — capability-delta firewall (why this compositional change is human-held).
