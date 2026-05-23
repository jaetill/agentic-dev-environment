# Standard 10 — AI Workflows

**Status:** 🟩 Decided (2026-05-08)
**ADR:** [ADR-0011](../adr/0011-ai-workflows.md)

This standard operationalizes the AI side of the platform that every prior standard has been assuming. It defines the head agent's modes, the 12 specialist subagents' system prompts and triggers, the hook policy, the slash command set, and the discipline around tokens, performance, and autonomy.

## Three guiding principles

> **Token cost discipline.** Cheap models for routine work; expensive models only where reasoning depth justifies. Prompt caching everywhere it applies. Pre-flight cheap checks before invoking expensive agents. Per-agent budgets with alerts.
>
> **Performance discipline.** Same standard as ADR-0007. Agents fan out in parallel where independent. Path-filtered context. Per-trigger time budgets enforced.
>
> **AI-autonomy default.** Each agent's prompt grants explicit authority for its scope. Self-recovery preferred over escalation. Escalation paths are for genuine anomalies, not "to be safe."

These principles are baked into every agent's system prompt and into the hook configuration.

## Summary

| Concern | Choice |
|---|---|
| Architecture | Head agent (orchestrator + decision partner, multiple modes) + 12 specialist subagents (headless workers) |
| Model selection | Tiered: Haiku for routine; Sonnet for reasoning; Opus only for `architect` on ADR-gated PRs |
| Token budgets | ~$15/mo total at solo scale; per-agent caps; prompt caching of stable context |
| Hook policy | Mixed strictness with concrete rules (see §3) |
| Slash commands | 10 commands (see §4) |
| Anomaly handling | Self-recover with retry; escalate only on genuine novelty or repeated failure |

## 1. The two-entity architecture

There are two kinds of entity:

### Head agent

The Claude session the human talks to. Holds memory, project state, conversation history. Orchestrates specialist subagents via the Agent/Task tool. Operates in different *modes* — architect, scrummaster, investigator, planner — but these are descriptive moments of one agent, not separate identities.

When a "scheduled scrummaster run" happens (e.g., daily digest), it's the head agent spawning with mode-specific instructions.

### 12 specialist subagents

Headless workers, narrow scope, restricted tools. Each has a focused system prompt. Always invoked by the head agent or by scheduled workflows.

| Subagent | Role | Cadence |
|---|---|---|
| `architect` (headless) | Autonomous ADR drafting from PR diffs when no human is in the conversation | On ADR-gated PR |
| `code-reviewer` | PR review against standards (incl. clarity/naming gap from ADR-0005) | On every PR |
| `security-reviewer` | Injection, secrets, authn/authz, dep CVEs | On every PR |
| `functional-tester` | Functional + integration test authoring/running | On PR + on staging |
| `e2e-tester` | Playwright end-to-end test authoring/running | On merge to main + on tag |
| `test-writer` | Unit test authoring on new/changed code | On PR if coverage drops |
| `doc-keeper` | README, runbook, API doc upkeep, dashboards drift detection | On merge to main |
| `release-captain` | Release notes, version bumps, tagging, publish, Sentry release | On Conventional-Commits-driven release PR |
| `dep-watcher` | Dependabot/Renovate PR review | On dep PRs |
| `incident-responder` | Reactive urgent triage — auto-rollback fails, prod down, paging | Real-time on alert |
| `drift-detector` | IaC drift triage and proposed fixes (per ADR-0007) | Weekly scheduled |
| `triage-bot` | Proactive scanner — gathers logs/errors, classifies, dedupes, files tickets with customer-advocate lens | Daily/weekly + webhook-driven |

## 2. Model selection per agent

The model is part of each agent's contract. Specified in the agent's frontmatter and propagated through all invocations.

| Agent | Model | Cheap-then-escalate? |
|---|---|---|
| `code-reviewer` | Sonnet 4.6 | No |
| `security-reviewer` | Sonnet 4.6 | No |
| `architect` (headless) | Opus 4.6 | No |
| `test-writer` | Sonnet 4.6 | No |
| `functional-tester` | Haiku 4.5 | Escalate to Sonnet on novel test authoring |
| `e2e-tester` | Haiku 4.5 | Escalate to Sonnet on novel test authoring |
| `doc-keeper` | Haiku 4.5 | No |
| `release-captain` | Haiku 4.5 | Escalate to Sonnet for narrative on majors/feature releases |
| `dep-watcher` | Haiku 4.5 | Escalate to Sonnet for major version bumps or unfamiliar deps |
| `incident-responder` | Sonnet 4.6 | No |
| `drift-detector` | Haiku 4.5 | Escalate to Sonnet for fix-PR drafts |
| `triage-bot` | Haiku 4.5 | Escalate to Sonnet for ticket framing |

The head agent uses the model the user is talking to it through (Sonnet 4.6 in interactive use; can be configured otherwise per session).

### Cheap-then-escalate pattern

Several agents (release-captain, drift-detector, triage-bot, dep-watcher, *-tester) use a two-tier prompt structure:

1. **Tier 1 (Haiku):** classify, dedupe, route. If the work is routine, complete it.
2. **Tier 2 (Sonnet):** invoked by Tier 1 when reasoning depth is needed (drafting prose, proposing a non-trivial change, evaluating a major version bump).

Tier 1 invokes Tier 2 explicitly via the Agent/Task tool. Both tiers are the *same agent* (same name, same scope) — the agent's prompt routes appropriately based on the input.

## 3. Hook policy

ADR-0001 / earlier discussion locked in **Mixed** strictness. The concrete rules:

### Block (reject + require explicit confirm to proceed)

| Lifecycle event | Pattern |
|---|---|
| `PreToolUse(Bash)` | `rm -rf /\|sudo \|git push --force.+main\|DROP TABLE\|TRUNCATE\|DELETE FROM .* WHERE 1=1` |
| `PreToolUse(Bash)` | Credential patterns (`AWS_SECRET_ACCESS_KEY=`, etc.) |
| `PreToolUse(Edit\|Write)` | Files matching `**/*.tfstate`, `.env*` (never editable) |

### Warn (surface but don't block)

| Lifecycle event | Action |
|---|---|
| `PostToolUse(Edit\|Write)` for source code | Run formatter on changed files; auto-fix |
| `PostToolUse(Edit\|Write)` for source code | Run linter; surface findings |
| `Stop` if tests failing or dirty tree | Warn; require confirm to proceed |

### Inject (add context to the head agent's prompt)

| Lifecycle event | Inject |
|---|---|
| `UserPromptSubmit` | Current branch, uncommitted state, last 3 commits |
| `SessionStart` | Project standards summary (links), recent ADRs (last 5), open issues |
| `UserPromptSubmit` for ADR-related work | Inject the relevant standards doc + prior ADRs in the topic |

### Audit (log only)

| Lifecycle event | Action |
|---|---|
| `PostToolUse(Bash)` | Append to `.claude/audit.log` (timestamp, command, exit code) |
| `PreToolUse(Edit)` for files containing PII tags | Log access; require confirm to proceed |

### Configuration

Hooks live in `plugins/ai-team/hooks/` in the platform workspace and ship via the plugin subscription (per ADR-0015). Each project's `.claude/settings.json` enables the plugin (`"ai-team@agentic-dev-environment": true`); the hook configuration ships inside the plugin at `plugins/ai-team/hooks/hooks.json` and is loaded automatically by Claude Code.

## 4. Slash commands

Each command is a markdown file under `plugins/ai-team/commands/` in the platform workspace, shipped via the plugin subscription (per ADR-0015) and invoked as `/ai-team:<command>` in subscribing projects.

| Command | Purpose | Invokes | Model |
|---|---|---|---|
| `/brainstorm <topic>` | Open a structured brainstorming session for a feature, design choice, or problem | Head agent in architect mode | (head's session model) |
| `/adr <topic>` | Draft an ADR for a decision | Head agent in architect mode (or `architect` subagent if headless) | (head's session model) or Opus 4.6 |
| `/review` | On-demand review of the current diff or specified files | `code-reviewer` + `security-reviewer` (parallel) | Sonnet 4.6 (each) |
| `/security-review` | Focused security review | `security-reviewer` | Sonnet 4.6 |
| `/test <files>` | Generate or run tests for specific files | `test-writer` / `functional-tester` | Sonnet 4.6 / Haiku 4.5 |
| `/release-notes` | Draft narrative release notes for the pending release | `release-captain` (Sonnet tier) | Sonnet 4.6 |
| `/triage` | One-off triage scan over recent logs | `triage-bot` | Haiku 4.5 |
| `/digest` | Generate the daily/weekly digest on demand | Head agent in scrummaster mode | (head's session model) |
| `/scaffold-project --stack=<X> --name=<Y>` | Bootstrap a new project | Head agent + scaffolding scripts | (head's session model) |
| `/postmortem` | Draft a postmortem for a recent incident | `incident-responder` + `architect` | Sonnet 4.6 + Opus 4.6 |

## 5. Token & performance budgets

### Per-agent token budgets

| Agent | Per-invocation input | Per-invocation output | Trigger frequency (solo) | Monthly $ estimate |
|---|---|---|---|---|
| `code-reviewer` | ~30K | ~3K | ~20 PRs/mo | ~$2 |
| `security-reviewer` | ~30K | ~2K | ~20 PRs/mo | ~$2 |
| `architect` (headless) | ~50K | ~5K | ~3 ADR-gated PRs/mo | ~$3 |
| `test-writer` | ~20K | ~5K | ~15/mo | ~$2 |
| `functional-tester`, `e2e-tester` | ~10K | ~1K each | ~30/mo each | <$1 total |
| `doc-keeper` | ~15K | ~2K | ~10/mo | <$1 |
| `release-captain` | ~10K H / ~30K S | ~2K H / ~5K S | ~5 releases/mo | <$1 |
| `dep-watcher` | ~10K | ~1K | ~10/mo | <$1 |
| `incident-responder` | ~30K | ~3K | rare (target <2/mo) | <$1 |
| `drift-detector` | ~15K | ~2K | weekly | <$1 |
| `triage-bot` | ~10K | ~2K | daily | ~$1 |
| **Total estimate** | | | | **~$15/mo** |

These are estimates. Budgets are enforced per invocation by API limits and by each agent's prompt instructing it to abort if the budget is exceeded.

### Prompt caching

Applied to stable context that's the same across invocations:

| Cached content | Approx. size | Hit rate |
|---|---|---|
| Agent's system prompt | 2–5K | 100% |
| Platform CLAUDE.md + standards summary | ~10K | 100% |
| Project CLAUDE.md (≤200 lines) | ~3K | 100% per project |
| Recent ADRs (last 5) | ~15K | high |

Cached reads charged at ~10% of normal cost. This typically reduces the *effective* per-invocation input cost by 60–80%.

### Performance budgets per trigger

| Trigger | Budget | Mechanism |
|---|---|---|
| PR opened (full review battery) | ≤90s wall time | code-reviewer + security-reviewer + destructive-change-detector run **in parallel** |
| Merge to main (deploy + e2e) | ≤5 min | e2e-tester runs after dev deploy completes |
| Tag created (release flow) | ≤8 min | release-captain + Sentry release + publish in sequence |
| Agent response time (interactive) | <5s for Haiku; <30s for Sonnet; <2 min for Opus | Per Anthropic's published p95 latencies |
| Hook execution | <500ms per hook | Hooks are fast checks, not heavy work |

Budget violations follow ADR-0007's protocol: architect-led investigation, ADR-documented adjustment if justified.

## 6. Memory & context strategy

How agents access shared knowledge without re-reading everything:

| Layer | What's there | How agents access |
|---|---|---|
| **Platform repo's `CLAUDE.md` + standards docs** | The decisions ADR-0001 through ADR-0011 made | Loaded once into prompt cache; ~10K tokens; cached at 10% cost |
| **Project's `CLAUDE.md`** | Project-specific context (≤200 lines per ADR-0008) | Loaded into context per invocation; cached |
| **Memory files** (head agent only) | Cross-session knowledge about user, project history, working preferences | Read-only by subagents via head-agent injection; head agent updates |
| **Recent ADRs** | Last 5 accepted ADRs; cross-references when relevant | Injected into agent prompt by hooks (`SessionStart`, `UserPromptSubmit` for ADR work) |
| **The diff / changeset** | What this specific invocation is reviewing | Loaded fresh per invocation; not cached |
| **Audit log** (`.claude/audit.log`) | What agents have done historically | Read by `drift-detector` + `triage-bot` when investigating |

Subagents are stateless within an invocation. They do not write memory files. The head agent owns memory mutations.

## 7. Anomaly handling

Agents self-recover where possible. Escalation is for genuine anomalies, not safety.

| Anomaly | Agent action |
|---|---|
| Tool call fails (network, API rate limit) | Retry with exponential backoff, max 3 attempts. Escalate only if all 3 fail. |
| Output token budget exceeded | Save partial work; either request budget increase from head agent OR fall back to a narrower scope. |
| Test agent finds a destructive change in code being tested (an unsafe migration in a feature PR) | Stop the test run; route to `architect` (subagent) for ADR review; mark PR as ADR-gated. |
| Triage-bot finds an error pattern that requires immediate response (auth bypass observed in logs) | Skip ticket creation; page `incident-responder` directly. |
| Agent disagrees with the human's instruction | Push back **once** with reasoning; if human reaffirms, proceed. Don't endlessly debate. |
| Agent encounters something genuinely outside its training (novel cloud service, weird build system) | Escalate to head agent rather than guessing. |
| Hook blocks an action and agent has no fallback | Ask the human via the head agent; do not bypass the hook. |
| Agent invocation times out | Save partial state; report what was completed; let the orchestrator decide whether to retry. |

Each anomaly path is documented in the agent's system prompt as an explicit fallback. The agent's prompt template includes a final section: "Anomaly handling — if you encounter X, do Y."

## 8. Agent invocation patterns

### Parallel fan-out (preferred for independent work)

When multiple agents need to run on the same input and don't depend on each other, the head agent invokes them in parallel via a single message with multiple Agent tool calls:

```
PR opened →
  Head agent invokes (in one parallel batch):
    - code-reviewer
    - security-reviewer
    - destructive-change-detector
  → all three return → head agent aggregates → posts PR comment
```

### Sequential pipeline (when dependencies exist)

Some flows are inherently sequential:

```
release-please opens PR →
  release-captain (Tier 1, Haiku) reviews changelog →
    decides narrative is needed →
      release-captain (Tier 2, Sonnet) drafts narrative →
        release-captain auto-merges PR →
          deploy workflow runs → tag created →
            Sentry release CLI uploads source maps
```

### Triggered by hook (fastest path)

The fastest agent invocations are triggered by hooks rather than by explicit head-agent decisions:

```
PR opened →
  GitHub Actions workflow triggers →
    workflow invokes `code-reviewer` directly (no head-agent involvement) →
      result posted as PR comment
```

This pattern eliminates a head-agent round trip for fully-automated work.

## 9. Triggers — full table

| Trigger | Agents involved | Pattern |
|---|---|---|
| PR opened or updated | code-reviewer, security-reviewer, destructive-change-detector, test-writer (if coverage drops) | Parallel fan-out via GitHub Actions |
| ADR-gated PR (one of 5 categories per ADR-0003) | architect (subagent) drafts ADR; merge blocked until ADR Accepted | Sequential |
| Merge to main | doc-keeper updates docs; e2e-tester on dev | Parallel |
| release-please opens release PR | release-captain | Sequential (Tier 1 → Tier 2 if needed) |
| Tag created | release-captain (publish + Sentry release); deploy workflow | Sequential |
| Auto-rollback triggered | incident-responder | Direct |
| Auto-rollback fails | incident-responder pages human | Direct |
| Daily | triage-bot scans logs | Direct |
| Weekly | drift-detector checks IaC | Direct |
| Weekly | head agent in scrummaster mode generates digest | Scheduled head-agent session |
| Dependabot opens PR | dep-watcher | Direct |
| Hook fires (destructive bash detected, etc.) | Block + require human confirm | Hook-only, no agent |
| Slash command invoked | (per §4 table) | Direct |

## 9a. Finding lifecycle — calibration, deferral, Sentry-driven cleanup

Per **[ADR-0016](../adr/0016-finding-lifecycle-calibration-deferral.md)**, three rules govern how findings flow from creation through resolution:

### Severity calibration

Reviewer-style agents (`code-reviewer`, `security-reviewer`, `triage-bot`, `doc-keeper`) explicitly avoid manufacturing severity to justify their reviews. Calibration is built into each agent's prompt:

- **Critical / High** — Actual production breakage, exploitable security path, data loss. Predictions of CI failure must be verified against actual run output before being filed at this level.
- **Medium** — Real bug or risk, bounded impact, clear fix.
- **Low / Nit** — Code smell, style, theoretical edge case. Reasonable authors could disagree.
- When in doubt, **downgrade**.

### Deferral policy

Low and nit findings get filed as GitHub issues with the **`deferred-until-adjacent`** label. The implementer does NOT pick them up in isolation. Instead — per **[ADR-0020](../adr/0020-fleet-orchestration.md)**, which amends ADR-0016's flat cap of 2 — every dispatched implementer run drains nits across two PRs. The **fix PR** bundles directory-adjacent deferred nits, cap `min(floor(total / 2), 4)`. A separate **sidecar cleanup PR** drains the rest, cap `max(floor(total / 2), 8)`, chunked at 12 issues per PR. `total` is the repo's open `deferred-until-adjacent` count. The promoter's spare-capacity `mode=cleanup-sweep` dispatch drains repos that get no qualifying work — so cold-code nits no longer wait on coincidental adjacency.

Medium findings default to non-deferred; defense-in-depth Mediums and prose-quality Mediums may carry the deferral label sparingly.

### Sentry-bug auto-pickup

Issues labeled `source:sentry` (auto-applied by Sentry's GitHub integration when its alert rules create an issue) or `severity:critical` trigger the implementer **immediately**, regardless of whether `ready-for-implementer` is set. Sentry-reported bugs are pre-validated production work; they don't need a triage gate. Fixing a Sentry bug also triggers the deferral-bundling scan in the same directory.

### Backlog finalization

- **Quarterly sweep:** `/ai-team:sweep-deferred` (slash command, future implementation) re-triages deferred issues older than 90 days.
- **Hard age limit:** any deferred issue open >180 days gets re-triaged (close, upgrade severity, or sweep).
- **Release visibility:** `release-captain` adds a "Cleaned up while here" section to release notes listing closed `deferred-until-adjacent` issues since the last release.

### Consumer-side workflow update needed

To make Sentry-bug auto-pickup actually fire, each consuming project's `claude-implementer.yml` must trigger on `source:sentry` and `severity:critical` labels in addition to `ready-for-implementer`. This is a one-line workflow-trigger change; tracked in the platform-port-quirks runbook. The `source:sentry` label itself is applied by Sentry's GitHub integration's alert-rule config — no separate auto-labeler workflow is needed.

## 9b. Fleet orchestration

Per **[ADR-0020](../adr/0020-fleet-orchestration.md)**, the autonomous loop runs as **one central loop reaching the whole portfolio**, not one loop per repo.

### One loop, every repo

`triage-scan.yml` is a single scheduled workflow on the platform repo. Its promoter pass scans and promotes agent-discovered work across every fleet repo. `severity:medium`, `severity:high`, and `triage:medium` are all promotable — ADR-0020 added `severity:high`, which previously had no automatic path. `severity:critical` and `source:sentry` still auto-pick-up at the implementer.

### Dispatch, not cascade

When the promoter promotes an issue it (1) applies `ready-for-implementer` as durable state and (2) explicitly dispatches that repo's `claude-implementer.yml` via `workflow_dispatch`. The dispatch is the trigger — a cross-repo label event does not reliably wake a workflow (GitHub's `GITHUB_TOKEN` cascade rule). A failed dispatch is visible in the scanner log; a silent label is not.

### The fleet credential

The loop's cross-repo credential is a GitHub App; the platform workflow mints a short-lived installation token per run. It holds `Issues` + `Actions` write for promotion and `Contents` + `Pull requests` write for autonomous merge (§9c) across the fleet. It writes platform→project only — the project→platform boundary (ADR-0019, Standard 12) is untouched.

### Throughput

The promoter respects a per-run dispatch cap (`FLEET_MAX_DISPATCH_PER_RUN`, default 6) so unblocking the backlog does not flood the implementers. Spare capacity is spent on `mode=cleanup-sweep` dispatches that drain deferred nits.

### Detection across the fleet

`ci-health.yml` watches every fleet repo's non-PR workflow runs and files one consolidated issue on the platform repo when failures hide. See Standard 12 for how a detected breakage in a platform-sourced workflow routes to a team fix.

## 9c. Autonomous merge of routine fix PRs

Per **[ADR-0021](../adr/0021-autonomous-merge.md)**, the fleet loop closes itself: the autonomous implementer's routine fix PRs are squash-merged by an `auto-merge` job in the `triage-scan` promoter — no human, no open session. This *applies* ADR-0003's approval model (AI shipping authority; the human gates only ADR-decisions) to the implementer path, the same way `release-captain` already auto-merges release PRs.

### The four-condition gate

The job merges an implementer fix PR when, and only when, **all four** conditions hold. The gate is deterministic — decidable from labels and check state, with no agent judgement at merge time:

1. **Implementer-authored, fixing a defect.** The PR's author is the implementer agent (`gh pr list --json author` renders the App bot as `app/claude`) and it closes an issue labelled `defect` or `bug`. A `feature-request` is excluded — features keep ADR-0017's plan-gate, where the human approves the approach first.
2. **Every check green.** The full AI review battery (§9, ADR-0003) passed; `code-review` and `security-review` are hard gates. A PR with *zero* checks does not qualify — the gate requires a non-empty green battery, not a vacuous pass.
3. **No `requires-adr:*` label.** The five ADR-gated categories (ADR-0003) route to the human, unchanged.
4. **A project repo.** The platform repo is excluded — its PRs are self-modifications, human-merged per [ADR-0019](../adr/0019-team-self-modification.md) / Standard 12.

### Controls

- **`AUTONOMOUS_MERGE`** — repo/org variable, default `on`. Set it `off` to pause autonomous merge fleet-wide with no code change.
- **`AUTONOMOUS_MERGE_CAP`** — default `10`. Bounds merges per run, so a malfunctioning implementer cannot land an unbounded batch in a single window.

### Why the merge runs centrally, as the fleet App

The job lives in the central `triage-scan` promoter, not the per-repo `claude-pr-review` reusable, and merges with the fleet App token — not `GITHUB_TOKEN`. A `GITHUB_TOKEN` merge triggers nothing downstream (ADR-0018): release-please would never see it, so nothing would deploy. The fleet App's events cascade, and its installation credential lives only on the platform repo — so the merge must run centrally. This is why the fleet App also carries `Contents` + `Pull requests` write (see §9b).

This is the operational form of *commander's intent*: a `defect`/`bug` fix inside the implementer's scope cap is routine and ships; anything that redefines scope arrives as a `feature-request` (→ plan-gate) or trips `requires-adr` (→ human).

## 10. Setup checklist

When bootstrapping a new project, the `new-project.sh` script will:

- [ ] Create `.claude/settings.json` subscribing to the `ai-team` plugin (per ADR-0015) — the plugin ships agents, commands, hooks, and skills
- [ ] Add the canonical `permissions.deny` block to `.claude/settings.json` (plugin manifests cannot ship permissions per the Claude Code spec)
- [ ] Add `.claude/audit.log` and `.claude/sessions/` to `.gitignore`
- [ ] Configure GitHub Actions workflows that invoke agents on triggers (per §9)
- [ ] Install the fleet GitHub App on the repo so the central promoter, auto-merger, and ci-health watcher can reach it (`Issues` + `Actions` + `Contents` + `Pull requests` write; see [ADR-0020](../adr/0020-fleet-orchestration.md), [ADR-0021](../adr/0021-autonomous-merge.md))
- [ ] Generate project-specific `CLAUDE.md` (≤200 lines)
- [ ] Verify the plugin loads on first session (`claude plugin list` shows `ai-team@agentic-dev-environment` enabled)

## 11. Execution contexts — Cowork vs CI

The platform's agents run in two distinct execution contexts. Each agent's frontmatter declares its `primary_context`; some agents have **enhanced capabilities when invoked from Cowork** because Cowork exposes MCP connectors that GitHub Actions runners do not.

### The two contexts

| Context | When | Has access to |
|---|---|---|
| **Cowork** | Interactive (you're at your desk talking to Claude) or scheduled-via-Cowork tasks | Memory across sessions; MCP connectors (Slack, Linear/Jira/Atlassian, Notion, GitHub, calendar, email, etc.); desktop notification capability; full file/bash access to your workspace |
| **CI** | GitHub Actions invokes the agent via `anthropics/claude-code-action@v1` on a trigger (PR, push, tag, schedule) | The repo content; AWS via OIDC; secrets configured in the GitHub environment; GitHub Issues / PR APIs; whatever's wired in the workflow YAML |

### Ca