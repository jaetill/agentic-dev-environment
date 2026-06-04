# ADR-0021: Autonomous merge of implementer fix PRs

- **Status:** Accepted — ratified by human merge of PR #51, 2026-05-23; auto-merge gate re-keyed from work type to work origin by [ADR-0023](0023-origin-based-autonomy-boundary.md)
- **Date:** 2026-05-23
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, governance, ci-cd, orchestration, autonomy

> **Amended by [ADR-0039](0039-merge-is-autonomous-human-gate-moves-to-prod.md):** condition 1 ("linked issue is machine-origin") is relaxed to "linked issue is present" — origin no longer gates the merge. The human checkpoint moves off the merge and onto test→prod promotion for user-facing features (#179). The other conditions (checks green, no `requires-adr`) and the firewall holds are unchanged.

> **Format:** MADR 4.x with the platform's three documented extensions. Single-decision ADR. This ADR *applies* an existing decision (ADR-0003) to a new path — it does not reopen the approval model.

## Context and Problem Statement

ADR-0003 settled the platform's approval model in week one: **AI has full shipping authority; the human gates only architectural decisions, via ADRs.** It explicitly rejected "human approves every PR" as a gate that "rots under fatigue." Under ADR-0003 a PR that passes the AI review battery and trips none of the five ADR-gated categories merges without waiting on a human.

That model was wired for release PRs (ADR-0010 — `release-captain` auto-merges them) but never for the autonomous implementer's fix PRs. So as the fleet loop (ADR-0020) came online and implementers began opening fix PRs, those PRs pooled unmerged — not by any policy, but because no job merges them. The loop runs to its last stage and stops.

Two things need settling:

1. **Wire it.** Specify the job and gate that auto-merge implementer fix PRs, the way `release-captain` already does for release PRs.
2. **Confirm the closed loop.** ADR-0003 (2026-05-08) predates the autonomous implementer. Its "AI auto-merges" assumed a *human* or a Claude *session* authored the PR — a person stood at the start of the cycle. The loop removes that: the implementer agent authors the PR, the reviewer agents approve it, a job merges it. This ADR records that we accept the fully-closed loop for routine fixes, and bounds it.

## Decision Drivers

- **ADR-0003 already governs.** This ADR applies that decision; it does not re-decide the approval model.
- **Close the loop.** ADR-0020's fleet orchestration is not worth its cost if throughput pools at the last stage.
- **Commander's intent.** The human owns direction and scope; the team executes routine work within it. The boundary must be *mechanical* — decidable from labels and check state, not judged at merge time.
- **Preserve the floor.** ADR-0019 — platform self-modifications reach `main` only by human merge — is untouched.

## Considered Options

- **Option A:** A loop workflow job auto-merges qualifying implementer fix PRs.
- **Option B:** Claude auto-merges qualifying PRs from an interactive session.
- **Option C:** Leave the gap — implementer PRs keep waiting on a hand merge.

## Decision Outcome

Chosen option: **Option A.** A job in the `triage-scan` promoter — the platform-central loop, running as the fleet App — auto-merges an implementer fix PR when, and only when, **all** of the following hold:

1. The PR is **authored by the implementer agent** and closes an issue labelled **`defect`** or **`bug`** — not `feature-request` (those keep the ADR-0017 plan-gate, where the human approves the approach first).
2. **Every required check passes** — this is ADR-0003's AI review battery. `code-review` and `security-review` are hard gates (a Critical/High finding → `VERDICT: BLOCK` → no merge); `functional-test` and the rest pass.
3. The PR carries **no `requires-adr:*` label** — this is ADR-0003 sub-decision 5: the five ADR-gated categories (destructive migration, new dependency, security-relevant, API contract, schema) route to the human, unchanged.
4. The repo is a **project repo**, not the platform repo (ADR-0019's floor).

> **Conditions 1 and 4 amended by [ADR-0023](0023-origin-based-autonomy-boundary.md) (2026-05-25).** The gate is re-keyed from work *type* to work *origin*. **Condition 1** becomes: the linked issue is **machine-origin** — it carries `source:sentry`, `source:cloudwatch`, or `origin:internal-review` and is not human-authored. Human-origin PRs (feature *or* bug) no longer auto-merge — they take a human checkpoint. **Condition 4** becomes: routine/mechanical platform-repo fixes now qualify; only compositional self-changes (ADR-0019 as narrowed by ADR-0023) are excluded. Conditions 2 (checks green) and 3 (no `requires-adr`) are unchanged.

Conditions 2 and 3 are not new — they are ADR-0003's existing mechanism. Condition 1 defers to ADR-0017's feature plan-gate; condition 4 defers to ADR-0019. What this ADR genuinely adds is the conditions-as-a-job for the implementer path, and the explicit acceptance of the closed loop.

This is the operational form of commander's intent: a `defect`/`bug` fix within the implementer's inherent scope cap (per [ADR-0026](0026-agentic-implementer.md)) is routine and ships; anything that redefines scope arrives as a `feature-request` (→ plan-gate) or trips `requires-adr` (→ human). The "ai-teacher should add financial planning" case reaches the human by a path that already exists.

**Pause control.** The job reads a repo/org variable `AUTONOMOUS_MERGE` (default `on`); setting it `off` halts auto-merge fleet-wide with no code change.

## Consequences

### Positive

- The loop closes — routine defect fixes ship on the loop's own cron, no session open. The dashboard's `merged` figure becomes live.
- The human's attention is spent only where ADR-0003 always intended it: direction, scope, ADR-gated decisions.

### Negative

- **The cycle is now fully closed for routine fixes** — agent authors, agents review, a job merges, no human in the loop. This is the real step beyond ADR-0003, which assumed a human or session author. Accepted because the blast radius is bounded (scope cap), the change is gated (`security-review` is hard; ADR categories excluded), every change is a revertable PR on the dashboard, and `AUTONOMOUS_MERGE=off` is a one-flip stop.

### Neutral

- One new job in the `triage-scan` promoter, running centrally as the fleet App. `release-please` and human-authored PRs are excluded by the implementer-authored filter (PR author `app/claude`).

## Pros and Cons of the Options

### Option A: A loop workflow job (CHOSEN)

- ✅ Pro: closes the loop on cron — it ships while Jason sleeps, which is the point of fleet orchestration. Symmetric with `release-captain`'s existing release-PR auto-merge.
- ✅ Pro: the merge decision is a deterministic, auditable gate.
- ❌ Con: no Claude judgement at merge time — only the gate conditions. Accepted: the gate *is* the boundary, and judgement was applied upstream by the review agents.

### Option B: Claude auto-merges from a session

- ✅ Pro: a judgement layer at merge time.
- ❌ Con: runs only when a session is open — it does not close the loop; it is the status quo with a faster human.

### Option C: Leave the gap

- ❌ Con: contradicts ADR-0003 in practice, the loop never closes, ADR-0020's investment stays half-realised. This is today's accidental state, not a chosen policy.

## Implementation notes

- **Workflow:** a new `auto-merge` job in `.github/workflows/triage-scan.yml` (the central promoter). It mints the fleet App token, sweeps the project fleet for green qualifying implementer PRs, and calls `gh pr merge --squash` on each.
- **Placement — central, not the reusable.** An earlier draft put this job in the `claude-pr-review` reusable. Implementation surfaced the flaw: a per-repo reusable job could only merge with `GITHUB_TOKEN`, and a `GITHUB_TOKEN` merge triggers nothing downstream (ADR-0018) — release-please would never see it, so nothing would deploy. The merge must be performed by the fleet App (whose events cascade), and the App credential lives only on the platform repo — so the job lives in the platform-central `triage-scan` promoter, alongside the rest of the fleet-wide loop (ADR-0020). The Option-A decision is unchanged; only placement was refined.
- **Fleet App permissions:** the auto-merge job merges as the fleet App, which needs `contents: write` + `pull requests: write`. The App had been installed with only the promoter's `issues` + `actions` write; both write scopes were added to the App and the installation re-approved on 2026-05-23, before this job went live.
- **Gate inputs:** the type label on the linked issue (from the PR's `Closes #N`); the `gh pr checks` bucket states (a PR with zero checks does not qualify — the gate requires a non-empty green battery, not a vacuous pass); the `requires-adr:*` label set; the PR author; the `AUTONOMOUS_MERGE` variable. A per-run cap (`AUTONOMOUS_MERGE_CAP`, default 10) bounds merges per window.
- **Standard 10 (AI workflows)** gains a section on the implementer-PR auto-merge gate; the plugin's shipped copy is updated in lockstep.
- **ADR-0016** is amended — the finding lifecycle gains a terminal **merge** stage for the routine-fix path.
- **ADR-0003** gains a forward reference to this ADR.
- **Sequencing:** this ADR is ratified (human merge) before the job is implemented; the job is itself a platform self-modification and lands by human merge per ADR-0019.

## Links

- [ADR-0003 — CI/CD & approval model](0003-ci-cd.md) — the parent decision (AI shipping authority; AI auto-merges PRs). This ADR applies it to the implementer loop.
- [ADR-0010 — release management](0010-release-management.md) — precedent: `release-captain` already auto-merges release PRs.
- [ADR-0016 — finding lifecycle](0016-finding-lifecycle-calibration-deferral.md) — amended: gains the terminal merge stage.
- [ADR-0017 — async orchestration](0017-async-orchestration.md) — the feature plan-gate, this ADR's scope-change boundary.
- [ADR-0018 — workflow distribution](0018-workflow-distribution.md) — the `GITHUB_TOKEN` no-cascade rule; why the merge runs as the fleet App in the central promoter, not the per-repo reusable.
- [ADR-0019 — team self-modification](0019-team-self-modification.md) — the platform-repo human-merge floor, preserved.
- [ADR-0020 — fleet orchestration](0020-fleet-orchestration.md) — the loop this ADR closes.
- Mission command / *commander's intent* — subordinates act on the intent, not on per-action approval.
