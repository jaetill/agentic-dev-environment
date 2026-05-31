# Autonomous Loop — Issue Flow and Decision Tree

How an issue travels from its source, into the cron-driven loop, through every
decision the loop makes, to one of its terminal states. The flow is **abstracted
over repo type** — the loop is fleet-wide and repo-agnostic; the only repo-shaped
fork shown is `scope:iac` (which agent builds it) and the no-app vs. app behaviour
folded into the review battery (ADR-0024). There is intentionally no per-repo split.

Source of truth: `triage-scan.yml`, `claude-implementer.yml`, `claude-pr-review.yml`,
and ADR-0016 / 0017 / 0019 / 0020 / 0021 / 0023 / 0024 / 0025 / 0026 / 0027 / 0028 / 0029 / 0030.

> **Dispatch routing (ADR-0030):** machine-detected work (severity:critical, source:sentry/cloudwatch) flows through the promoter's deterministic, throttled dispatch — **event-dispatch** on the platform repo (immediate), a **central `*/15` urgent-poll** for app repos (they hold no cross-repo credential to be pushed). Human-approved work (`ready-for-implementer`) stays on each repo's **local** trigger — immediate, no throttle needed (humans don't storm). The fleet-wide `FLEET_MAX_DISPATCH` throttle is enforced centrally.

**Legend — outcome palette** (terminal & parked end-states)

- 🟩 green — work completed (issue closed)
- 🟧 amber — handed to the human (a deliberate checkpoint, not a failure)
- ⬛ grey — parked, re-evaluated on a later cycle/window

**Agent palette** — every *action/choice* node is coloured by the agent that owns it, inside or outside the stage boxes (so the promoter's `EVENTDISP` and sweep dispatch read as promoter even though they sit outside the ② loop box): **teal** = promoter (`triage-bot`), **indigo** = implementer, **purple** = reviewer agents, **steel-blue** = merger (auto-merge gate). See *Agent ownership* below.

```mermaid
flowchart TD
    %% ===================== ① SOURCES =====================
    subgraph SRC["① Issue sources"]
        direction TB
        S1["code-reviewer<br/>High/Med finding"]
        S2["security-reviewer<br/>finding"]
        S3["test-writer<br/>coverage gap"]
        S4["doc-keeper<br/>doc gap"]
        S5["ci-health<br/>fleet workflow failure"]
        S6["Sentry<br/>production error"]
        S7["dep-watch<br/>reviews dependency PRs"]
        S8A["You / trusted maintainer<br/>filed issue"]
        S8B["Other user · app user / external<br/>feature request or bug"]
        PF["triage-scan Pass 3<br/>process-flaw markers pulled<br/>fleet-wide, refiled on platform repo"]
    end

    S1 --> LBL["Issue filed<br/>labels: severity:*, origin:internal-review"]
    S2 --> LBL
    S3 --> LBL
    S4 --> LBL
    S5 --> CILBL["Issue filed<br/>labels: bug, triage:medium"]
    S6 --> SENT["Issue filed<br/>label: source:sentry"]
    S7 --> DEPAUTO["Auto-merges safe bumps + CVE patches<br/>(patch/minor · tests green) → merged"]
    S7 --> DEPFIND["Files work: major bumps · EOL/deprecation ·<br/>dead-package replacement<br/>severity:* + ready-for-implementer"]
    S7 --> DEPDIGEST["Weekly digest<br/>label: dep-watch"]
    DEPFIND -->|"ADR-0027 · no human gate"| QUEUE
    DEPDIGEST --> DIGSINK["Human info sink ·<br/>read-only, never a gate"]
    S8A --> OPTIN
    S8B --> INERT["Sits inert — cannot self-dispatch<br/>non-maintainers cannot apply labels"]
    INERT --> OPTIN{"Trusted maintainer opts it in?<br/>applies ready-for-implementer / severity:critical<br/>permission-gated — write/triage only"}
    OPTIN -->|yes| EVENTDISP
    OPTIN -->|"no — not yet"| OPTINWAIT["Never auto-acted on ·<br/>waits for your review"]
    PF --> QUEUE
    CILBL --> QUEUE

    LBL --> QUEUE["Agent-discovered queue<br/>awaits the promoter"]

    SENT --> EVENTDISP["Promoter deterministic dispatch · ADR-0030<br/>machine work: event-dispatch (platform) · urgent-poll (app repos)<br/>throttled to FLEET_MAX_DISPATCH · no LLM"]
    QUEUE -. "agent-applied severity:critical" .-> EVENTDISP

    %% ===================== ② TRIAGE-SCAN LOOP =====================
    subgraph LOOP["② triage-scan loop · cron-driven · platform-central · fleet-wide"]
        direction TB
        WIN{"In window?<br/>overnight 01–04 CT daily ·<br/>work-hours 09–12 CT Mon–Fri ·<br/>manual dispatch always passes"}
        WIN -->|no| WWAIT["Quiet — wait for next window"]
        WIN -->|yes| EVALALL["①·triage EVERY open finding · full pass<br/>exhaustive — the cap does NOT gate evaluation"]
        EVALALL --> PROMO{"per finding: promotion eligible? · Tier-2 judgement<br/>· agent-discovered<br/>· severity:med/high or triage:med<br/>· not already ready-for-implementer<br/>· survived at least one cycle (older than ~35 min)<br/>· well-specified, single bounded change"}
        PROMO -->|"no — vague"| DISAMB{"Promoter can disambiguate<br/>from the code? · ADR-0031"}
        DISAMB -->|"yes — enrich body"| ENRICH["Rewrite issue with missing<br/>repro/acceptance criteria · comment"]
        ENRICH --> PROMSET
        DISAMB -->|no| CLOSEV["Auto-close vague issue · comment<br/>malformed agent finding — linked, not lost"]
        CLOSEV --> AQUAL["File/append agent-quality issue · platform repo<br/>deduped per source agent · names missing field + spec file"]
        PROMO -->|yes| PROMSET["②·promotable set ·<br/>collected across the whole pass"]
        PROMSET --> RANK{"③·rank the set by severity, then dispatch<br/>top N within FLEET_MAX_DISPATCH = 6<br/>severity:high before any medium"}
        RANK -->|"top N"| DISPATCH["+ ready-for-implementer ·<br/>dispatch the repo's implementer · comment"]
        RANK -->|"beyond cap"| CAPWAIT["Rest wait for next cycle ·<br/>re-ranked next pass — not dropped"]
        CAPWAIT -. "re-ranked next pass — re-enters eligibility" .-> PROMO
        AQUAL -. "cap-exempt · dedup-bounded · ADR-0031" .-> DISPATCH
        RANK -. "spare slots, but only after ≥1 real promotion · ADR-0028" .-> SWEEP["Promoter dispatches a cleanup-sweep (Mode C) ·<br/>spare slots only · to the repo with the most<br/>deferred nits · skip zero-count repos"]
    end

    QUEUE --> WIN
    PROMO -->|"Low / Nit — deferred-until-adjacent (ADR-0016)"| DEFER["deferred pool ·<br/>deferred-until-adjacent (ADR-0016)"]
    DEFER -. "reconsidered every pass — re-enters eligibility (guarded self-loop)" .-> PROMO
    DEFER -. "pulled into a real dispatch only on an adjacent same-file change · ADR-0029" .-> DISPATCH
    DEFER -. "or swept on an active cycle · ADR-0028" .-> SWEEP

    %% ===================== ③ IMPLEMENTER =====================
    subgraph IMPL["③ Implementer · Mode A · repo-type-abstracted"]
        direction TB
        IAC{"scope:iac?"}
        IAC -->|yes| IACIMPL["iac-implementer<br/>tofu plan only · no apply · cap 5 resources"]
        IAC -->|no| CG{"Self-change?<br/>process-flaw / changes to ai-team"}
        CG -->|"compositional · standards · security ·<br/>rail-enforcer agent · or n=1 generality"| ARCH["STOP — route to architect<br/>propose ADR · human ratifies"]
        CG -->|"mechanical · additive agent-output<br/>tightening (ADR-0032) · or not a self-change"| PHASE{"feature-request WITH<br/>plan-first label? · ADR-0033"}
        PHASE -->|"yes — opt-in plan review"| PLAN["PLAN PHASE: post approach,<br/>label awaiting-plan-approval, STOP"]
        PLAN --> PAPP{"Human applies plan-approved?"}
        PAPP -->|"not yet"| PLANWAIT["Waits for human"]
        PAPP -->|yes| SCOPE
        PHASE -->|"no — defect/bug, or feature builds by default"| SCOPE{"Within scope cap?<br/>50 LOC · 3 files · 1 component"}
        SCOPE -->|no| REFUSE["Refuse + stop<br/>needs split or human"]
        SCOPE -->|yes| BUILD["Build: branch impl/* ·<br/>code + tests · lint · typecheck · commit"]
        BUILD --> CONF{"Pre-flight rebase clean?"}
        CONF -->|"no — conflict"| CONFWAIT["Abort + comment +<br/>exit without push · retry next dispatch"]
        CONF -->|yes| OPENPR["Push + open PR · Closes #n"]
    end

    EVENTDISP --> IAC
    DISPATCH --> IAC
    IACIMPL --> OPENPR

    %% ===================== ④ REVIEW BATTERY =====================
    subgraph REV["④ Review battery · claude-pr-review on the PR"]
        direction TB
        REVIEW["code-review · security-review ·<br/>functional-test · e2e-test ·<br/>test-writer · doc-keeper ·<br/>destructive-change · ensure-labels ·<br/>invoke-architect-if-gated"]
        REVIEW --> VERDICT{"code / security verdict?"}
        VERDICT -->|"BLOCK · Critical/High"| FIXIT{"Prior fix attempts under 3?"}
        FIXIT -->|yes| FIX["Mode B: address findings ·<br/>rebase check · push"]
        FIXIT -->|"no · 3 reached"| ESCAL["Escalate to human ·<br/>stop fix iteration · ADR-0026"]
    end

    OPENPR --> REVIEW
    SWEEP --> SWEEPIMPL["implementer · Mode C cleanup-sweep<br/>drains the repo's deferred nits · opens a PR"]
    SWEEPIMPL --> REVIEW
    FIX --> REVIEW
    REVIEW -. "files new defects" .-> S1

    %% ===================== ⑤ AUTO-MERGE GATE =====================
    subgraph MERGE["⑤ Auto-merge gate · in-window · as fleet App · per implementer PR"]
        direction TB
        MG0{"AUTONOMOUS_MERGE on?"}
        MG0 -->|off| PAUSED["Paused — held"]
        MG0 -->|on| MG1{"requires-adr:* label?"}
        MG1 -->|yes| HADR["Hold for human · ADR-gated"]
        MG1 -->|no| MG2{"compositional-self-change label?"}
        MG2 -->|yes| HCOMP["Hold for human · ADR-0023"]
        MG2 -->|no| MG3{"Linked issue present and machine-origin?<br/>bot author · source:sentry ·<br/>source:cloudwatch · origin:internal-review"}
        MG3 -->|"no — human-origin or none"| HHUM["Hold for human merge"]
        MG3 -->|yes| MGGUARD{"additive-self-change-guard · ADR-0032<br/>touches an agent definition?"}
        MGGUARD -->|"out-of-lane agent edit"| HSELF["Hold for human ratification ·<br/>self-change firewall (ADR-0019/0023)"]
        MGGUARD -->|"in-lane additive · or not a self-change"| MG4{"All required checks green?"}
        MG4 -->|"no · or none reported"| HCHK["Hold — needs green battery"]
        MG4 -->|yes| MG5{"Within per-run cap = 10?"}
        MG5 -->|no| CAPM["Rest wait for next window ·<br/>re-considered next pass — not dropped"]
        CAPM -. "re-considered next window" .-> MG0
        MG5 -->|yes| DOMERGE["Squash-merge + delete branch<br/>cascades release-please + deploy"]
        DOMERGE --> MFAIL{"Merge succeeded?"}
        MFAIL -->|no| HFAIL["Merge failed — left for human"]
        MFAIL -->|yes| CLOSED["Issue closed"]
    end

    VERDICT -->|"APPROVE / with-comments"| MG0

    %% ===================== terminal styling =====================
    classDef success fill:#1f7a3d,stroke:#0d4d24,color:#fff;
    classDef human fill:#b06f00,stroke:#7a4d00,color:#fff;
    classDef wait fill:#4a4a4a,stroke:#2a2a2a,color:#fff;

    %% Agent ownership — every action/choice node carries its OWNING agent's
    %% colour, inside or outside the stage boxes. So the promoter's EVENTDISP
    %% and sweep dispatch read as promoter even though they sit outside ②.
    %% Terminal end-states keep the outcome palette above.
    classDef promoter fill:#0e5057,stroke:#1fa3bf,color:#eaffff;
    classDef implementer fill:#2e2f70,stroke:#5560c8,color:#eaeeff;
    classDef reviewer fill:#5e2a6e,stroke:#9a5bb5,color:#f7eaff;
    classDef merger fill:#2b5b8a,stroke:#5a9fd4,color:#eaf6ff;

    class CLOSED,DEPAUTO success;
    class ARCH,PLANWAIT,REFUSE,ESCAL,HADR,HCOMP,HHUM,HFAIL,HSELF,PAUSED human;
    class WWAIT,CAPWAIT,CONFWAIT,CAPM,DEFER,HCHK,INERT,OPTINWAIT,DIGSINK wait;

    class PF,EVENTDISP,WIN,EVALALL,PROMO,DISAMB,ENRICH,CLOSEV,AQUAL,PROMSET,RANK,DISPATCH,SWEEP promoter;
    class IAC,IACIMPL,CG,PHASE,PLAN,PAPP,SCOPE,BUILD,CONF,OPENPR,FIX,SWEEPIMPL implementer;
    class REVIEW,VERDICT,FIXIT reviewer;
    class MG0,MG1,MG2,MG3,MGGUARD,MG4,MG5,DOMERGE,MFAIL merger;
```

## Terminal states

| State | Colour | Meaning |
|---|---|---|
| Issue closed | 🟩 | Fix merged; the loop did its job end-to-end. |
| Route to architect | 🟧 | Competence gate caught a compositional/standards/security self-change — ADR + human ratify (ADR-0019). |
| Plan waiting | 🟧 | feature-request paused for human `plan-approved` (ADR-0017 plan-gate). |
| Refuse (scope cap) | 🟧 | Change exceeds 50 LOC / 3 files / 1 component — needs a split or human. |
| Escalate (3 attempts) | 🟧 | Mode B couldn't converge in 3 fix iterations (ADR-0026). |
| Hold: ADR-gated | 🟧 | `requires-adr:*` label — one of the five gated categories. |
| Hold: compositional | 🟧 | `compositional-self-change` label (ADR-0023). |
| Hold: human-origin | 🟧 | Linked issue is human-filed — human-merge checkpoint (ADR-0023). |
| Hold: merge failed | 🟧 | Qualified but `gh pr merge` rejected — left for human. *(This was the platform-repo deadlock fixed in ADR-0024.)* |
| Paused | 🟧 | `AUTONOMOUS_MERGE=off`. |
| Wait: window / cap / conflict / checks | ⬛ | Parked, re-evaluated next cycle or window. |
| deferred-until-adjacent | ⬛ | Low/Nit finding — drained later by cleanup-sweep (ADR-0016). |
| Auto-closed (malformed finding) | 🟩 | Promoter couldn't disambiguate a vague agent finding — closed, and a fix to the source agent's contract dispatched (ADR-0031). |

## Agent ownership (node colours)

Every **action/choice** node is coloured by the agent that owns it — so "is the right agent doing the right job" is a glance, and an agent's work is one colour *wherever it sits*, not confined to a stage box. The promoter's `EVENTDISP` (deterministic dispatch) and its sweep dispatch live outside the ② box but read promoter-teal like the rest of its nodes. Terminal/parked end-states keep the outcome palette (🟩/🟧/⬛).

| Agent | Colour | Owns (action/choice nodes) |
|---|---|---|
| promoter (`triage-bot`) | teal | the ② loop (window, triage, rank, dispatch, vague-handling) **+** `EVENTDISP` & the sweep dispatch outside it **+** the Pass-3 process-flaw scan |
| implementer (+ `iac-implementer`) | indigo | the ③ build flow + the Mode-B fix node |
| reviewer agents | purple | the ④ review-battery decisions |
| merger (fleet App) | steel-blue | the ⑤ auto-merge gate, incl. the ADR-0032 self-change guard |

The **source agents** (① — code-reviewer, ci-health, Sentry, dep-watch, …) and the queue/filing nodes keep the default fill for now; colouring those by agent (and a full per-agent swimlane redraw) is the remaining increment.

## Notes

- **Two ways in.** Most agent-discovered work *waits* for the in-window promoter. A small set of **label-triggered** signals bypass it and hit the implementer immediately: `ready-for-implementer`, `severity:critical`, and `source:sentry`.
- **You vs. other users — the separation is permission-enforced.** In every app repo the implementer fires only on a *labeled* event, never on issue-open. Applying those labels requires triage/write access, which app users and external collaborators don't have (and there are no auto-labeling issue templates). So another user's request **sits inert** until a trusted maintainer reviews it and opts it in. The distinction is enforced by GitHub repo permissions on label application, not by an author check in the workflow — which is why it isn't visible in the raw `if:` conditions.
- **Three safeguards against an external request weakening the app.** (1) It can't self-dispatch — needs a maintainer's opt-in label. (2) If it's a `feature-request`, the plan-gate still holds it for your `plan-approved`. (3) The auto-merge gate holds *every* human-origin issue for your manual merge (ADR-0023). A non-maintainer can file, but cannot make the loop build or land anything.
- **Platform opened-path — now owner-gated.** The platform repo (`agentic-dev-environment`) is public and its templates auto-apply `bug` / `feature-request`. Its `opened` pickup (`initial` + `initial-iac`) is now guarded by `author_association == 'OWNER'` (ADR-0025) — the owner's own issues fast-path; anyone else's start *no* work until the owner applies `ready-for-implementer`. This puts the human-in-the-loop checkpoint ahead of implementation, not just merge, matching the app repos. So the "Other user" source above is inert across the whole fleet, platform repo included.
- **The loop generates its own inputs.** The review battery files fresh defects (dashed edge back to sources) — this is why backlog can grow even while the loop runs; throughput, not correctness.
- **Triage is exhaustive; only dispatch is capped — and it ranks first.** Each pass the promoter triages *every* open finding — promoting, deferring, enriching, or auto-closing as it goes — and applies `FLEET_MAX_DISPATCH` only at the end, to the *ranked* promotable set (phases ①→②→③ in the loop). It never stops evaluating because the cap is full, so nothing is skipped for triage; a beyond-cap promotion just waits and is re-ranked next pass, never dropped. Agent-quality self-fixes dispatch **cap-exempt** (dedup-bounded, ADR-0031), so a self-correction can't be starved by routine work.
- **The loop fixes its own labor (ADR-0031).** A vague finding can only originate from one of the loop's own agents — the promoter never evaluates human-authored issues. So when the promoter can't enrich a vague finding from the code, it auto-closes it and dispatches a fix to the *source agent's* contract, same run. Repeated vague output converges to one tracked improvement instead of an immortal, re-commented backlog issue.
- **Repo abstraction.** The promoter, implementer, review, and merge stages are identical across all fleet repos. The only repo-shaped decisions are `scope:iac` (routes to `iac-implementer`) and app-vs-no-app inside the review battery (resolved by ADR-0024 so required checks always report, never skip).
- **The merge gate is mechanical.** No agent judgement — every branch is decidable from labels, the linked issue's origin, and check state.
