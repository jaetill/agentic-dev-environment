import { google, type gmail_v1 } from "googleapis";
import { OAuth2Client } from "google-auth-library";

import type { EmailMessage, InboxProvider, ListCriteria } from "./provider.js";

export interface GmailOAuthCreds {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}

export interface GmailProviderConfig {
  /** OAuth credentials. Ignored when `gmail` client is supplied directly. */
  oauth?: GmailOAuthCreds;
  /** Pre-built Gmail client — injection point for unit tests. */
  gmail?: gmail_v1.Gmail;
  /** Inbox owner's email (the base address before plus-aliasing). */
  baseEmail: string;
  /** Page size for list calls; default 25. */
  pageSize?: number;
}

const DEFAULT_PAGE_SIZE = 25;

export class GmailInboxProvider implements InboxProvider {
  private readonly gmail: gmail_v1.Gmail;
  private readonly pageSize: number;

  constructor(private readonly config: GmailProviderConfig) {
    if (config.gmail) {
      this.gmail = config.gmail;
    } else if (config.oauth) {
      this.gmail = makeGmailClient(config.oauth);
    } else {
      throw new Error("GmailInboxProvider requires either `oauth` creds or a `gmail` client");
    }
    this.pageSize = config.pageSize ?? DEFAULT_PAGE_SIZE;
  }

  async listRecentMessages(criteria: ListCriteria): Promise<EmailMessage[]> {
    const query = buildGmailQuery(criteria);

    const [inboxIds, spamIds] = await Promise.all([
      this.listIds(query, "INBOX"),
      this.listIds(query, "SPAM"),
    ]);

    const messages = await Promise.all([
      ...inboxIds.map((id) => this.fetchMessage(id, "inbox")),
      ...spamIds.map((id) => this.fetchMessage(id, "spam")),
    ]);

    return messages
      .filter((m): m is EmailMessage => m !== null)
      .sort((a, b) => b.receivedAt.getTime() - a.receivedAt.getTime());
  }

  async markRead(messageIds: string[]): Promise<void> {
    if (messageIds.length === 0) return;
    await this.gmail.users.messages.batchModify({
      userId: "me",
      requestBody: {
        ids: messageIds,
        removeLabelIds: ["UNREAD"],
      },
    });
  }

  private async listIds(query: string, labelId: "INBOX" | "SPAM"): Promise<string[]> {
    const res = await this.gmail.users.messages.list({
      userId: "me",
      q: query,
      labelIds: [labelId],
      maxResults: this.pageSize,
    });
    return (res.data.messages ?? [])
      .map((m) => m.id)
      .filter((id): id is string => typeof id === "string");
  }

  private async fetchMessage(
    id: string,
    folder: "inbox" | "spam",
  ): Promise<EmailMessage | null> {
    const res = await this.gmail.users.messages.get({
      userId: "me",
      id,
      format: "full",
    });
    return parseGmailMessage(res.data, folder);
  }
}

/** Build a `users.messages.list` query string from criteria. */
export function buildGmailQuery(criteria: ListCriteria): string {
  const parts: string[] = [];
  if (criteria.to) parts.push(`to:${criteria.to}`);
  if (criteria.subjectContains) {
    parts.push(`subject:"${criteria.subjectContains.replace(/"/g, '\\"')}"`);
  }
  if (criteria.sentAfter) {
    // Gmail's `after:` operator takes epoch seconds.
    const epochSec = Math.floor(criteria.sentAfter.getTime() / 1000);
    parts.push(`after:${epochSec}`);
  }
  return parts.join(" ");
}

/** Convert a Gmail API message into our EmailMessage shape. Null on malformed. */
export function parseGmailMessage(
  msg: gmail_v1.Schema$Message,
  folder: "inbox" | "spam",
): EmailMessage | null {
  if (!msg.id) return null;
  const headers = (msg.payload?.headers ?? []).reduce<Record<string, string>>(
    (acc, h) => {
      if (h.name && h.value) acc[h.name.toLowerCase()] = h.value;
      return acc;
    },
    {},
  );

  const bodyText = extractBody(msg.payload, "text/plain") ?? "";
  const bodyHtml = extractBody(msg.payload, "text/html");

  // Gmail returns `internalDate` as a stringified epoch-ms.
  const receivedAt = msg.internalDate
    ? new Date(Number(msg.internalDate))
    : new Date(0);

  const result: EmailMessage = {
    id: msg.id,
    from: headers["from"] ?? "",
    to: headers["to"] ?? "",
    subject: headers["subject"] ?? "",
    bodyText,
    receivedAt,
    folder,
    labels: msg.labelIds ?? [],
  };
  if (bodyHtml !== undefined) {
    result.bodyHtml = bodyHtml;
  }
  return result;
}

/** Walk a Gmail message payload tree and return the first body matching mimeType. */
export function extractBody(
  payload: gmail_v1.Schema$MessagePart | undefined,
  mimeType: string,
): string | undefined {
  if (!payload) return undefined;

  if (payload.mimeType === mimeType && payload.body?.data) {
    return decodeBase64Url(payload.body.data);
  }
  for (const part of payload.parts ?? []) {
    const found = extractBody(part, mimeType);
    if (found !== undefined) return found;
  }
  return undefined;
}

/** Gmail bodies are base64url-encoded. Decode to a UTF-8 string. */
export function decodeBase64Url(data: string): string {
  const base64 = data.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(base64, "base64").toString("utf-8");
}

/** Create a Gmail v1 client authenticated via refresh token. */
export function makeGmailClient(oauth: GmailOAuthCreds): gmail_v1.Gmail {
  const auth = new OAuth2Client({
    clientId: oauth.clientId,
    clientSecret: oauth.clientSecret,
  });
  auth.setCredentials({ refresh_token: oauth.refreshToken });
  return google.gmail({ version: "v1", auth });
}

/** Load OAuth creds from standard env vars. Throws if any are missing. */
export function gmailOAuthFromEnv(): GmailOAuthCreds {
  const clientId = process.env["GMAIL_TESTER_CLIENT_ID"];
  const clientSecret = process.env["GMAIL_TESTER_CLIENT_SECRET"];
  const refreshToken = process.env["GMAIL_TESTER_REFRESH_TOKEN"];
  const missing = [
    !clientId && "GMAIL_TESTER_CLIENT_ID",
    !clientSecret && "GMAIL_TESTER_CLIENT_SECRET",
    !refreshToken && "GMAIL_TESTER_REFRESH_TOKEN",
  ].filter(Boolean);
  if (missing.length > 0) {
    throw new Error(`Missing Gmail OAuth env vars: ${missing.join(", ")}`);
  }
  return {
    clientId: clientId!,
    clientSecret: clientSecret!,
    refreshToken: refreshToken!,
  };
}
