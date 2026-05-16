# @platform/test-inbox

Platform component for end-to-end testing of workflows that involve email:
invites, temp passwords, magic links, password resets, notifications, nudges.

**Status:** Phase 1 — scaffold only. Public API is stubbed; implementations
land in subsequent phases. See `PLAN_email_testing_platform.md` in the
workspace root.

## What it does

Given a real email address (a dedicated tester Gmail account, plus-aliased
per test), this component lets a test:

1. Trigger a real workflow under test (e.g. admin sends an invite).
2. Poll the inbox **and the spam folder** for a matching message.
3. Parse the message (e.g. extract a Cognito temp password and login URL).
4. Use the extracted data to complete the flow (sign in, click link, …).
5. Clean up: mark emails read, optionally delete the test Cognito user.

The whole point of the spam-folder polling is that a workflow which "works"
but lands its emails in spam is a bug, not a success. The fixture flags
this explicitly via `inbox.lastWasInSpam()`.

## Install (consumer projects)

Until this package is published, consumer projects depend on it via a
`file:` path — same pattern as `templates/_shared/terraform-modules/`.

```jsonc
// in consumer project's package.json
{
  "devDependencies": {
    "@platform/test-inbox": "file:../../Agentic Dev Environment/templates/_shared/test-inbox"
  }
}
```

## Configure

| Env var | Purpose |
|---|---|
| `GMAIL_TESTER_EMAIL` | Base address. Default: `jaetill@gmail.com` (decision 2026-05-15; uses plus-aliases on the real account to avoid Google bot-flagging a fresh account). |
| `GMAIL_TESTER_CLIENT_ID` | OAuth client ID (Google Cloud project) |
| `GMAIL_TESTER_CLIENT_SECRET` | OAuth client secret |
| `GMAIL_TESTER_REFRESH_TOKEN` | Long-lived refresh token for the tester account |
| `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP` | Required when running `cleanupCognitoTestUsers` against `us-east-2_xneeJzaDJ` (the production pool's name doesn't contain "test"; the alias-prefix guard is the load-bearing safety). |

In CI: pull these from AWS Secrets Manager at `platform/test-inbox/gmail-tester`
(keys: `clientId`, `clientSecret`, `refreshToken`) using the consumer repo's
existing GitHub OIDC role.

Local: Gmail filter recommended to keep test mail out of your real inbox view —
`to:(jaetill+gn-* OR jaetill+portal-* OR jaetill+ai-teacher-*)` → Skip Inbox + Label `tester/`.

## Use — programmatic

```ts
import { TestInbox } from "@platform/test-inbox";

const inbox = new TestInbox({
  project: "gn",
  runId: process.env.GITHUB_RUN_ID ?? String(Date.now()),
  testName: "admin-invite",
});

// Use inbox.address as the invitee email in the workflow under test.
await triggerAdminInvite(inbox.address);

const invite = await inbox.waitForCognitoInvite();
console.log(invite.tempPassword, invite.loginUrl);
console.log("in spam?", inbox.lastWasInSpam());

await inbox.cleanup();
```

## Use — Playwright (recommended: manual wiring)

When this package is consumed via `file:`, importing
`@platform/test-inbox/playwright` can trip Playwright's
"Requiring @playwright/test second time" guard (two node_modules trees
both contain `@playwright/test`). The resilient pattern is to use the
pure `inboxFixture` function against the consumer's own
`@playwright/test`:

```ts
import { test as base, expect } from "@playwright/test";
import { inboxFixture } from "@platform/test-inbox";

const test = base.extend({
  inbox: async ({}, use, testInfo) => {
    await inboxFixture(
      {
        inboxProject: "gn",
        inboxRunId: process.env.GITHUB_RUN_ID ?? String(Date.now()),
        inboxOverrides: {},
        title: testInfo.title,
      },
      use,
    );
  },
});

test("admin invite delivers a usable temp password", async ({ inbox }) => {
  // ... drive the workflow under test using inbox.address ...
  const invite = await inbox.waitForCognitoInvite();
  expect(invite.tempPassword).toMatch(/.{8,}/);
  expect(inbox.lastWasInSpam()).toBe(false);
});
```

The `@platform/test-inbox/playwright` sugar entry point exists for
consumers using a workspace setup that successfully dedupes
`@playwright/test` (pnpm workspaces, yarn workspaces). Prefer the manual
wiring above when in doubt.

## Cognito user cleanup

Separate from inbox cleanup. Has explicit safety guards (see `src/cleanup.ts`):

- `emailMatchesAlias` is required; only users whose email **starts with**
  that alias are eligible for deletion.
- Optional `poolNameContains` check.
- Refuses to run against pools whose name doesn't contain "test", unless
  `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true` is set.

The guards are intentionally redundant. Read `cleanup.ts` and the
linked ADR-0014 before changing them.

## Develop

```bash
npm install
npm run build         # tsc → dist/
npm run typecheck     # tsc --noEmit
npm test              # vitest unit tests
npm run test:integration  # gated by TEST_INBOX_INTEGRATION=1; hits real Gmail
```

## Phase map

| Phase | What |
|---|---|
| 1 | Scaffold (this commit): package.json, tsconfig, vitest, stub source |
| 2 | Gmail provider — OAuth, INBOX+SPAM list, MIME parse |
| 3 | TestInbox class + parsers + alias generator + Cognito cleanup |
| 4 | Playwright fixture |
| 5 | game-night-pwa integration; reproduce the live invite bug |
| 6 | ADR-0014 + Standard 03 §6 |

## References

- ADR-0014 (TBD): platform component for testing email-bearing workflows
- Standard 03 §6 (TBD): testing email-bearing workflows
- `PLAN_email_testing_platform.md` (workspace root)
