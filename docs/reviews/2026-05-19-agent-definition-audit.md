# Agent definition audit — 2026-05-19

Code-review-style audit of the 14 subagent definition files in `plugins/ai-team/agents/`, adapted for a declarative-prompt artifact class. Calibration substrate per [code-reviewer.md](../../plugins/ai-team/agents/code-reviewer.md) and [ADR-0016](../adr/0016-finding-lifecycle-calibration-deferral.md).

## 1. TL;DR

- **Overall health: strong.** The roster is consistent, well-structured, and shows clear authorial discipline. All 14 agents share a recognizable template (Role / Triggers / Authority / Inputs / Process / Output / Anomaly handling / Anti-patterns) — this is unusual for prompt collections and pays off in predictability.
- **Top theme: reviewer-class calibration is uniformly present** (code-reviewer, security-reviewer, doc-keeper, triage-bot all have an explicit "Calibration philosophy" section citing ADR-0016). Implementer-class agents have "don't manufacture work" anti-patterns. The policy has actually landed in the prompts.
- **Top gap: zero adoption of the newer plugin frontmatter fields** (`skills`, `memory`, `background`, `isolation`). Several agents — doc-keeper, architect, triage-bot — are plausible `skills:` or `memory:` candidates. Not a bug, but a missed leverage point given ADR-0015's plugin posture.
- **Findings: 0 Critical, 2 Medium, 6 Low, 4 Nit.** Near-clean audit. The biggest concrete issue is that `drift-detector` and `dep-watcher` (both reviewer-class) lack the explicit ADR-0016 calibration block their siblings carry.
- **One artifact-class observation:** the auto-selection surface (frontmatter `description`) is generally good but two agents — `architect` and `implementer` — have descriptions that promise specific triggers but could be sharper at distinguishing themselves from a likely-confused sibling.

## 2. Cross-cutting themes

These are the patterns worth fixing once across the roster, not agent-by-agent.

### Theme A — Reviewer-class calibration not fully propagated

ADR-0016's calibration block landed in 4 of the 6 reviewer-class agents:

| Agent | Has "Calibration philosophy" section | Has explicit deferral policy |
|---|---|---|
| code-reviewer | Yes (L118) | Yes (L134) |
| security-reviewer | Yes (L147) | Yes (L161) |
| doc-keeper | Yes (L115) | Partial — mentions deferral inline (L125) |
| triage-bot | Yes (L200) | Partial — covered in severity table (L209) |
| **drift-detector** | **No** | **No** |
| **dep-watcher** | **No** | **No** |

drift-detector and dep-watcher are both reviewer-class agents that produce findings and merge decisions. The omission is most visible in dep-watcher, whose Tier 2 process can request ADRs and block PRs — the same severity-inflation failure mode applies. See Medium finding M1.

### Theme B — Frontmatter field coverage is shallow

No agent in the roster uses any of: `skills:`, `memory:`, `background:`, `isolation:` (verified via grep for `^skills:|^memory:|^background:|^isolation:` against all 14 files). Per [Claude Code plugin reference](https://code.claude.com/docs/en/plugins-reference), these are first-class fields. Likely candidates:

- **doc-keeper** — could ship a `skills:` reference to a "docs-style-guide" skill or load standards-doc cross-link rules from memory.
- **architect** — ADR template fits the `skills` pattern (it's procedural knowledge separable from the prompt).
- **triage-bot** — `memory:` is the obvious fit for "open `triage:*` issues already filed" dedupe state.
- **incident-responder** — `background: true` is plausible for long-running incident watch, though current trigger model is event-based.

Not filing as discrete findings — surface here for Jason's call. See "Decisions only Jason can make" below.

### Theme C — Output-format example blocks are present but inconsistent in completeness

12 of 14 agents include a fenced code block showing expected output shape. The two exceptions: `iac-implementer` (has a PR-body template at L120, which is fine) and `implementer` (says "the PR is the report" at L242 — acceptable since the artifact is a PR). The pattern is healthy.

Inconsistency: some agents (functional-tester, e2e-tester, dep-watcher, release-captain, drift-detector) show **separate Tier 1 and Tier 2 output blocks**, which is excellent. Others that have tiered processes (triage-bot) only show one example. Low-priority polish.

### Theme D — Tool grants are well-scoped, with two notable cases

12 of 14 agents have minimum-necessary tool grants. Reviewer-class read-only agents correctly omit Write/Edit (code-reviewer L5, security-reviewer L6, triage-bot L6). Implementer-class agents correctly include them. Two cases worth noting:

- **dep-watcher** (L6: `[Read, Grep, Glob, WebFetch, Bash]`) — has `Bash` but lacks `Edit/Write` despite claiming authority to "Approve and auto-merge a PR" (L28). Auto-merge via `gh` CLI works through Bash, so this is consistent — but tight. Not a finding.
- **doc-keeper** (L6: `[Read, Edit, Write, Grep, Glob, Bash]`) — has the broadest grant of any non-implementer agent. Justified by the "regenerate API docs, update navigation YAML" scope, but worth noting it sits one step away from being a code-editing agent.

### Theme E — Triggering precision is generally good; two agents could disambiguate against siblings

- `e2e-tester` (L9) explicitly disambiguates: "You are distinct from `functional-tester` (service-level) and `test-writer` (unit-level)." This is the model.
- `functional-tester` (L13) does the same: "You are the **test-execution arm**; `test-writer` is the **test-authoring arm**."
- **`implementer` vs `iac-implementer`** — both descriptions say "writes ... code in response to defect issues." iac-implementer's description (L3) does add "infrastructure-as-code changes," but the disambiguation lives in the prompt body (implementer L81 forbids `terraform/`), not the description Claude uses for auto-selection. If Claude is choosing between them on a borderline issue, the descriptions alone may not break the tie. Low finding L1.
- **`architect` vs head-agent** — architect's prompt body L15-16 explicitly says "You are **not** the head agent's interactive architect mode" — but the frontmatter description doesn't carry this. A user typing "design the auth flow" might land on architect when they wanted interactive help. Low finding L2.

## 3. Per-agent scorecards

Scoring 1–5 on the six rubric dimensions. Format: score with one-line evidence (line numbers reference the agent file).

| Agent | Charter clarity | Triggering precision | Tool boundaries | Prompt structure | Output format | Calibration alignment |
|---|---|---|---|---|---|---|
| **architect** | 4 — "ADR drafting, system-level reasoning" + 3 triggers (L3) | 3 — overlaps head-agent's design mode; disambiguation only in body (L15) | 5 — read + edit + web; appropriate for ADR drafting (L5) | 5 — full template, all sections present | 4 — writes file directly; conversational reply for slash (L83) | N/A — not a reviewer/implementer class |
| **code-reviewer** | 5 — names triggers, slash command, scope explicitly (L3) | 5 — "linters cannot — clarity, naming, abstractions" (L3) | 5 — `[Read, Grep, Glob]` only; correctly read-only (L5) | 5 — full template + Calibration + Filing sections | 5 — block example with severity sections (L78) | 5 — explicit ADR-0016 alignment (L118-144) |
| **dep-watcher** | 4 — clear scope, mentions Tier 1/2 (L3) | 4 — "Dependabot/Renovate dependency-update PRs" (L3) | 5 — Bash for `gh` merge, no Edit needed for the auto-merge path (L6) | 5 — full template + tier escalation rule | 5 — Tier 1 + Tier 2 examples (L109, L122) | **2 — no ADR-0016 calibration block; reviewer-class** |
| **doc-keeper** | 4 — clear "current truth" framing (L3) | 4 — 7 trigger types enumerated (L17-23) | 4 — broadest grants of any non-impl; justified but wide (L6) | 5 — full template + calibration section | 5 — drift + update example blocks (L78, L91) | 5 — Calibration philosophy + deferral mention (L115-125) |
| **drift-detector** | 4 — IaC drift triage + tier model (L3) | 4 — weekly schedule + slash command (L17-19) | 5 — Edit/Write for IaC PR drafting only (L6) | 5 — full template with tier sections | 5 — Tier 1 report + Tier 2 PR markdown (L100, L127) | **2 — no ADR-0016 calibration block; reviewer-class** |
| **e2e-tester** | 5 — names Playwright explicitly + disambiguates siblings (L3, L9) | 5 — 4 distinct triggers + slash command (L17-20) | 5 — Edit/Write/Bash for test authoring (L6) | 5 — full template, tier model | 5 — Tier 1 + Tier 2 example blocks (L96, L107) | N/A — has "don't manufacture" via L137 retry rule |
| **functional-tester** | 4 — clear; explicit overlap-handling vs e2e (L13) | 5 — disambiguated from siblings in description (L3) and body | 5 — Edit/Write/Bash; appropriate (L6) | 5 — full template, tier model | 5 — Tier 1 + Tier 2 examples (L91, L102) | N/A — has anti-pattern against silent quarantining (L127) |
| **iac-implementer** | 5 — "writes IaC changes ... Strictly read-only against AWS" (L3) | 5 — 3 triggers + explicit scope cap (L17, L46) | 5 — Edit/Write/Bash; appropriate; explicit no-apply (L6, L38) | 5 — full template + Why-this-exists section | 5 — PR body template with mandatory plan output (L120) | 5 — has "manufacture work" guard implicit via scope-cap refusal (L97) |
| **implementer** | 5 — comprehensive, names modes A/B (L3) | 4 — could disambiguate against iac-implementer more sharply in description (L3) | 5 — appropriate read+write+bash (L6) | 5 — full template + dual modes + Why-this-exists | 4 — "the PR is the report" (L242); no example block per se | 5 — anti-pattern L264 "unbounded refactoring while you're in there" |
| **incident-responder** | 5 — "real-time interrupt path; only synchronous human-paging" (L3) | 5 — disambiguated vs triage-bot and drift-detector in description (L3) | 5 — Bash + Web for diagnostics; no Edit for code (L6) | 5 — full template, includes cowork_enhancements field | 5 — incident + postmortem block examples (L86, L104) | N/A — not a finding-producer; severity discipline embedded in process |
| **release-captain** | 5 — names triggers + tier model (L3) | 5 — release-please-specific + slash command (L17-20) | 5 — Edit/Write/Bash for release metadata (L6) | 5 — full template + tier model | 5 — Tier 1 + Tier 2 example blocks (L138, L150) | N/A — orchestrator, not a reviewer |
| **security-reviewer** | 5 — names categories, parallel to code-reviewer (L3) | 5 — explicit "Distinct scope from code-reviewer" (L3) | 5 — `[Read, Grep, Glob, WebFetch]`; correctly read-only (L6) | 5 — full template + Calibration + Filing | 5 — block example with all severity tiers (L109) | 5 — explicit ADR-0016 + scope discipline (L147-171) |
| **test-writer** | 4 — clear scope; mentions trigger conditions (L3) | 4 — coverage-drop trigger + slash command (L17-19) | 5 — Edit/Write/Bash; appropriate for test authoring (L6) | 5 — full template + naming convention section | 5 — code block example (L96) | N/A — has "don't modify production code" L34 |
| **triage-bot** | 5 — "customer-advocate lens; Distinct from incident-responder" (L3) | 5 — disambiguates from incident-responder + code-reviewer in description (L3) | 5 — read-only + Bash; no code modification (L6) | 5 — full template + cowork_enhancements + calibration | 5 — Tier 1 daily summary + Tier 2 ticket draft (L133, L150) | 5 — explicit ADR-0016 alignment (L200-213) |

**Aggregate:** 13 of 14 agents score ≥4 across all applicable dimensions. The two below-4 cells are both the same finding: dep-watcher and drift-detector missing ADR-0016 calibration.

## 4. Findings bundled by severity

### Critical

None.

### Medium

**[dep-watcher.md] and [drift-detector.md] — Missing ADR-0016 calibration block on reviewer-class agents** (M1)
Both agents make merge / PR-blocking decisions and produce escalations (dep-watcher to architect for ADRs; drift-detector to architect for structural drift). The same severity-inflation failure mode that motivated ADR-0016 applies. The 4 sibling reviewer agents all carry an explicit "Calibration philosophy" + deferral block; these two do not.
**Evidence:** `grep -E '^## Calibration' plugins/ai-team/agents/{dep-watcher,drift-detector}.md` returns nothing. Compare to code-reviewer.md L118, security-reviewer.md L147, doc-keeper.md L115, triage-bot.md L200.
**Recommended fix:** Add the same ~15-line Calibration philosophy section used in the other 4 reviewers, adapted to the dep-watcher/drift-detector severity vocabulary. Reference ADR-0016 explicitly.

### Low (apply `deferred-until-adjacent`)

**[implementer.md:3] — Description doesn't disambiguate against iac-implementer for Claude's auto-selection** (L1)
The disambiguation lives in the body (L81 forbids `terraform/`), but Claude's agent selection reads frontmatter. On a borderline issue ("update the prod IAM policy"), both descriptions begin "Writes ... code in response to defect issues" — the tiebreaker is buried.
**Evidence:** implementer L3 starts "Writes production application code"; iac-implementer L3 starts "Writes infrastructure-as-code changes."
**Recommended fix:** Add "Application-code only; IaC goes to iac-implementer" or similar to implementer's description. One sentence.
**Label:** `deferred-until-adjacent`.

**[architect.md:3] — Description doesn't distinguish from head-agent's interactive architect mode** (L2)
The body explicitly draws this line (L15-16), but the frontmatter description does not. Users typing "design the auth flow" or "what's the right architecture for" may auto-route to this agent when they wanted interactive discussion.
**Evidence:** architect.md L3: "Use for architectural design decisions, ADR drafting, system-level reasoning."
**Recommended fix:** Append "Used for autonomous ADR drafting; interactive design discussion stays with the head agent." Single sentence.
**Label:** `deferred-until-adjacent`.

**[doc-keeper.md:126] — Stray anti-pattern bullet below the "Calibration philosophy" section** (L3)
The "❌ **Deleting documentation pre-emptively**" bullet on L126 appears after the calibration section ends, suggesting it was appended out of order during a prior edit. It belongs in the Anti-patterns section (which ends at L114).
**Evidence:** doc-keeper.md L126: `- ❌ **Deleting documentation pre-emptively...`, no preceding `## Anti-patterns` header to anchor it.
**Recommended fix:** Move bullet up into the Anti-patterns list near L113.
**Label:** `deferred-until-adjacent`.

**[implementer.md:142] — Mojibake in prompt body** (L4)
Two characters (`�`) appear where en-dashes or em-dashes should be. Will confuse Claude minimally but visible noise. Same character also appears at L165 and L223.
**Evidence:** implementer.md L142: "test-writer agent is in reviewer mode � it flags"; L165: "Rebase clean � continuing to push"; L223: "Rebase clean � continuing to push".
**Recommended fix:** Replace `�` with `—` (em-dash) in all three locations.
**Label:** `deferred-until-adjacent`.

**[functional-tester.md:54] — Routes flake to `architect` for fix-or-remove, but architect doesn't author tests** (L5)
The standard says route a flake "to `architect` + this agent's Tier 2 path to fix or remove." Architect drafts ADRs, not test fixes. Likely meant `test-writer` or just Tier 2.
**Evidence:** functional-tester.md L54: "stop, route to `architect` + this agent's Tier 2 path to fix or remove."
**Recommended fix:** Replace `architect` with `test-writer` or remove the cross-agent reference; Tier 2 of this same agent is the right path.
**Label:** `deferred-until-adjacent`.

**[triage-bot.md:115] — Hand-off to "head agent in scrummaster mode" is unfamiliar terminology** (L6)
Phrase appears here and at L19 ("the head agent in scrummaster mode is the dispatcher"). Reader is left to guess what "scrummaster mode" means — it isn't defined in this file or referenced from a standards doc.
**Evidence:** triage-bot.md L19: "the head agent in scrummaster mode is the dispatcher."
**Recommended fix:** Link to the standard or ADR that defines scrummaster mode, or replace with a self-explanatory phrase like "head agent for dispatching."
**Label:** `deferred-until-adjacent`.

### Nit

**[code-reviewer.md:122] — "Modern naming" comment hints at unfinished cleanup** (N1)
The output-format block (L78) still uses legacy "Blocking/Suggestion" labels while the Calibration section (L122) introduces Critical/Medium/Low/Nit and notes the supersession parenthetically. Either format is workable, but the dual vocabulary is the kind of drift that compounds.
**Evidence:** code-reviewer.md L122: "modern naming — supersedes the Blocking/Suggestion legacy labels in this doc's Output format section."
**Recommended fix:** Update the example block at L78 to use the modern vocabulary; remove the supersession note.
**Label:** `deferred-until-adjacent`.

**[release-captain.md:115] — Bundled-fix release-notes section uses a sub-heading nested under Tier 2** (N2)
The "Cleaned up while here" section is described mid-paragraph at L115 rather than as its own item in the structure list. Easy to miss when scanning.
**Evidence:** release-captain.md L115: "**Cleaned up while here** (when applicable)" embedded in a bulleted Tier 2 process step.
**Recommended fix:** Promote to its own bullet at the same indentation level.
**Label:** `deferred-until-adjacent`.

**[incident-responder.md:87] — Mid-prompt emoji breaks the otherwise-textual tone** (N3)
The `🚨` in the output-format example is the only emoji in the file. Style nit; pattern-matching consistency with other agents would suggest omitting it.
**Evidence:** incident-responder.md L87: `🚨 P0 INCIDENT — auto-rollback FAILED for game-night-prod`.
**Recommended fix:** Either keep (it's the most P0-appropriate place for one) or remove for consistency. No strong opinion.
**Label:** `deferred-until-adjacent`.

**[iac-implementer.md:124-125] — Escaped backticks in fenced-block example may render oddly** (N4)
The example PR-body template uses `\`\`\`` to escape the inner fence. Works in Markdown but adds visual noise; could use a different fence style (`~~~` outer, ``` inner) or HTML rendering.
**Evidence:** iac-implementer.md L124-125: `\`\`\`` (literal backslashes).
**Recommended fix:** Use `~~~` outer fence for the example, drop the escaping.
**Label:** `deferred-until-adjacent`.

## 5. Decisions only Jason can make

These are genuine forks where reasonable engineers could pick either way; flagging for your discernment rather than recommending.

- **Adopt the `skills:` and `memory:` frontmatter fields?** Per Theme B, zero agents use these. The architect's ADR template, doc-keeper's style guide, triage-bot's open-ticket state are all plausible candidates. The cost is one more concept to track; the benefit is separable, versionable, reusable knowledge artifacts. **Open question because:** the platform deliberately keeps the prompt body monolithic for readability, and `skills`/`memory` move that knowledge outside the prompt. Either is defensible.

- **Sharpen `architect` vs head-agent disambiguation in the description, or leave as-is?** L2 finding above. The current state works as long as Claude correctly notices the body-level disambiguation. If you've observed accidental auto-selection of the architect agent for interactive design questions, fix the description; if not, the cost of editing may exceed the benefit.

- **Consolidate `functional-tester` and `e2e-tester` into one agent?** Both follow nearly identical structure (tiered Haiku/Sonnet, classify-then-author, run-against-deployed). The split makes sense conceptually (service-level vs browser-level) but the prompts are 70% the same. **Open question because:** combining loses the tool-grant clarity (e2e needs Playwright-specific tools; functional uses the project's test runner) but might reduce maintenance.

- **Promote `incident-responder` to `background: true`?** Per Theme B. It's the most natural fit for a long-running watcher pattern. Currently event-triggered which works, but `background: true` would let it maintain warmer context across alert clusters. The risk is cost; the benefit is faster MTTR on related-alert storms.

## 6. Evidence index

The two Medium findings, with full quotes for spot-check verification:

**M1a — dep-watcher missing calibration block**
- File: `plugins/ai-team/agents/dep-watcher.md`
- Last `## ` section header in file is L146: `## Anti-patterns to avoid`
- No `## Calibration` anywhere in file (verified via grep).
- Compare to code-reviewer.md L118: `## Calibration philosophy`

**M1b — drift-detector missing calibration block**
- File: `plugins/ai-team/agents/drift-detector.md`
- Last `## ` section header in file is L154: `## Anti-patterns to avoid`
- No `## Calibration` anywhere in file (verified via grep).
- Compare to security-reviewer.md L147: `## Calibration philosophy`

**L4 — implementer.md mojibake**
- File: `plugins/ai-team/agents/implementer.md`
- L142 contains exact char `�` between "reviewer mode" and "it flags"
- L165 contains exact char `�` between "Rebase clean" and "continuing to push"
- L223 contains the same pattern in the Mode B equivalent step

End of report.
