# ADR-0054: Fleet orchestration stays plan-as-code in GitHub Actions — defer literal dynamic-workflow adoption

- **Status:** Accepted
- **Date:** 2026-06-27
- **Implementation:** N/A (no code changes required) — this ADR affirms the current architecture and records the triggers that would reopen the decision. The artifact *is* the documentation.
- **Deciders:** Jason Tilley
- **Tags:** ai-workflows, orchestration, ci-cd, governance

> **Format:** MADR 4.x with the platform's three extensions. Single-decision ADR.

## Context and Problem Statement

The Claude Code Advanced Patterns webinar (mined in #251) promotes **dynamic workflows / plan-as-code**: moving an orchestration plan *into a script the runtime executes* — resumable, auditable, bounded (≤1000 agents/run), and able to apply a repeatable quality pattern such as **independent agents adversarially reviewing each other's findings before they're reported**. Issue #588 asks whether the platform should codify the **fleet promoter / dispatch loop** and/or the **reviewer cross-check** as plan-as-code orchestration with adversarial cross-checking — and, critically, whether that means *literal* adoption (a Claude Code dynamic-workflow run) or a *conceptual borrow* (a deterministic orchestration script the loop calls).

The question only answers cleanly once the current architecture is described accurately, because the issue's framing ("the plan lives in an LLM context, not in inspectable code") predates the orchestration the fleet actually runs today:

- **The promoter is already plan-as-code.** `triage-scan.yml` decides dispatch with *deterministic shell* — bot/severity eligibility filters, the one-cycle survival check, `ready-for-implementer` as durable queue state, adjacency bundling (ADR-0029), and a filename-based REST `workflow_dispatch` (ADR-0050). The auto-merge job is 100% deterministic with no LLM at merge time. The *only* LLM judgment in the loop is a single Tier-2 veto — "is this issue well-specified enough to hand off? when vague, leave it unpromoted." The plan is in inspectable code; an LLM fills one scoped judgment slot.
- **A guarded cross-check already exists.** ADR-0053's `review-lead` does substance-based dedup and on/off-diff routing, bound by a trust boundary it cannot cross: it may annotate but may **not** silently drop a peer's Critical/High, and the peer reviewer jobs remain *independent required status checks* (#601). What it is *not* is the webinar's specific pattern — *N independent agents each trying to refute a finding before it is filed*.
- **Dynamic workflows are a Claude-Code-*session* construct.** They run inside one `claude` session via the `Workflow` tool. The fleet loop runs as **headless `claude -p` in GitHub Actions**, where the load-bearing safety model is *independent required checks enforced by branch protection* — enforcement that lives outside any single agent's judgment.

So the decision is not "adopt plan-as-code" (we largely have) but: **do we replace the proven GitHub-Actions + bash orchestration with a literal dynamic-workflow construct, and/or build the one genuinely net-new idea (adversarial refutation of reviewer findings) now?**

## Decision Drivers

- **Independent enforcement is load-bearing and must not move into a single session's judgment.** Branch-protection required checks (the peer reviewer gates, `validate`, `adr-format-check`, the capability-delta and IaC firewalls) are enforced by the platform, not by an agent. #601 fought specifically to keep peers "report-only but MUST stay required checks." Collapsing orchestration into one dynamic-workflow session would make a single agent's reasoning the enforcement point.
- **The substantive benefits of plan-as-code are already realized.** The plan is inspectable (YAML + bash), the queue is resumable across runs (label-as-state survives any single run dying), the fan-out is bounded (concurrency caps + daily caps), and the cross-check is guarded.
- **Fit matters.** Dynamic workflows are a session construct; the loop is headless CI. The async-orchestration PLAN already rejected Claude Code *agent teams* on exactly this ground ("using a new feature where it doesn't fit") — the same logic applies to literal dynamic-workflow orchestration of a headless loop.
- **Minimal new machinery (pragmatism).** Rewriting working, deterministic bash as a Claude-session script adds a session dependency and blast radius to the running fleet for benefits it already has.
- **The one net-new idea must be justified by observed need.** Adversarial refutation of findings attacks false-positive noise — but only earns its cost if false positives are a *measured* problem. Building it speculatively is the "elegant solution to no real problem" trap.
- **Keep the door open.** The pattern has real value for a *bounded sub-task inside a single job*; the decision should not foreclose that.

## Considered Options

- Option A: **Conceptual borrow + reviewer-first** — keep orchestration as GitHub-Actions + bash; build an adversarial refutation pass that a finding must survive before `review-lead` files it.
- Option B: **Literal dynamic-workflow for the reviewer panel** — collapse the parallel reviewer jobs + consolidator into one `claude-pr-review` session running a `Workflow` script (fan-out → adversarially verify → synthesize → file).
- Option C (chosen): **Document & defer** — affirm the current plan-as-code architecture as already satisfying the pattern's intent; build nothing now; record explicit triggers that would reopen the decision.
- Option D: **Rewrite the promoter as plan-as-code** — codify the promoter/dispatch loop itself as a dynamic-workflow run now.

## Decision Outcome

Chosen option: **Option C (document & defer)**, because the platform already realizes the pattern's substantive benefits — an inspectable plan, run-to-run resumability via label-as-state, bounded fan-out, and a guarded cross-check — in an idiom whose *independent required-checks* safety model literal adoption (B, D) would weaken, while the one genuinely net-new idea (adversarial refutation, A) is not yet justified by any *measured* false-positive rate. The honest finding is that #588's premise is largely already-solved; the correct output is to document *why* the current architecture is the plan-as-code answer for a headless loop and to name the conditions under which that ceases to be true — not to churn a running fleet for fidelity to a pattern it already embodies.

This ADR formalizes the boundary ADR-0053 already drew in passing ("Full dynamic-workflow review (#588) is explicitly out of scope").

**Scope note (not a reversal):** literal use of the `Workflow` tool remains permitted as an *in-job implementation detail* — i.e. inside a single GitHub-Actions job where it cannot subvert cross-job independent enforcement. What is deferred is using a dynamic workflow as the *orchestration substrate* across the fleet.

## Consequences

### Positive

- No churn on a running fleet; the deterministic safety model (independent required checks, branch protection) stays intact and unmoved.
- The question stops recurring: a documented decision with named triggers replaces "should we adopt plan-as-code?" resurfacing each time the webinar is re-read.
- The triggers make the deferral *falsifiable* — if the conditions occur, the decision flips on evidence, not vibes.

### Negative

- We forgo the potential false-positive reduction of adversarial finding-verification until a trigger fires. Accepted because the current `review-lead` + ADR-0049 floor + ADR-0053 on/off-diff routing already constrain finding-bloom, and no false-positive rate has been measured to justify the build.
- The webinar's headline pattern is not *literally* demonstrated in the platform — a minor portfolio-narrative cost (the platform can still describe plan-as-code via its deterministic YAML+bash orchestration).

### Neutral

- The `Workflow` tool remains available for bounded in-job sub-tasks; nothing here forbids it where it doesn't cross the enforcement boundary.
- `triage-scan.yml`, `claude-pr-review.yml`, and `review-lead` are unchanged by this ADR.

## Pros and Cons of the Options

### Option A: Conceptual borrow + reviewer-first adversarial verification

- ✅ Pro: Directly attacks false-positive findings, which become real dispatched issues; pairs with the existing `review-lead`.
- ✅ Pro: Stays in the proven idiom; can be a bounded in-job `Workflow` call without crossing the enforcement boundary.
- ❌ Con: Speculative without a measured false-positive rate — builds machinery for a problem not yet shown to exist at cost-justifying volume.
- ❌ Con: Adds verification latency/token cost to every PR review.

### Option B: Literal dynamic-workflow for the reviewer panel

- ✅ Pro: Highest fidelity to the webinar pattern; one place to read the whole review plan; resumable within the session.
- ❌ Con: Collapses *independent* per-check enforcement into one session's judgment — the exact property #601 and ADR-0053's trust boundary protect. A single session becomes the point where a Critical/High could be suppressed.
- ❌ Con: Trades a battle-tested CI model (required checks, branch protection) for a session construct that GitHub Actions cannot enforce around.

### Option C: Document & defer (chosen)

- ✅ Pro: Zero blast radius on a running fleet; preserves the independent-enforcement safety model.
- ✅ Pro: Settles a recurring question with an evidence-based, falsifiable deferral.
- ✅ Pro: Honest about the already-solved premise rather than building for pattern-fidelity.
- ❌ Con: Ships no new capability now; relies on the triggers actually being watched (mitigated by listing measurable ones).

### Option D: Rewrite the promoter as plan-as-code

- ✅ Pro: Unifies the dispatch plan into one script.
- ❌ Con: The promoter is *already* deterministic shell; this adds a Claude-session dependency and blast radius to plain bash for no new benefit.
- ❌ Con: Highest risk to the live fleet for the least marginal value; #588 itself defers it.

## Implementation notes

(MADR extension — pointers that make this decision real.)

- **No code changes.** No standards doc accompanies this ADR: it does not introduce a new standard, it affirms the existing orchestration standards already captured in [ADR-0017](0017-async-orchestration.md), [ADR-0020](0020-fleet-orchestration.md), [ADR-0021](0021-autonomous-merge.md), [ADR-0030](0030-all-dispatch-through-promoter.md), and the review architecture in [ADR-0053](0053-review-finding-routing.md). (The "standard + ADR together" rule does not apply when no new standard is being decided.)
- **Affirmed artifacts (unchanged):** `.github/workflows/triage-scan.yml` (promoter + deterministic auto-merge), `.github/workflows/claude-pr-review.yml` + `plugins/ai-team/agents/review-lead.md` (guarded cross-check).
- **Revisit triggers — reopen this ADR (toward Option A or B) when any holds:**
  1. **Measured false positives.** `review-lead`-filed `origin:internal-review` issues that are subsequently closed as invalid/wontfix exceed a meaningful rate (e.g. ≥30% over a 20-issue window) → build Option A's adversarial refutation pass.
  2. **Promoter mis-promotion.** The single "well-specified?" veto demonstrably mis-promotes (implementer picks up under-specified issues that bounce) often enough to want structured, multi-angle promotion judgment.
  3. **Enforcement-preserving literal path appears.** Claude Code dynamic workflows become invocable from headless `claude -p` *while preserving independent gating*, or GitHub Actions gains a native equivalent → re-evaluate Option B.
  4. **Reviewer fan-out outgrows the idiom.** The number/complexity of reviewer lenses grows past what parallel jobs + a single consolidator handle cleanly.
- **Supersession:** none. Amends nothing; scopes #588 to closed-with-rationale.

## Links

- Claude Code dynamic workflows: `https://code.claude.com/docs/en/workflows` — the pattern evaluated here.
- Claude Code Advanced Patterns webinar: `https://www.anthropic.com/webinars/claude-code-advanced-patterns` — source of the plan-as-code / adversarial-cross-check patterns (#251).
- [ADR-0017](0017-async-orchestration.md), [ADR-0020](0020-fleet-orchestration.md), [ADR-0021](0021-autonomous-merge.md), [ADR-0030](0030-all-dispatch-through-promoter.md) — the orchestration this ADR affirms as plan-as-code.
- [ADR-0053](0053-review-finding-routing.md) — the guarded cross-check; already scoped #588 out of its own changes.
- [ADR-0049](0049-review-filing-severity-floor.md) — the severity floor that, with ADR-0053, already constrains finding-bloom.
- Issue #588 (this decision) and epic #251 (the webinar mining).
