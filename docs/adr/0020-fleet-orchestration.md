# ADR-0020: Fleet orchestration — running the autonomous loop across the portfolio

- **Status:** Accepted
- **Date:** 2026-05-22
- **Deciders:** Jason Tilley (with AI architectural review)
- **Tags:** ai-workflows, ci-cd, orchestration, distribution

> **Amended by [ADR-0030](0030-all-dispatch-through-promoter.md):** dispatch routing changed — all implementer dispatch now goes through the promoter (no direct bypass). See the *Impacted ADRs* table in ADR-0030 for the specific change to this ADR.

> **Format:** MADR 4.x with the platform's three extensions. This is a **bundled-sub-decision** ADR — five coupled decisions about running one loop across many repos.

## Context and Problem Statement

[ADR-0017](0017-async-orchestration.md) designed the autonomous loop — scheduling, concurrency, routing, the triage-bot promoter — but designed it for *a repo*, singular. [ADR-0018](0018-workflow-distribution.md) distributed *event-driven* workflows (PR review, the implementer) as reusables with a per-repo caller stub. [ADR-0019](0019-team-self-modification.md) made the platform repo the team's "self" and built the project→platform *reported*-flaw channel. None of the three asked the question the portfolio now forces: **does the loop's scheduled scan-and-promote cycle run once across the whole portfolio, or once per repo — and if once, how does it reach the other repos?**

The de-facto answer was never decided. `triage-scan.yml` exists only on the platform repo, and its promoter pass runs `gh issue list` with no `--repo` — so it scans only the platform repo's own issues. The result, measured 2026-05-22: ~105 agent-discovered findings sit open across the eight project repos, 0 promoted, 0 fix PRs in flight, 0 merges in seven days. A `source:sentry` P0 (game-night-pwa #81) has been stuck seven days. The loop has intake — reviewers file findings in each repo — and no throughput. How should orchestration run so that one team's loop actually moves work across the whole portfolio?

## Decision Drivers

- One human, one team, many projects — the loop must serve the whole portfolio without N copies of the machinery to herd.
- Throughput, not just intake — a finding must flow discovered → promoted → implemented → merged, in any repo.
- Two targets — the loop acts on project codebases *and* on the team's own process when a platform workflow breaks.
- Determinism over silent failure — the P0 #81 dead-end (a label that triggered nothing) must not be reproducible.
- Don't strand the nit tier — ADR-0016's `deferred-until-adjacent` findings must actually get cleaned, not wait on coincidence.
- Reuse the existing primitives — one cron, issues, labels, reusable workflows, ADR-0019's flaw channel. Don't invent infrastructure.
- Solo-dev: one place to fix the loop, one place to watch it.

## Considered Options

A bundle of five sub-decisions:

1. **Loop topology** — one central fleet-reaching loop, or one loop per repo?
2. **Cross-repo trigger** — how does the central promoter start a project's implementer?
3. **Fleet-dispatch credential** — how does the platform repo get write access into the project repos?
4. **Detected-flaw channel** — how does a *broken* (not merely reported) platform workflow reach the team?
5. **Deferred-nit handling** — how do low/nit findings actually get cleaned? (Amends ADR-0016.)

## Decision Outcome

We chose the bundle:

- **Sub-decision 1 → One central fleet-reaching loop.** `triage-scan.yml` stays a single cron on the platform repo; its promoter pass scans and promotes across every project repo. `severity:high` joins promoter eligibility; the ADR-0017 throughput cap is applied portfolio-wide.
- **Sub-decision 2 → Dispatch-triggered.** The promoter applies `ready-for-implementer` as durable state and then explicitly dispatches the target repo's `claude-implementer.yml` via `workflow_dispatch`. The label records intent; the dispatch is the trigger. Because an App-applied label event *does* cascade (ADR-0018), each `claude-implementer.yml`'s label-triggered `initial` job must ignore `ready-for-implementer` when a **bot** applied it — otherwise the App-applied label and the dispatch both fire and the issue is implemented twice. The bot promotion path is the dispatch; the label-trigger path is reserved for a human manually promoting. `source:sentry` and `severity:critical` auto-pickup are unaffected (they trigger regardless of who applied them).
- **Sub-decision 3 → One credential, typed as a GitHub App.** ADR-0019's feedback credential is *widened* — not duplicated — to `Issues: read+write` and `Actions: write` across the project repos, and reconstituted as a GitHub App installation token in place of the PAT ADR-0019 planned. One credential serves both the flaw-marker scan and the fleet dispatch; the credential count stays at two.
- **Sub-decision 4 → ci-health goes fleet-wide.** The watcher — today a platform-repo-only workflow — observes every repo's platform-sourced workflows; a detected breakage is filed as a platform-repo issue and handled by ADR-0019's self-modification path. It complements 0019's *reported*-flaw channel: detection where 0019 had only reporting.
- **Sub-decision 5 → Two-PR deferred-nit handling.** A dispatched run produces a lean fix PR (directory-adjacent nits, cap `min(⌊total/2⌋, 4)`) and a sidecar cleanup PR (the rest, cap `max(⌊total/2⌋, 8)`, chunked at 12 issues per PR). A spare-capacity backstop sweep drains repos that get no qualifying dispatch. Amends ADR-0016.

The bundle is internally consistent: sub-decision 1 sets the shape; 2 and 3 make it mechanically possible and bounded; 4 extends the same central loop to the team's own process; 5 ensures the loop drains every tier of work, not only the promotable middle. The governing principle: **one loop, reaching every repo, with an explicit and observable trigger at every cross-repo hop — because a silent hop is how P0 #81 died.**

## Consequences

### Positive

- The ~105-finding backlog becomes reachable: the promoter sees it, the implementers get dispatched, work flows.
- Every cross-repo hop is explicit and logged — a failed dispatch shows up in the scanner run; no more silent label dead-ends.
- The team's own broken workflows are detected, not just reported — closing the gap where a reusable could break fleet-wide unnoticed.
- The nit tier drains on a schedule instead of waiting for coincidental adjacency; ADR-0016's "stable code carries nits forever" hole is closed.
- One cron, one promoter, one queue — one place to fix, one place to watch.

### Negative

- The widened credential is reconstituted as a GitHub App — registration and fleet-wide installation, more setup than the permission edit a PAT would need. Accepted — a long-lived PAT that can dispatch any workflow and write issues across the portfolio is the system's fattest key; an App's short-lived installation tokens are the right trade for the loop's most powerful credential.
- The central scanner now does materially more work per run (fleet scan + N dispatches). Accepted — it is bounded by the ADR-0017 throughput cap, and the scan itself is read-cheap.
- Two PRs per dispatched run (fix + sidecar) roughly doubles PR-review load. Accepted — the reviews are the gate that makes auto-merge safe, and a cleanup PR of pure nits is a light review.
- A fleet-wide failure mode now exists — a bad App token stalls every repo at once. Mitigated — the fleet ci-health watcher surfaces it, and the loss is latency, not corruption (branch isolation, ADR-0017).

### Neutral

- The per-project event-driven path is unchanged — `claude-implementer.yml` still fires on `issues: opened` for human-filed work (ADR-0017) and still runs as a reusable caller stub (ADR-0018). Fleet orchestration adds a dispatch entry point; it removes nothing.
- ADR-0019's project→platform boundary is untouched. The widened credential writes platform→project — the *expected* direction. The forbidden direction (project→platform write) still has no token.
- ADR-0019's feedback credential is amended: widened from `Issues:read` to `Issues:read+write` + `Actions:write`, and re-typed from a planned PAT to a GitHub App. The credential count is unchanged — ADR-0019's two-credential model stands; only this credential's scope and type change.
- The legacy per-project `claude-triage-bot.yml` (event-triage on issue-open) is retired — the central scan supersedes its scanning role, and ADR-0017's `issues: opened` path already covers human-filed triage.

## Pros and Cons of the Options

### Sub-decision 1: Loop topology

| Option | Pros | Cons |
|---|---|---|
| **One central fleet-reaching loop** (chosen) | One cron, one promoter, one queue; global prioritisation possible; one place to fix and watch | Needs a platform→project write credential; a central failure touches every repo |
| One loop per repo | Fault-isolated; no cross-repo credential | N crons to herd and keep in sync; no global priority; the dashboard has nothing central to read; N× the drift surface |
| Status quo — central cron, platform-blind | No change | The clog: the promoter sees one repo of nine; 105 findings unreachable |

### Sub-decision 2: Cross-repo trigger

| Option | Pros | Cons |
|---|---|---|
| **Dispatch-triggered** (chosen) | Deterministic — `workflow_dispatch` always fires; success/failure visible in the scanner log; inputs passed directly | Two actions (label + dispatch); the scanner must know each implementer's workflow filename |
| Label-triggered (cascade) | One action; the label is both state and trigger; uniform with the human manual-label path | Depends on a cross-repo label event cascading from an App identity — unverified, and the prime suspect for P0 #81 sitting dead seven days |

The label is applied either way — it is the queue's durable state, read by the dashboard and required for idempotency. "Label-triggered" therefore saves only the dispatch call, and that call is exactly what buys determinism.

### Sub-decision 3: Fleet-dispatch credential

| Option | Pros | Cons |
|---|---|---|
| **Widen the feedback credential, typed as a GitHub App** (chosen) | One credential for one principal; installation tokens auto-expire (~1 h), shrinking the blast radius of the loop's most powerful key; fine-grained per-repo install; GitHub's intended mechanism for one system acting on many repos | An App to register and install fleet-wide — more setup than editing a PAT |
| Widen the feedback credential, kept as a PAT | A two-minute permission edit; no new infrastructure | A long-lived key that can dispatch any workflow and write issues across the whole portfolio; user-scoped |
| A separate read token plus write token | Notionally least-privilege | Theatre — `triage-scan.yml` is the only principal and holds both; a leak vector exposing one exposes both. Two credentials to rotate for no real isolation |

### Sub-decision 4: Detected-flaw channel

| Option | Pros | Cons |
|---|---|---|
| **Fleet-wide ci-health → platform issue** (chosen) | Reuses an existing, working watcher; feeds ADR-0019's self-modification machinery; detection covers what reporting misses | Cross-repo run reads add an App-token dependency — a small erosion of ci-health's otherwise zero-dependency design rule |
| Rely on reported flaws only (ADR-0019 as-is) | No new work | A reusable can break fleet-wide with no human or agent filing a `process-flaw` for it — silent |
| A new dedicated fleet-CI monitor | Purpose-built | Reinvents ci-health; another workflow to maintain |

### Sub-decision 5: Deferred-nit handling (amends ADR-0016)

| Option | Pros | Cons |
|---|---|---|
| **Two PRs — lean fix + sidecar cleanup** (chosen) | The functional fix stays reviewable; nits drain on every dispatched run; cold-code nits no longer wait on adjacency | Two PRs and two reviews per dispatched run |
| One PR — bundle everything | One review | A fix PR becomes a grab-bag; one bad nit blocks the real fix — the failure ADR-0016's cap of 2 was guarding against |
| Keep ADR-0016 as-is (adjacent, cap 2) | No change | "Stable code carries nits forever" — ADR-0016's own admitted, unmitigated hole |

## Amendment to ADR-0016

ADR-0016 Rule 2 capped deferred-nit bundling at a flat 2 per PR, scoped to the directory the implementer was already working in, and left cold-code nits to a quarterly `/ai-team:sweep-deferred` command that was never built. ADR-0020 replaces the flat cap with dynamic caps and adds a second drainage path:

- `total` = the count of open `deferred-until-adjacent` issues in the target repo at dispatch time.
- **Fix PR** bundles directory-adjacent nits, cap `min(⌊total/2⌋, 4)`.
- **Sidecar cleanup PR** drains the remainder, cap `max(⌊total/2⌋, 8)`, split into chunks of at most 12 issues per PR.
- **Backstop:** when a window's throughput cap leaves spare capacity, the promoter dispatches a cleanup-only run for the repo with the oldest deferred backlog — so a repo that never receives a qualifying dispatch is still drained.

ADR-0016 is amended, not superseded; its calibration philosophy and Sentry-priority rule stand unchanged.

## Implementation notes

- **Affected workflows:** `triage-scan.yml` (fleet scan + promote + dispatch + spare-capacity sweep); `ci-health.yml` (widen the watch from platform-repo-only to the whole fleet); each project's `claude-implementer.yml` (add a `mode` input and a `cleanup-sweep` job; guard the `initial` job so a bot-applied `ready-for-implementer` does not double-trigger alongside the dispatch).
- **Affected agents:** `triage-bot.md` (fleet promoter logic, throttle, dispatch); `implementer.md` (two-PR nit handling and the dynamic caps).
- **Retired:** the legacy `claude-triage-bot.yml` event-triage workflow in the project repos.
- **Credential:** ADR-0019's feedback credential is widened to `Issues: read+write` + `Actions: write` across the project repos and reconstituted as a GitHub App installed fleet-wide; `triage-scan.yml` mints a per-run installation token. The existing `FEEDBACK_READ_TOKEN` secret is superseded by the App's credentials (App ID + private key). The App is registered and installed by the human — the loop cannot self-provision credentials (ADR-0019).
- **Standards:** Standard 10 (AI workflows) gains a fleet-orchestration section; Standard 12 (self-modification) records the detected-flaw channel alongside the reported-flaw channel.
- **Verification:** promote a test finding in a project repo end-to-end to a dispatched implementer run; trip a platform-sourced workflow and confirm ci-health files the platform issue.

## Links

- [ADR-0016 — finding lifecycle](0016-finding-lifecycle-calibration-deferral.md) — amended here (deferred-nit caps).
- [ADR-0017 — async orchestration](0017-async-orchestration.md) — the loop this ADR makes fleet-wide.
- [ADR-0018 — workflow distribution](0018-workflow-distribution.md) — reusables, caller stubs, the `GITHUB_TOKEN` cascade rule.
- [ADR-0019 — team self-modification](0019-team-self-modification.md) — the reported-flaw channel this ADR complements; the feedback credential this ADR widens and re-types.
- [Standard 10 — AI workflows](../standards/10-ai-workflows.md); [Standard 12 — self-modification](../standards/12-self-modification.md).
- triage-scan run `26278440435` (2026-05-22) and the 105-finding backlog measurement that motivated this ADR.
