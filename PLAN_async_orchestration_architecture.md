# Plan: async-orchestration architecture for the ai-team plugin

**Captured:** 2026-05-20 morning.
**Revised:** 2026-05-20 — Jason's 7 decisions baked in + Claude Code agent-teams research folded in.
**Status:** Draft for review. Becomes ADR-0017 candidate after Jason's feedback.
**Source:** Route more work through `implementer` (centralize), but don't let async pickup race interactive sessions or conflict when multiple humans + agents are active. Sentry work should be slow (clustered), not reactive. Bulk work runs on timers while Jason is at work or asleep, so the queue is done when he sits down.

## TL;DR

Correctness comes from **optimistic concurrency** — branch isolation + PR-based integration, which is just git's native model. Everything else is scheduling, calibration, and visibility on top of that foundation.

Four pillars:

1. **Branch isolation (the correctness foundation).** Every async actor works on its own `issue-NNN` branch and integrates via PR. No actor ever pushes to a branch another actor or human is on. This — not a lock — is what prevents conflicts.
2. **Three time windows** (`interactive`, `work-hours` = Mon–Fri 09:00–12:00, `overnight` = 22:00–06:00). Async agents fire only in `work-hours` + `overnight`. Afternoons/evenings/weekends are `quiet` so the queue is settled when Jason gets home.
3. **Concurrency groups** (per area) — GitHub Actions native; only one async job touches a subtree at a time.
4. **CODEOWNERS + branch protection** — reviewer routing + merge gates. Lighter-weight than first thought, because the repo is public and the friend will fork (fork-PR flow already isolates external contributors).

Plus four disciplines: **work routing by source + type** (human-filed work bypasses the window and the promoter — only agent-discovered work is window-gated; human-filed *features* get a plan-gate, bugs don't), **triage-bot as the promoter** for agent-discovered work, **throughput backpressure** (concurrent-run + daily caps — no dollar budget needed, Jason is on Claude Max), and an **observability artifact**.

A dedicated session beacon is **explicitly deferred** — branch isolation makes it non-load-bearing. See Pillar 1's note.

Rollout: **A (concurrency + branch discipline) → B (windows + triage schedule) → C (Sentry debounce, deferrable) → D (CODEOWNERS) → E (dashboard)**.

## Decisions locked (Jason, 2026-05-20)

| # | Decision | Effect on plan |
|---|---|---|
| 1 | `work-hours` = Mon–Fri **09:00–12:00** America/Chicago (not 17:00) | Implementer runs mornings only; afternoon+evening are `quiet` so the queue is done when Jason gets home → "fresh session" feeling. |
| 2 | Token budget irrelevant — Jason on Claude Max | Drop dollar-denominated budget. Keep throughput caps (those are for conflict-avoidance, not cost). Friend uses their own tokens via fork. |
| 3 | **Never** auto-merge Jason's own PRs — only on explicit, on-demand human command | Jason's PRs always require a deliberate human merge action. Implementer-authored PRs may still auto-merge after reviewer approval (AI shipping authority, ADR-0003) — those aren't "Jason's PRs". |
| 4 | Friend's PRs require Jason approval | Standard. Reinforced by fork model — friend literally cannot push to the repo. |
| 5 | Beacon: best practice, not easiest | Best practice = optimistic concurrency (branch isolation). Dedicated beacon deferred as non-load-bearing. See Pillar 1. |
| 6 | **triage-bot is the promoter** | triage-bot applies `ready-for-implementer` on its scheduled scan (Tier 2 judgment). No separate promoter workflow. See "Severity-gated pickup." |
| 7 | Repo is already **public** (confirmed: `gh repo view` → `PUBLIC`) | Friend onboards via fork → PR. No collaborator access needed. CODEOWNERS becomes reviewer-routing polish, not an access gate → moves later in rollout. |
| 8 | Human-filed **feature** issues get a **plan-gate**; human-filed **bugs** do not | Implementer posts its intended approach as an issue comment, waits for Jason's 👍, then implements; PR auto-merges after reviewer approval. Bugs skip the gate (the fix is the fix). See "Work routing & pickup." |

## Problem statement

Today's wiring is mostly aspirational:

- `claude-implementer.yml` fires on `issues: types: [labeled]` and `issue_comment: types: [created]`. Any label change can wake it. No concurrency control, no schedule.
- `triage-bot` has no scheduled run anywhere (`grep schedule:` across all workflows: zero matches as of 2026-05-20).
- Sentry → triage-bot pipeline isn't wired.
- No CODEOWNERS file.
- No concurrency groups on any async workflow.

Failure modes the design must prevent:

| Failure | What goes wrong | Defused by |
|---|---|---|
| **Race conflict** | Implementer pushes to a branch Jason is editing | Pillar 1 — branch isolation. Each actor owns its branch. |
| **Async stomp** | Implementer files PR for a bug Jason just fixed | Pillar 2 — windows. Implementer runs when Jason is typically away; residual collisions surface as a stale issue, cheap to close. |
| **Two async jobs race** | Two implementer runs edit the same area | Pillar 3 — concurrency groups serialize per area. |
| **Sentry alert spam** | One error fires 14× during a deploy | Pillar 4 — debounce buffer + clustered scan. |
| **Multi-author conflict** | Friend's PR + Jason's PR touch the same file | Optimistic concurrency — second-to-merge resolves a normal git conflict. CODEOWNERS routes review. |
| **Surprise commit** | Jason opens laptop to 8 overnight merges | Pillar 2 — bounded windows; Pillar E — dashboard shows what happened. |

## Design goals (priority order)

1. **Conflict-resilient.** Multiple authors (human, agent, mixed) work without races. Achieved by branch isolation, not locking.
2. **Predictable.** Jason knows when async work happens. No surprises.
3. **Signal-calibrated.** Single-shot Sentry errors don't trigger fix-loops; clustered patterns do.
4. **Observable.** One page: what's queued, in-flight, done today.
5. **Backward-compatible.** Slash commands and sync work route exactly as they do today.

Cost is not a goal (Claude Max). Throughput caps exist purely to bound concurrency, not spend.

## The four pillars

### Pillar 1 — Branch isolation (the correctness foundation)

This is the load-bearing pillar. Everything else is scheduling and visibility on top of it.

**Rule:** every async actor works on its own branch and integrates via PR. Never push to a branch another actor or human holds.

- Implementer: branch `implementer/issue-NNN` per issue it picks up.
- triage-bot: never edits code — files issues only. No branch.
- Jason: his own branches, his own cadence.
- Friend: their fork; cross-fork PRs.

**Why this is the best-practice answer (Jason's decision #5).** The question "how do we stop two authors conflicting" is the question version control already solved. Git is optimistic concurrency: authors work in isolation, reconcile at merge. A *beacon* ("check if a human is active, defer") is *pessimistic locking* layered on top. Pessimistic locking is the right tool only when the cost of a conflict is high and unrecoverable — here it isn't: a conflict is a normal git merge conflict, surfaced at PR time, resolved in minutes.

**On the deferred beacon.** A beacon would add one thing branch isolation doesn't: "don't even *start* async work if Jason is mid-session, to avoid a wasted run that just conflicts." That's a cost/noise optimization, not a correctness need — and Pillar 2's windows already cover the bulk of it (implementer runs 09:00–12:00 + overnight; Jason's interactive sessions skew evening/weekend = `quiet`). The residual case is a Jason morning/weekend session overlapping the work-hours window. If that ever produces a real conflict, add a lightweight beacon then:

> **Deferred beacon design (build only if a real overlap conflict occurs):** a GitHub repo variable `INTERACTIVE_BEACON_AT`, ISO-8601 timestamp, written by a Cowork session hook each turn. Async workflows read it; if `now - beacon < 30min`, skip. This is functionally a TTL lease. A DynamoDB-item-with-TTL version is "more correct store" and reuses the OpenTofu-lock infra precedent — but DynamoDB TTL deletion isn't instant (AWS: up to 48h), so the consumer does a timestamp comparison either way. The store choice barely matters; the pattern (stored-expiry + consumer-side freshness check) is the same. Repo variable wins on simplicity if we ever build it.

### Pillar 2 — Time windows

Three windows. Each agent declares which it fires in.

| Window | Hours (America/Chicago) | Async work? |
|---|---|---|
| `interactive` | (only relevant if the deferred beacon is ever built) | No |
| `work-hours` | **Mon–Fri 09:00–12:00** | Yes — bounded throughput |
| `overnight` | Daily 22:00–06:00 | Yes — heavy lifting |
| `quiet` | everything else (afternoons, evenings, weekends) | No |

The morning-only `work-hours` window is deliberate (decision #1): implementer clears the queue while Jason is at work; by noon it stops; the afternoon/evening stays quiet so when Jason gets home the queue is settled and he gets a clean session.

Implementation: a window-check step gating each async workflow.

```yaml
- name: Window check
  id: window
  run: |
    hour=$(TZ=America/Chicago date +%H)
    dow=$(TZ=America/Chicago date +%u)
    if   [[ $hour -ge 22 || $hour -lt 6 ]]; then echo "active=true"  >> $GITHUB_OUTPUT
    elif [[ $dow -le 5 && $hour -ge 9 && $hour -lt 12 ]]; then echo "active=true" >> $GITHUB_OUTPUT
    else echo "active=false" >> $GITHUB_OUTPUT
    fi
```

Critical/High-severity issues are the one exception — they bypass the window and pick up immediately (an active security issue shouldn't wait for the morning window).

### Pillar 3 — Concurrency groups

GitHub Actions native. Each async workflow gets a concurrency group keyed to the area it touches. Research confirmed the policy:

```yaml
concurrency:
  group: implementer-${{ github.repository }}-${{ inputs.area || 'global' }}
  cancel-in-progress: false   # queue — never cancel; work-in-progress is sunk cost
```

`cancel-in-progress: false` is the documented best practice for sequential/stateful work (vs. `true` for CI where only the latest commit matters). Implementer's `area` derives from the issue's `area:*` label. Effect: 8 issues labeled at once get serialized per area — `area:frontend` waits for prior `area:frontend`; `area:lambda` runs in parallel. PR-time reviewers need no concurrency group (already scoped to one PR).

### Pillar 4 — Sentry debouncing

Today: Sentry webhook would hit triage-bot reactively → spam risk during deploys.

Proposed:

1. Sentry webhook → a thin receiver workflow that **only** buffers: appends the event to a single long-lived "Sentry buffer" issue per project (label `triage:buffer`).
2. **Scheduled triage-bot scan** — every 30 min during `work-hours`, once at the start of `overnight`. Reads the buffer, clusters by `event.fingerprint`, dedupes against existing open issues, and files a new issue only when a cluster crosses a significance threshold (count ≥ N, or impacted-users ≥ U, or novel fingerprint). Clears processed buffer entries.
3. Filed issues default `severity:medium`, promoted to `high` if user-impact crosses a threshold.

Net: single-shot deploy-time errors never become issues; clustered patterns become exactly one issue each.

### Pillar 5 — CODEOWNERS + branch protection

Repo is public; friend forks. The fork-PR flow already isolates external contributors (friend cannot push to the repo at all). So CODEOWNERS is **reviewer-routing polish**, not an access gate — which is why it moves later in the rollout.

Proposed `CODEOWNERS`:

```
*                          @jaetill
/plugins/ai-team/          @jaetill
/templates/_shared/        @jaetill
/.github/                  @jaetill
/docs/                     @jaetill
```

Branch protection on `main`:

- Require PR before merge; require code-owner approval.
- Require status checks: `validate`, `adr-format-check`, `agent-frontmatter-check`, `link-check`.
- No direct pushes.

Implementer agent prompt updated: "add the CODEOWNER of the touched area as a PR reviewer."

## Operational disciplines

### Work routing & pickup

The plan's first draft conflated two independent things: *severity* (how bad a bug is) and *work type* (bug vs. feature). They're separate axes. Routing depends on three things — **who filed it**, **what type it is**, and **how severe it is**.

**The governing principle:** the time-window exists for *surprise control* — it batches up *autonomously-discovered* work so it doesn't ambush Jason. Work Jason *explicitly requests* is never a surprise, so it bypasses both the promoter and the window.

| Source | Type | Promoter / window | Plan-gate | Pickup latency |
|---|---|---|---|---|
| Jason, in a live session | any | n/a — head agent does it directly | n/a | seconds |
| Jason, filed issue | **bug** | none — `ready-for-implementer` on creation; bypasses window | no | minutes |
| Jason, filed issue | **feature** | none — `ready` on creation; bypasses window | **yes** | minutes to first plan comment |
| triage-bot / reviewer-discovered | bug, Medium | triage-bot promotes after one cycle; window-gated | no | 30 min – next window |
| triage-bot / reviewer-discovered | bug, Low/Nit | no promotion — opportunistic bundling only | no | days–weeks |
| any source | bug, **Critical/High** | no promotion needed; **bypasses window** | no | minutes |

So: **a human-filed idea never waits for 0900.** The window only ever gates agent-discovered work.

**The feature plan-gate (decision #8).** When implementer picks up a human-filed issue labelled `type:feature`:

1. Implementer picks it up within minutes (it's `ready` on creation — no window, no promoter).
2. Before writing code, it posts its **intended approach** as an issue comment — the design call, scope, files it expects to touch.
3. It waits for Jason's 👍 (reaction or comment). No timeout — a feature waits for its human; it does not proceed on a timer.
4. On approval, implementer implements. The PR **auto-merges** after `code-reviewer` + `security-reviewer` approve — the key call (the approach) was already made at step 3.
5. **Bypass:** a `skip-plan` label, or Jason pre-writing the approach in the issue body, skips straight to step 4.

This puts the human checkpoint exactly at the *approach* — Jason's Discernment zone — and keeps him out of execution. A `type:bug` issue skips the gate entirely: the fix is the fix.

**triage-bot is the promoter (decision #6) — for agent-discovered work only.** On its scheduled scan, triage-bot applies `ready-for-implementer` to eligible `severity:medium` agent-filed issues. Eligibility:

- The issue has survived **at least one full triage-bot cycle** since filing — triage-bot never promotes an issue in the same scan that filed it. Gives Jason a triage window equal to the scan interval (≈30 min in work-hours; overnight issues are visible next morning before eligible).
- The issue is well-specified enough to hand off. This is a **Tier 2 (Sonnet) judgment** within triage-bot — promotion is reasoning, not classification.
- Jason can pre-empt: manually applying `ready-for-implementer` promotes now; closing or downgrading removes eligibility.

Human-filed issues do **not** go through the promoter — filing them *is* the triage.

**Label convention this needs:** `type:bug` / `type:feature` on every issue. triage-bot applies `type:bug` to everything it files. Humans pick the type when filing (issue template default: `type:feature`, since humans mostly file ideas; bugs they hit interactively get fixed in-session).

### Backpressure (throughput only — no dollar budget)

| Limit | Default | Adjustable via |
|---|---|---|
| Concurrent implementer runs (global) | 2 | repo variable `IMPLEMENTER_MAX_CONCURRENT` |
| Implementer runs per day | 12 | repo variable `IMPLEMENTER_MAX_DAILY` |
| Triage-bot issues filed per day | 10 | repo variable `TRIAGE_MAX_DAILY` |

When a limit is hit: workflow logs the reason, exits `skipped`, comments on the issue ("deferred — daily cap reached, resumes next window"). These caps exist to bound concurrency and surprise, not cost.

### Merge authority

- **Jason's own PRs:** never auto-merge. A human must explicitly merge, on demand (decision #3).
- **Implementer-authored PRs:** may auto-merge after `code-reviewer` + `security-reviewer` approve and CI is green (AI shipping authority, ADR-0003). This is what makes "queue is done when Jason gets home" actually true.
- **Friend's cross-fork PRs:** always require Jason's approval (decision #4).

### Observability

A live artifact (via `create_artifact`) Jason refreshes — beacon/window state, queue by severity, in-flight PRs with age, last-24h merges, Sentry buffer depth. Pulls from GitHub on each open; no backend.

## Agent teams — researched, deliberately not in the core design

Claude Code shipped an experimental feature ([agent teams](https://code.claude.com/docs/en/agent-teams)): multiple Claude Code instances coordinating via a shared task list + mailbox, enabled by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

**It does not solve this plan's problem.** Agent teams is for *interactive parallel work* — "spawn 3 teammates to review this PR while I watch." It has no notion of schedules, time windows, or the human-away case. The async pipeline here runs as headless GitHub Actions, not as a Claude Code team. Folding agent teams into the orchestration design would be using a new feature where it doesn't fit.

**Where it IS useful for Jason — interactively:**

- Parallel code review (one teammate per lens: security / performance / tests).
- Competing-hypothesis debugging (teammates each test a theory, argue).
- Cross-layer features (frontend / backend / tests, one teammate each).

**Two facts worth keeping:**

1. Our 14 plugin agents are reusable as agent-team teammates with zero extra work — "reference a subagent type from any scope; the teammate inherits its system prompt, tools, model." Define once, use as delegated subagent *and* as teammate.
2. Caveat for Jason's setup: split-pane mode needs tmux or iTerm2 and is **not supported in Windows Terminal / VS Code terminal**. On Windows, agent teams run in in-process mode (Shift+Down to cycle teammates). Workable, just not the split-pane view.

Recommendation: leave agent teams out of the orchestration build; mention it in the platform docs as an interactive option. Revisit if it graduates from experimental.

## Rollout phases

Order reflects the locked decisions: correctness first, the "runs while away" behavior second, friend-onboarding polish later (fork model means it's not a gate).

### Phase A — Concurrency groups + explicit branch-isolation discipline (1 PR)

The correctness foundation. Highest impact, lowest risk.

- `.github/workflows/claude-implementer.yml` — add `concurrency:` block keyed by area.
- `plugins/ai-team/agents/implementer.md` — make the `implementer/issue-NNN` branch rule explicit in Process; add the area-derivation rule.

### Phase B — Time windows + triage-bot scheduling + routing (1–2 PRs)

The behavior Jason asked for: bulk work on timers, queue settled by afternoon; human ideas never wait.

- New `.github/workflows/triage-scan.yml` — `schedule:` crons (every 30 min in the 09:00–12:00 window; once at 22:00). Calls triage-bot.
- Window-check step added to `claude-implementer.yml` and `triage-scan.yml` — but only gating *agent-discovered* work; human-filed issues skip it.
- `type:bug` / `type:feature` label convention + an issue template that defaults humans to `type:feature`.
- `plugins/ai-team/agents/triage-bot.md` — add the promoter logic (eligibility rule, one-cycle delay, Tier 2 judgment); always apply `type:bug` to filed issues.
- `plugins/ai-team/agents/implementer.md` — the routing table: human-filed bypasses window+promoter; `type:feature` triggers the plan-gate (post approach → await 👍 → implement); `type:bug` skips the gate; Critical/High bypass window; `skip-plan` label bypasses the gate.

### Phase C — Sentry debouncing (2 PRs — deferrable)

Low urgency; current Sentry volume is small. Build when volume justifies it.

- New `.github/workflows/sentry-webhook-receiver.yml` — buffers events.
- triage-scan.yml extended to process the buffer.
- `plugins/ai-team/agents/triage-bot.md` — buffer-reading + clustering logic.

### Phase D — CODEOWNERS + branch protection (1 PR, mostly text)

Not a gate (fork model already isolates the friend) — this is reviewer-routing + merge-protection polish.

- New `CODEOWNERS` at repo root.
- Branch protection rules (GitHub UI, or IaC if branch-protection-as-code is judged worth it).
- `plugins/ai-team/agents/implementer.md` — "add area CODEOWNER as PR reviewer."

### Phase E — Observability dashboard (1 artifact)

Live artifact showing queue + in-flight + done-today. Build last; makes the rest legible.

## Decisions still open

1. **Sentry significance thresholds** (Pillar 4: count N, impacted-users U) — needs a look at real Sentry volume to set sanely. Defer until Phase C.
2. **Branch-protection-as-code?** — Phase D is faster via GitHub UI, cleaner via Terraform/API. Worth an ADR only if Jason wants the protection rules version-controlled.
3. **Whether to ever build the deferred beacon** — left as a "build if a real conflict occurs" trigger. No action needed now.

## Why this design follows best practices

- **Optimistic concurrency over locking** — version control's native model; branches + PRs are the conflict-resolution mechanism. Pessimistic locking (a beacon) is reserved for high-cost-irrecoverable conflicts, which this isn't.
- **Concurrency groups** — GitHub's documented pattern; `cancel-in-progress: false` for sequential/stateful work matches the [GitHub Actions concurrency docs](https://docs.github.com/en/actions/using-jobs/using-concurrency).
- **Debouncing** — standard alerting pattern (PagerDuty grouping, Alertmanager `group_wait`/`group_interval`).
- **Time-window batch processing** — classic operational pattern (ETL blackout windows, DBA maintenance windows).
- **CODEOWNERS + protected branches + fork-PR** — GitHub's canonical multi-author model, battle-tested at scale.
- **Calibration + deferral** — already codified in ADR-0016; this plan extends it (triage-bot as promoter) rather than replacing it.
- **Backpressure** — standard producer/consumer pattern; here throughput-axis only, since cost isn't a constraint.

## Expected outcome

After Phases A, B, D land:

- Jason leaves for work; implementer clears the *agent-discovered* queue 09:00–12:00 and overnight.
- A feature idea Jason files from his phone mid-day gets picked up within minutes — implementer posts its approach, Jason 👍s it on a break, and it's built and merged by the time he's home. It never waits for the next window.
- Afternoons/evenings are quiet of *autonomous* work — Jason comes home to a settled queue and a fresh session.
- Friend forks, runs their own Claude sessions, files cross-fork PRs; conflicts (if any) are normal git merges, and Jason approves every external merge.
- Jason's own PRs never merge without him; implementer's feature PRs auto-merge only after Jason approved the approach.
- Sentry storms produce one issue per cluster (after Phase C).

Phase E gives Jason a single glance-able page for "what happened while I was away."
