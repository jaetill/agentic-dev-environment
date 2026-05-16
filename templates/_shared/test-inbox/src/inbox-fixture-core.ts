import { TestInbox, type TestInboxConfig } from "./inbox.js";

/**
 * Pure fixture function used by both the Playwright sugar entry point
 * (`@platform/test-inbox/playwright`) and consumers who prefer to wire
 * Playwright themselves (the manual-wiring path documented in the README).
 *
 * Manual-wiring is preferred when the consumer already has a pinned
 * `@playwright/test` installation; importing from
 * `@platform/test-inbox/playwright` works but pulls in this package's own
 * `@playwright/test` resolution and can trip Playwright's
 * "Requiring @playwright/test second time" guard when file:-linked.
 *
 * This module deliberately does NOT import `@playwright/test`. Anything
 * that re-exports from here stays Playwright-free.
 */

export interface InboxFixtureArgs {
  inboxProject: string;
  inboxRunId: string;
  inboxOverrides: Partial<TestInboxConfig>;
  title: string;
}

export async function inboxFixture(
  args: InboxFixtureArgs,
  use: (inbox: TestInbox) => Promise<void>,
): Promise<void> {
  const config: TestInboxConfig = {
    project: args.inboxProject,
    runId: args.inboxRunId,
    testName: args.title,
    ...args.inboxOverrides,
  };
  const inbox = new TestInbox(config);
  try {
    await use(inbox);
  } finally {
    try {
      await inbox.cleanup();
    } catch (err) {
      // eslint-disable-next-line no-console
      console.warn(
        `[@platform/test-inbox] cleanup failed for ${inbox.address}: ${(err as Error).message}`,
      );
    }
  }
}

export const DEFAULT_INBOX_PROJECT = "default";
export const DEFAULT_INBOX_RUN_ID: string =
  process.env["GITHUB_RUN_ID"] ?? String(Date.now());
