# ADR-0051: Fleet membership system of record is a committed manifest; the `fleet` topic is derived

- **Status:** Accepted — ratified by Jason 2026-06-22 (chat decision); implemented by this PR
- **Date:** 2026-06-22
- **Implementation:** Implemented 2026-06-22 via this PR (#563) — adds the system-of-record manifest `fleet/repos.txt`; repoints the single resolver `scripts/fleet-repos.sh` to read it; adds the best-effort derived-topic reconciler `scripts/fleet-topic-sync.sh` + `.github/workflows/fleet-topic-sync.yml`; updates roster-comment references in `ci-health.yml`, `urgent-poll.yml`, `scripts/fleet-inflight.sh`.
- **Deciders:** Jason
- **Tags:** fleet, security, governance, ci-cd

> **Lifecycle:** `Proposed` (drafted, undecided) → `Accepted` (decided, awaiting human ratify) → `Ratified` (human-approved, PR merged, code changes pending) → `Implemented` (code changes merged). `Deprecated` / `Superseded by ADR-NNNN` are terminal. The **Implementation** line is required when the ADR is in `Ratified` or `Implemented` state and is enforced by `adr-format-check`.

> **Format:** This ADR follows [MADR 4.x](https://adr.github.io/madr/) with three documented extensions: (1) **Neutral consequences** as a third bucket alongside Positive/Negative; (2) **Implementation notes** as a separate section before Links; (3) **Bundled sub-decisions** when multiple related decisions are tightly coupled.

## Context and Problem Statement

Fleet membership is a **capability grant**: a repo in the fleet receives FLEET_TOKEN scope, autonomous implementer dispatch, and auto-merge eligibility. PR #554 (closing #139/#39) made membership resolve at runtime from the `fleet` GitHub repo topic, replacing scattered hardcoded lists with a single resolver (`scripts/fleet-repos.sh`) that every consumer calls. The security review on #555 then flagged the consequence: deriving a capability grant from a repo topic moves the trust boundary from "merge a reviewed code change" to "write a repo setting" — and topic-write is repo-admin, an unaudited act with no review and no admission log. **Where should the authoritative record of fleet membership live, such that admission is an authorized, audited act from which capability flows?**

## Decision Drivers

- Membership confers privilege; the act of admission must be **authorized and audited** (reviewed, attributable, recoverable from history) — not a silent settings write.
- The capability-grant trust boundary must sit at a reviewed artifact, consistent with the capability-delta firewall (ADR-0047) that gates the loop's self-changes.
- Honor the real intent of #139/#39 — *one* non-scattered source of truth, no hardcoded lists drifting across repos.
- Preserve queryability for dashboards / `gh search`, which today key off the `fleet` topic.
- Keep the resolver dependency-free and fail-closed (an unresolvable roster must do-nothing, never present an empty fleet that the throttle would over-dispatch against).
- Do not broaden the loop's blast radius (e.g. by granting the fleet App repo-admin).

## Considered Options

- Option A: Topic-only (status quo after #554)
- Option B: Manifest-only, no topic
- Option C: Manifest ∧ topic cross-check (the original #563 allowlist idea)
- Option D: Manifest authoritative + topic derived
- Option E: GitHub-native org Team / custom repository property

## Decision Outcome

Chosen option: **Option D**, because it puts the authoritative record in a **reviewed, audited artifact** (the committed manifest, whose git history is the admission log) while keeping the `fleet` topic for queryability as a cosmetic, best-effort projection.

Capability derives from the reviewed manifest: the single resolver `scripts/fleet-repos.sh` reads `fleet/repos.txt`, applying the same fail-closed contract it had before (missing/empty manifest → print nothing, warn, exit 3 → callers do-nothing-this-cycle). Because #554 already funneled every consumer (throttle, urgent-poll, ci-health, triage-scan) through that one resolver, repointing the resolver repoints the whole fleet — no other consumer logic changes. The topic becomes a derived projection synced best-effort by `scripts/fleet-topic-sync.sh`; a topic-write failure (no repo-admin) warns and never fails, because the topic gates nothing. No privileged decision is ever made against the topic again.

## Consequences

### Positive

- **Auditable admission.** Adding a repo to the fleet is a reviewed PR; git history records who, when, and who approved — a real admission log. The capability-grant boundary sits at a reviewed artifact, consistent with ADR-0047.
- **Single, non-scattered source** honoring #139's real intent without the settings-write boundary #555 objected to. No hardcoded lists; no API call, no auth, no search-index lag in the resolver.
- **Closes #555** — self-enrollment by writing a repo topic is no longer possible; topic-write grants nothing.

### Negative

- The derived topic can **drift** from the manifest if the sync lacks repo-admin (the fleet App is not granted admin in this PR, by design). Accepted: the topic is cosmetic; drift affects only dashboards / `gh search`, never a privileged decision.

### Neutral

- Option E (org Team / custom repository property) remains the long-term target if the repos ever migrate from the `jaetill` user account to a GitHub org — the manifest is a clean intermediate that an org Team could later mirror.

## Pros and Cons of the Options

### Option A: Topic-only (status quo #554)

- ✅ Pro: Live, queryable; one resolver; no second artifact to keep in sync.
- ❌ Con: Capability grant derives from a repo-settings write — unaudited, no review, no admission log (the #555 objection). Topic-write is repo-admin; an actor with admin on any repo could self-enroll.
- ❌ Con: Resolver depends on a live API call + auth + a search/REST view that can lag a topic change.

### Option B: Manifest-only, no topic

- ✅ Pro: Authoritative record is reviewed + audited; resolver is dependency-free and fast; trust boundary at a code change.
- ❌ Con: Loses the `fleet` topic that dashboards / `gh search` rely on — queryability regresses with nothing to replace it.

### Option C: Manifest ∧ topic cross-check (#563's original allowlist)

- ✅ Pro: Manifest gates authorization, so self-enroll-by-topic is blocked.
- ❌ Con: The topic is redundant once the manifest is authoritative — it adds a second required write (topic AND manifest) to admit a repo, the friction of B without the simplicity of A, and a JSON+jq dependency in the gate.
- ❌ Con: Two-condition resolution is more failure modes for no security gain over D.

### Option D: Manifest authoritative + topic derived (chosen)

- ✅ Pro: Authoritative record reviewed + audited (admission log = git history); resolver dependency-free + fail-closed; trust boundary at a reviewed artifact.
- ✅ Pro: Keeps the topic for queryability as a best-effort, non-gating projection — no regression for dashboards.
- ❌ Con: The topic can drift if the reconciler lacks repo-admin. Accepted — cosmetic only.

### Option E: GitHub-native org Team / custom repository property

- ✅ Pro: Native, queryable, audited via org audit log; the "right" long-term primitive.
- ❌ Con: Requires migrating the repos from the `jaetill` user account to a GitHub org — out of scope now. Deferred; D is a clean intermediate that E can later mirror.

## Implementation notes

- System of record: `fleet/repos.txt` (newline-delimited names; `#` comments + blanks allowed).
- Resolver: `scripts/fleet-repos.sh` reads the manifest, strips comments/blanks, normalizes to one space-separated line; fail-closed exit 3 on missing/empty.
- Derived-topic reconciler: `scripts/fleet-topic-sync.sh` (best-effort; warns-not-fails on topic-write errors) + `.github/workflows/fleet-topic-sync.yml` (push to `fleet/repos.txt` + manual dispatch; mints the fleet App token).
- Affected consumers (roster-comment references only, logic unchanged): `.github/workflows/ci-health.yml`, `.github/workflows/urgent-poll.yml`, `scripts/fleet-inflight.sh`.
- Deliberately NOT done: granting the fleet App Administration(write). Full topic auto-sync needs it; until then the sync warns and the topic is reconciled manually. Granting admin would broaden the loop's blast radius, contrary to #555's intent.

## Links

- #555 — security review flagging that #554 moved the capability-grant trust boundary to an unaudited repo-settings write (the problem this ADR resolves).
- #563 — the implementing PR (originally the manifest∧topic allowlist of Option C; repointed to Option D).
- #139, #39 — the "single source of truth, no hardcoded lists" intent that #554 served; this ADR preserves that intent at a reviewed artifact.
- ADR-0047 — capability-delta firewall; the capability-grant boundary this manifest anchors.
- ADR-0030 — fleet dispatch through the promoter; one of the consumers of the resolver this ADR repoints.
