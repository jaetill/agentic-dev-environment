/**
 * Playwright fixture sugar — `import { test, expect } from
 * "@platform/test-inbox/playwright"`.
 *
 * This entry point depends on `@playwright/test` (peer dep). When this
 * package is consumed via `file:` and the consumer has its own copy of
 * `@playwright/test`, npm sometimes installs both — which trips
 * Playwright's "Requiring @playwright/test second time" guard.
 *
 * **Manual-wiring is the resilient path.** Consumers can import the pure
 * fixture function from `@platform/test-inbox` and wire it themselves
 * against their own `@playwright/test`:
 *
 *   import { test as base, expect } from "@playwright/test";
 *   import { inboxFixture } from "@platform/test-inbox";
 *
 *   export const test = base.extend({
 *     inbox: async ({}, use, testInfo) => {
 *       await inboxFixture(
 *         { inboxProject: "gn", inboxRunId: process.env.GITHUB_RUN_ID ?? String(Date.now()),
 *           inboxOverrides: {}, title: testInfo.title },
 *         use,
 *       );
 *     },
 *   });
 */

import { test as base, expect } from "@playwright/test";
import type { TestInboxConfig } from "./inbox.js";
import type { TestInbox } from "./inbox.js";
import {
  DEFAULT_INBOX_PROJECT,
  DEFAULT_INBOX_RUN_ID,
  inboxFixture,
} from "./inbox-fixture-core.js";

export interface InboxOptions {
  inboxProject: string;
  inboxRunId: string;
  inboxOverrides: Partial<TestInboxConfig>;
}

export interface InboxFixtures {
  inbox: TestInbox;
}

export const test = base.extend<InboxOptions & InboxFixtures>({
  inboxProject: [DEFAULT_INBOX_PROJECT, { option: true }],
  inboxRunId: [DEFAULT_INBOX_RUN_ID, { option: true }],
  inboxOverrides: [{}, { option: true }],
  inbox: async ({ inboxProject, inboxRunId, inboxOverrides }, use, testInfo) => {
    await inboxFixture(
      { inboxProject, inboxRunId, inboxOverrides, title: testInfo.title },
      use,
    );
  },
});

export { expect };

export type InboxFixtureOptions = InboxOptions;

export function createInboxTest(_opts?: unknown): typeof test {
  return test;
}
