# ADR-0045: dep-watch digest architecture — rolling report file and writer/publisher security split

- **Status:** Accepted — digest medium decided 2026-06-03; writer/publisher split activated 2026-06-05 alongside the dep-watch workflow rewrite
- **Date:** 2026-06-05
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, dependencies, security, signal-to-noise

> **Format:** MADR 4.x with the platform's three documented extensions. Bundled-sub-decision ADR covering two tightly-coupled choices in the dep-watch workflow redesign: (1) the digest's publication medium and (2) the security architecture for LLM-generated content. Extends [ADR-0027](0027-dep-watcher-autonomous-backlog.md)-era behaviour; the dep-watcher's *triage* duties are unchanged — only the digest's medium and publishing pipeline move.

## Context and Problem Statement

The weekly dep-watch run needed two related decisions resolved simultaneously. Each repo held a standing "Weekly dependency report" issue edited in place forever — a never-closeable issue that offended backlog hygiene and polluted issue counts. Separately, the dep-watch workflow must pass attacker-influenced npm advisory text to a `bypassPermissions` LLM agent; if that agent also holds `contents: write` permission, a prompt-injection in an advisory could write arbitrary content to the repository. How should the dep-watch digest be published, and how should the LLM-generation step be isolated from write access?

## Decision Drivers

- The backlog must be able to reach zero open issues — a perpetual issue is permanent noise.
- The digest is *information, not change*: it should not consume issue counts, label queries, review, or merge gates.
- Latest state must stay easy to read, and history should be cheap to keep.
- Actionable findings (CVEs, EOL, major bumps) must remain separate `severity:*` issues entering the implementer backlog — unaffected by where the digest lives.
- **Prompt-injection threat:** npm advisory text is attacker-influenced input; it is fed to a `bypassPermissions` agent — a mode that allows the agent to bypass tool-call restrictions. If the LLM generation step also holds write credentials, a crafted advisory could write malicious content or exfiltrate secrets from the repository.
- **Writer ≠ approver invariant:** a step that produces output must not also be the step that commits it — the same principle as [ADR-0035](0035-auto-merge-safe-additive-iac.md)'s independent guard.

## Considered Options

- Sub-decision 1: Digest medium — where to publish the rolling digest
- Sub-decision 2: Security architecture — how to isolate the LLM generation step from write access

## Decision Outcome

We chose the bundle:

- Sub-decision 1 → **Rolling file on a `reports/dep-watch` branch** (`docs/dependency-report.md`), rewritten each run; history is the branch's commit log.
- Sub-decision 2 → **Writer/publisher split with artifact handoff** — the `generate` job (LLM, `contents: read`) emits the report as a GitHub Actions artifact; a separate deterministic `publish` job (no LLM, fixed shell, `contents: write`) fetches the artifact and pushes it.

The bundle is internally consistent because the artifact-based handoff is both the security boundary (no write credential in the LLM job) and the mechanism that enables the rolling-file approach (the publish job is the only actor with commit authority on `reports/dep-watch`).

## Consequences

### Positive

- Zero perpetual issues; the backlog can reach zero; digest history is the branch's commit log with no label or cockpit-row overhead.
- Prompt-injection in an advisory cannot write to the repository — the LLM job holds no write credential.
- The deterministic publish step is auditable: every commit to `reports/dep-watch` is made by a fixed shell script, not an LLM.
- Consistent with [ADR-0035](0035-auto-merge-safe-additive-iac.md)'s writer-not-approver principle; no new security pattern to invent.

### Negative

- The report is one click further away (a branch file, not an issue in the default view) — acceptable for a read-only info sink.
- Two-job handoff via artifact adds workflow complexity vs. a single job.

### Neutral

- The `dep-watch` label retires with the perpetual issues (it was deliberately left out of [ADR-0044](0044-label-system-and-intake-steward.md)'s type axis).
- The cockpit's dep-watch row (header + 8 stats) retires.

## Pros and Cons of the Options

### Sub-decision 1: Digest medium

| Option | Pros | Cons |
|---|---|---|
| **Rolling file on `reports/dep-watch`** (chosen) | Zero perpetual issues; backlog can reach zero; history is `git log`; no label/cockpit overhead; information, not change | Report is one click further away than an issue |
| **Keep the perpetual per-repo issue** | Maximally discoverable in the default issue list | Never-closeable issue pollutes counts and label queries; requires its own cockpit row |
| **Fresh issue each week, auto-closing prior** | Each issue is closeable | Weekly open/close churn in the backlog and notification stream for a read-only info sink |

### Sub-decision 2: Security architecture for LLM-generated content

| Option | Pros | Cons |
|---|---|---|
| **Inlined write permissions with sanitization** | Single job, simpler workflow | Sanitization of attacker-controlled text is bypassable; a `bypassPermissions` agent with write credentials is the maximum-risk configuration — any prompt-injection in the npm advisory ecosystem gets a free repository write |
| **Writer/publisher split with artifact handoff** (chosen) | LLM job holds zero write credentials; publish job is deterministic shell with no LLM; consistent with ADR-0035's writer-not-approver shape; artifact provides a clear, inspectable boundary | Two-job handoff; artifact retention adds minor overhead |
| **No LLM-generated report** | Eliminates prompt-injection risk entirely | Loses qualitative advisory analysis and actionability scoring; `npm audit` JSON alone lacks severity context; defeats the dep-watcher's purpose |

## Implementation notes

- Workflow: `.github/workflows/dep-watch.yml` — `generate` job (`permissions: contents: read`, LLM + artifact upload) + `publish` job (`permissions: contents: write`, deterministic shell + artifact download + force-with-lease push to `reports/dep-watch`).
- 7 × `claude-dep-watcher.yml` caller workflows updated; write permission moved to the publish job.
- 7 standing digest issues closed with pointers to the rolling branch file.
- Cockpit dep-watch row removed.

## Links

- [ADR-0027](0027-dep-watcher-autonomous-backlog.md) — dep-watcher triage duties (unchanged by this ADR).
- [ADR-0035](0035-auto-merge-safe-additive-iac.md) — writer-not-approver principle; the IaC guard has the same shape.
- [ADR-0018](0018-workflow-distribution.md) — reusable workflow distribution (dep-watch.yml is distributed via this pattern).
- [ADR-0044](0044-label-system-and-intake-steward.md) — label system; `dep-watch` label deliberately excluded from the type axis.
