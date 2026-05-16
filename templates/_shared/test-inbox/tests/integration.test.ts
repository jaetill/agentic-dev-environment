import { describe, it, expect } from "vitest";

import {
  GmailInboxProvider,
  gmailOAuthFromEnv,
} from "../src/providers/gmail.js";

const RUN_INTEGRATION = process.env["TEST_INBOX_INTEGRATION"] === "1";

describe.skipIf(!RUN_INTEGRATION)("@platform/test-inbox — integration", () => {
  it("authenticates with Gmail and lists recent inbox messages", async () => {
    const baseEmail = process.env["GMAIL_TESTER_EMAIL"];
    if (!baseEmail) {
      throw new Error("GMAIL_TESTER_EMAIL must be set for integration tests");
    }
    const provider = new GmailInboxProvider({
      oauth: gmailOAuthFromEnv(),
      baseEmail,
      pageSize: 5,
    });
    // Empty criteria → returns the most recent N messages from INBOX + SPAM.
    // We don't assert content; just that the call succeeds with valid OAuth.
    const messages = await provider.listRecentMessages({});
    expect(Array.isArray(messages)).toBe(true);
  });

  // Phase 2 manual integration test:
  // Send yourself a test email (manually or via a helper with gmail.send scope),
  // then verify the provider retrieves it. Wired up when the Gmail account
  // OAuth is set up. Until then, the Phase 5 invite-flow test exercises the
  // full retrieve-from-real-sender pipeline.
  it.todo("retrieves a known test email by subject within timeout");

  it.todo("retrieves an email that landed in SPAM and tags folder=spam");
});
