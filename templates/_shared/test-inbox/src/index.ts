// Core, Playwright-free public surface. Anything that imports
// `@playwright/test` MUST live in `./playwright-fixture.ts` and be
// imported via the `@platform/test-inbox/playwright` subpath only.

export { TestInbox } from "./inbox.js";
export type { TestInboxConfig, WaitForEmailCriteria } from "./inbox.js";

export type { EmailMessage, InboxProvider, ListCriteria } from "./providers/provider.js";
export { GmailInboxProvider, gmailOAuthFromEnv } from "./providers/gmail.js";
export type { GmailOAuthCreds, GmailProviderConfig } from "./providers/gmail.js";

export type { EmailParser } from "./parsers/parser.js";
export { CognitoInviteParser } from "./parsers/cognito-invite.js";
export type { CognitoInvitePayload } from "./parsers/cognito-invite.js";

export { buildAliasAddress, parseAliasAddress } from "./address.js";
export type { AliasParts } from "./address.js";

export { cleanupCognitoTestUsers } from "./cleanup.js";
export type { CognitoCleanupOptions, CognitoCleanupResult } from "./cleanup.js";

// Pure fixture function — Playwright-free. Consumers use this with their
// own `@playwright/test` install to avoid the "two-copies" hazard. The
// sugar `test`/`expect` exports are at `@platform/test-inbox/playwright`.
export { inboxFixture, DEFAULT_INBOX_PROJECT, DEFAULT_INBOX_RUN_ID } from "./inbox-fixture-core.js";
export type { InboxFixtureArgs } from "./inbox-fixture-core.js";
