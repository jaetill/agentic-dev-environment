---
name: playwright-e2e
description: Use when writing or debugging Playwright E2E tests. Covers webServer config, flaky-network handling, and the inboxFixture pattern from templates/_shared/test-inbox.
---

# Playwright E2E

## When to consult

- Authoring new E2E tests with `@playwright/test`.
- Debugging flaky CI runs that pass locally.
- Setting up tests that need a backing dev server or external service.

## Gotchas

### `webServer` start-up race

**Symptom:** First test fails with connection refused; subsequent tests pass.

**Root cause:** `webServer.url` health check fires before the server actually binds.

**Fix:** Use `webServer.url` pointing at an endpoint that 200s ONLY when the server is ready (not just any port-bound endpoint). Add `reuseExistingServer: !process.env.CI` so local runs reuse a long-lived dev server.

```typescript
// playwright.config.ts
webServer: {
  command: "npm run dev",
  url: "http://localhost:3000/api/health",  // must return 200 when truly ready
  reuseExistingServer: !process.env.CI,
  timeout: 120_000,
}
```

### Flaky network handling

**Symptom:** Tests pass locally, randomly fail on CI with timeouts.

**Root cause:** External APIs (Gmail, Postmark, Stripe) have latency variance CI runners don't tolerate.

**Fix:** Stub external dependencies at the network layer (`page.route()`), don't try to make them faster. Reserve real-API tests for a small, targeted suite that runs nightly, not on every PR.

### `inboxFixture` pattern (test-inbox package)

For testing flows that send email (Cognito invites, password resets, magic links), use the `inboxFixture` from `@jaetill/test-inbox`. It's a Playwright fixture that:
- Acquires a unique plus-alias on `jaetill@gmail.com`.
- Provides a `waitForEmail(predicate, timeout)` method that polls Gmail via API.
- Cleans up after the test.

```typescript
import { test, expect } from "@jaetill/test-inbox";

test("invite flow", async ({ page, inbox }) => {
  await page.goto("/admin/invite");
  await page.fill("input[name=email]", inbox.address);
  await page.click("button[type=submit]");
  const inviteEmail = await inbox.waitForEmail(m => m.subject.includes("invite"));
  const link = extractLinkFromBody(inviteEmail.body);
  await page.goto(link);
  // ... continue test
});
```

The fixture cleans up the Cognito user AND deletes the Gmail label-bucket on test end. Per `project_test_inbox_decisions` memory: this is the canonical pattern for any project that sends real email in tests.

## Conventions

- E2E tests live in `e2e/` at project root, separate from unit/integration tests.
- One worker in CI for tests that hit external services (avoid Gmail rate limit).
- Trace on first retry: `trace: 'on-first-retry'` — full trace for the retry attempt without paying the cost on every passing run.

## See also

- [[standards-testing]] — overall testing strategy
- [[postmark-email]] — email senders being tested
- [[cognito-pool-quirks]] — Cognito test pool cleanup
- `templates/_shared/test-inbox/` workspace package
