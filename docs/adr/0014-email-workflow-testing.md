# ADR-0014: Platform component for testing email-bearing workflows

- **Status:** Accepted
- **Date:** 2026-05-15
- **Deciders:** Jason
- **Tags:** testing, e2e, email, cognito, gmail, aws, platform-components

> Format: MADR 4.x (bundled-sub-decision form). See [`template.md`](template.md).

## Context and Problem Statement

Three jaetill projects exchange invite/notification emails with end users —
game-night-pwa (game invites + portal admin invites), jaetill-portal (admin
invites against the shared Cognito pool), and ai-teacher (parent
communications, eventually classroom invites). All three rely on real email
delivery; none have automated coverage that proves a workflow's email
arrives, lands in the inbox (not spam), and contains usable content.

The forcing function for this decision: an active bug where invitees receive
no usable email after an admin invite via the portal. The bug could be
anywhere in the chain — Cognito rejection, SES send failure, spam-folder
delivery, broken template — and "look at CloudWatch logs and the inbox
manually" doesn't scale across three projects.

The question: what does shared test infrastructure for email-bearing
workflows look like, and where does it live?

## Decision Drivers

- **Reusability across three projects.** Game-night-pwa, jaetill-portal, and
  ai-teacher all need this. A per-project solution would triplicate work.
- **Spam-folder visibility is mandatory.** Tests that only check the inbox
  miss the exact bug class we're trying to debug. The harness must read
  INBOX *and* SPAM.
- **Real email path, not mocks.** The bug we're chasing is at the SES →
  Gmail delivery boundary. Mocked email defeats the purpose.
- **Safety on a shared Cognito pool.** All three apps share
  `us-east-2_xneeJzaDJ`. Test users created during runs must be cleanly
  removable without risk of deleting real users.
- **Solo-scale operations.** No team to maintain a dedicated test
  infrastructure stack. Setup must fit in a single Gmail OAuth flow and an
  AWS Secrets Manager entry.
- **Template-propagation.** Platform-level components live in
  `templates/_shared/`; per-project usage is via a `file:` dep until the
  workspace is published (mirrors the `terraform-modules/` precedent).
- **Discoverability for AI agents.** The e2e-tester and functional-tester
  subagents must be able to find and use this fixture without re-deriving
  the pattern each time.

## Considered Options

This is a bundled-sub-decision ADR — five tightly-coupled choices share
the same decision context:

- Sub-decision 1: **Inbox provider** — how do tests read the inbox?
- Sub-decision 2: **Test address strategy** — what address does the test register?
- Sub-decision 3: **Cognito test pool** — separate pool, real pool, or no cleanup?
- Sub-decision 4: **OAuth secret storage** — where do tester credentials live?
- Sub-decision 5: **Public surface** — programmatic class only, Playwright fixture only, or both?

## Decision Outcome

We chose the bundle:

- Sub-decision 1 → **Gmail API** (with `InboxProvider` interface for later providers)
- Sub-decision 2 → **Plus-aliasing on `jaetill@gmail.com`** (the real account, not a dedicated one)
- Sub-decision 3 → **Real pool with alias-prefix guard** (option B from the plan; pool-name override)
- Sub-decision 4 → **AWS Secrets Manager** at `platform/test-inbox/gmail-tester`
- Sub-decision 5 → **Both** — programmatic `TestInbox` class + Playwright fixture wrapping it

The bundle is internally consistent because every choice prioritises *real
end-to-end fidelity* over isolation. We exercise the real Cognito pool, the
real Gmail account, the real Secrets-Manager-backed credentials — and use
layered software guards (alias prefix, pool-name override, mark-read-not-delete)
to keep the tests safe rather than building isolation infrastructure.

## Consequences

### Positive

- **Real-pool bugs surface.** Tests against the production Cognito pool
  catch real-pool config (template, attribute rules, `ALLOW_USER_AUTH`
  quirks). A separate test pool would have hidden these.
- **One shared component, three consumers.** Game-night-pwa, portal, and
  ai-teacher pull the same `@platform/test-inbox` and inherit fixes for
  free.
- **Spam-folder visibility is first-class.** `inbox.lastWasInSpam()` flags
  the exact bug pattern we're chasing without needing manual inbox checks.
- **No new Gmail account, no bot-flag risk.** Plus-aliases on the existing
  long-lived `jaetill@gmail.com` avoid Google's bot-detection sweeps that
  hit fresh receive-only accounts.
- **Layered Cognito-cleanup safety.** Server-side `email ^=` filter,
  client-side `startsWith` check, pool-name guard, and an explicit env
  override mean four independent things must fail before a real user can
  be touched.
- **Secrets centralized.** AWS Secrets Manager rotation in one place; no
  syncing across consumer-repo GitHub Secrets.

### Negative

- **Pollution risk in the real inbox.** A misconfigured test that sends to
  `jaetill@gmail.com` instead of `jaetill+gn-foo@gmail.com` would land in
  Jason's real inbox. Mitigation: Gmail filters routing `jaetill+gn-* OR
  jaetill+portal-* OR jaetill+ai-teacher-*` to a `tester/` label and out
  of the inbox view.
- **`PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true` is a load-bearing
  string.** The Cognito pool name doesn't contain "test", so cleanup needs
  this env var. If it's set globally in the wrong shell, the guard
  collapses to one layer (alias prefix). Mitigation: set it only in the
  test command line, never in shell profile.
- **Gmail-only at launch.** A `MailosaurProvider` or similar would let
  faster inner-loop tests trap SES before delivery; deferred per the
  scope rule.
- **OAuth refresh tokens can rotate.** Google may invalidate the tester
  refresh token on inactivity or scope change. Mitigation: a runbook for
  "tests started failing with 401; rotate refresh token" lives in Standard
  03 §14.

### Neutral

- **`@platform/test-inbox` is unpublished.** Consumers depend on it via
  `file:` path, same as `terraform-modules/`. When the workspace
  publishes versioned packages, this becomes a regular npm dep without
  consumer code changes (the export surface is stable).
- **Plus-aliases vs Workspace tester account is a future migration.** If
  pollution becomes painful, swap `GMAIL_TESTER_EMAIL` to a Workspace
  account on `jaetill.com` without changing the env-var surface or any
  consumer code.

## Pros and Cons of the Options

### Sub-decision 1: Inbox provider

| Option | Pros | Cons |
|---|---|---|
| **Gmail API** (chosen) | Spam-folder access via API; OAuth (no app-password risk); refresh tokens long-lived; covers all three projects which send to Gmail recipients | Gmail-specific; abstraction needed if we later test workflows that send to non-Gmail recipients |
| IMAP | Provider-agnostic | App passwords required (more risk); spam-folder semantics inconsistent across providers |
| Mailosaur / inbox-as-a-service | Sub-second polling; never delivers to real inbox; first-class spam trap | Paid; doesn't exercise real Gmail delivery, which is exactly what we want to test |
| Cognito event hook | Catches the email payload before SES sends it | Misses the SES → Gmail delivery path entirely (the bug surface we care about) |

### Sub-decision 2: Test address strategy

| Option | Pros | Cons |
|---|---|---|
| **Plus-aliasing on `jaetill@gmail.com`** (chosen) | Zero bot-flag risk (aged account); free; unique per test run | Pollutes real inbox view without Gmail filters |
| Dedicated `jaetill.platform.tester@gmail.com` | Clean isolation | Google may flag a fresh receive-only account during anti-bot sweeps |
| Workspace tester on `jaetill.com` | Most robust; survives policy churn | Costs ~$6/mo; setup overhead |
| Per-run throwaway inbox (Mailinator etc.) | No setup | Public inboxes; spam-folder semantics not real |

### Sub-decision 3: Cognito test pool

| Option | Pros | Cons |
|---|---|---|
| **Real pool with alias-prefix guard** (chosen) | Tests exercise real-pool config (the whole point); guards prevent accidental cross-contamination | Requires `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true` because pool name doesn't match "test" |
| Separate test pool | Safer isolation | Pool config diverges from real; defeats E2E purpose for pool-specific bugs |
| No cleanup at all | Simplest | Real pool fills with stale test users over time |

### Sub-decision 4: OAuth secret storage

| Option | Pros | Cons |
|---|---|---|
| **AWS Secrets Manager** at `platform/test-inbox/gmail-tester` (chosen) | One source of truth; rotation in one place; same pattern as other shared secrets; consumer-repo OIDC roles already exist | Each consumer repo needs `secretsmanager:GetSecretValue` IAM scoped to this ARN |
| Per-repo GitHub Actions secrets | Zero AWS coupling | Token rotation means updating N repos; drift risk |
| 1Password / external vault | Vendor-flexible | Adds a new vault to consumer-repo CI; doesn't fit existing OIDC pattern |

### Sub-decision 5: Public surface

| Option | Pros | Cons |
|---|---|---|
| **Both — `TestInbox` class + Playwright fixture** (chosen) | Playwright path is ergonomic for most tests; programmatic path supports Lambda-side integration tests | Slightly more surface to maintain |
| Class only | Smallest API | Every consumer rewrites Playwright wiring |
| Fixture only | Most ergonomic | Forces Playwright on non-E2E callers |

## Implementation notes

- **Component:** `templates/_shared/test-inbox/` — TypeScript, Node ≥20, ESM,
  tested with Vitest. Public surface: `TestInbox`, `GmailInboxProvider`,
  `CognitoInviteParser`, `buildAliasAddress` / `parseAliasAddress`,
  `cleanupCognitoTestUsers`, plus `test` / `expect` exports under
  `@platform/test-inbox/playwright`.
- **Consumer install:** `file:` dep in `package.json`, matching the
  `terraform-modules/` precedent. When the workspace publishes versioned
  packages, the `file:` form becomes a regular `npm` version pin without
  any consumer code change.
- **Cognito-cleanup safety layers (load-bearing):**
  1. `emailMatchesAlias` required and non-empty.
  2. Server-side filter `email ^= "<alias>"`.
  3. Client-side `startsWith` re-check on each returned user.
  4. Pool-name must contain "test" OR `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true`.
  5. Optional `poolNameContains` consumer-specified extra check.
  Weakening any of these requires this ADR to be superseded.
- **Standards doc:** [`docs/standards/03-testing.md`](../standards/03-testing.md)
  §14 — usage pattern, env-var surface, secret retrieval, refresh-token
  rotation runbook.
- **Affected consumer projects:** game-night-pwa first (the bug-debug
  driver), then jaetill-portal and ai-teacher.
- **Out of scope for this ADR but flagged for follow-up:**
  - SES domain reputation / SPF / DKIM / DMARC tuning, if Phase 5 confirms
    delivery is the bug. Belongs in a separate observability/deliverability ADR.
  - `MailosaurProvider` as a second `InboxProvider` for fast inner-loop
    tests. Architecture supports it; not built.
  - Wiring the component into the `e2e-tester` subagent's prompt so it
    automatically reaches for `inbox` fixtures when testing email-bearing
    flows.

## Links

- Plan document `PLAN_email_testing_platform.md` (consumed and removed after ratification) — the spec this ADR ratifies.
- [Gmail API — Users.messages](https://developers.google.com/gmail/api/reference/rest/v1/users.messages) — list/get/batchModify reference.
- [Cognito — ListUsers filter syntax](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_ListUsers.html#API_ListUsers_RequestSyntax) — the `^=` operator the cleanup helper depends on.
- [Standard 03 §14](../standards/03-testing.md) — operational usage and the refresh-token rotation runbook.
- ADR-0004 — Testing standard parent (this ADR adds the email-workflow case).
- ADR-0006 — Secrets standard (this ADR follows the AWS-Secrets-Manager pattern).
