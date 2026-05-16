import { buildAliasAddress } from "./address.js";
import { CognitoInviteParser, type CognitoInvitePayload } from "./parsers/cognito-invite.js";
import {
  GmailInboxProvider,
  gmailOAuthFromEnv,
  type GmailOAuthCreds,
} from "./providers/gmail.js";
import type { EmailMessage, InboxProvider } from "./providers/provider.js";

export interface TestInboxConfig {
  /** Project slug for alias namespacing, e.g. "gn" or "portal". */
  project: string;
  /** Unique run identifier (e.g. process.env.GITHUB_RUN_ID or Date.now()). */
  runId: string;
  /** Optional test name for further disambiguation. */
  testName?: string;
  /** Override base email; defaults to env GMAIL_TESTER_EMAIL. */
  baseEmail?: string;
  /** Override OAuth creds; defaults to env vars. */
  oauth?: GmailOAuthCreds;
  /** Provider injection point for tests; defaults to GmailInboxProvider. */
  provider?: InboxProvider;
}

export interface WaitForEmailCriteria {
  subjectMatches?: RegExp | string;
  bodyContains?: string;
  fromMatches?: RegExp | string;
  sentAfter?: Date;
  /** Default 60_000 ms. */
  timeoutMs?: number;
  /** Default 3_000 ms. */
  pollIntervalMs?: number;
}

const DEFAULT_TIMEOUT_MS = 60_000;
const DEFAULT_POLL_INTERVAL_MS = 3_000;

export class TestInbox {
  readonly address: string;
  private readonly provider: InboxProvider;
  private readonly seenIds = new Set<string>();
  private lastFolder: "inbox" | "spam" | null = null;

  constructor(config: TestInboxConfig) {
    const baseEmail = config.baseEmail ?? process.env["GMAIL_TESTER_EMAIL"];
    if (!baseEmail) {
      throw new Error("baseEmail is required (or set GMAIL_TESTER_EMAIL)");
    }
    this.address = buildAliasAddress({
      baseEmail,
      project: config.project,
      runId: config.runId,
      ...(config.testName !== undefined && { testName: config.testName }),
    });

    if (config.provider) {
      this.provider = config.provider;
    } else {
      this.provider = new GmailInboxProvider({
        oauth: config.oauth ?? gmailOAuthFromEnv(),
        baseEmail,
      });
    }
  }

  async waitForEmail(criteria: WaitForEmailCriteria): Promise<EmailMessage> {
    const timeoutMs = criteria.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    const pollIntervalMs = criteria.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS;
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      const listOpts: { to: string; sentAfter?: Date } = { to: this.address };
      if (criteria.sentAfter !== undefined) listOpts.sentAfter = criteria.sentAfter;
      const messages = await this.provider.listRecentMessages(listOpts);
      for (const msg of messages) {
        if (this.seenIds.has(msg.id)) continue;
        if (!this.criteriaMatch(msg, criteria)) continue;
        this.seenIds.add(msg.id);
        this.lastFolder = msg.folder;
        return msg;
      }
      await sleep(pollIntervalMs);
    }
    throw new Error(
      `TestInbox.waitForEmail: no matching message at ${this.address} within ${timeoutMs}ms`,
    );
  }

  async waitForCognitoInvite(
    opts: { timeoutMs?: number } = {},
  ): Promise<CognitoInvitePayload & { raw: EmailMessage }> {
    const parser = new CognitoInviteParser();
    const waitOpts: WaitForEmailCriteria = {};
    if (opts.timeoutMs !== undefined) waitOpts.timeoutMs = opts.timeoutMs;
    const raw = await this.waitForEmail(waitOpts);
    if (!parser.matches(raw)) {
      throw new Error(
        `TestInbox.waitForCognitoInvite: message ${raw.id} doesn't look like a Cognito invite (subject: "${raw.subject}")`,
      );
    }
    const payload = parser.parse(raw);
    return { ...payload, raw };
  }

  /** True if the last matching email was retrieved from the SPAM folder. */
  lastWasInSpam(): boolean {
    if (this.lastFolder === null) {
      throw new Error("TestInbox.lastWasInSpam: no email retrieved yet");
    }
    return this.lastFolder === "spam";
  }

  async cleanup(): Promise<void> {
    const messages = await this.provider.listRecentMessages({ to: this.address });
    const ids = messages.map((m) => m.id);
    await this.provider.markRead(ids);
  }

  private criteriaMatch(msg: EmailMessage, criteria: WaitForEmailCriteria): boolean {
    if (criteria.subjectMatches && !stringOrRegexMatch(msg.subject, criteria.subjectMatches)) {
      return false;
    }
    if (criteria.fromMatches && !stringOrRegexMatch(msg.from, criteria.fromMatches)) {
      return false;
    }
    if (criteria.bodyContains && !msg.bodyText.includes(criteria.bodyContains)) {
      return false;
    }
    if (criteria.sentAfter && msg.receivedAt < criteria.sentAfter) {
      return false;
    }
    return true;
  }
}

function stringOrRegexMatch(haystack: string, pattern: RegExp | string): boolean {
  if (pattern instanceof RegExp) return pattern.test(haystack);
  return haystack.includes(pattern);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
