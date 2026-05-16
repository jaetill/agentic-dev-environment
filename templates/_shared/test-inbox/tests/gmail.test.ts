import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { gmail_v1 } from "googleapis";

import {
  GmailInboxProvider,
  buildGmailQuery,
  decodeBase64Url,
  extractBody,
  gmailOAuthFromEnv,
  parseGmailMessage,
} from "../src/providers/gmail.js";

function encodeBase64Url(text: string): string {
  return Buffer.from(text, "utf-8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

describe("buildGmailQuery", () => {
  it("composes a to/subject/after query", () => {
    const q = buildGmailQuery({
      to: "jaetill+gn-1@gmail.com",
      subjectContains: "invite",
      sentAfter: new Date(1_700_000_000_000),
    });
    expect(q).toBe('to:jaetill+gn-1@gmail.com subject:"invite" after:1700000000');
  });

  it("returns empty string when criteria is empty", () => {
    expect(buildGmailQuery({})).toBe("");
  });

  it("escapes double quotes in subject", () => {
    expect(buildGmailQuery({ subjectContains: 'foo "bar" baz' })).toBe(
      'subject:"foo \\"bar\\" baz"',
    );
  });
});

describe("decodeBase64Url", () => {
  it("decodes URL-safe base64 to UTF-8", () => {
    const encoded = encodeBase64Url("Hello, world!");
    expect(decodeBase64Url(encoded)).toBe("Hello, world!");
  });

  it("handles strings containing - and _ (URL-safe chars)", () => {
    const text = ">>>some?text>>>";
    const encoded = encodeBase64Url(text);
    // sanity: encoded form should contain at least one URL-safe substitution
    expect(encoded).toMatch(/[-_]/);
    expect(decodeBase64Url(encoded)).toBe(text);
  });
});

describe("extractBody", () => {
  it("returns body data for a single-part payload of the requested type", () => {
    const payload: gmail_v1.Schema$MessagePart = {
      mimeType: "text/plain",
      body: { data: encodeBase64Url("plain body") },
    };
    expect(extractBody(payload, "text/plain")).toBe("plain body");
  });

  it("walks multipart/alternative trees to find the matching mimeType", () => {
    const payload: gmail_v1.Schema$MessagePart = {
      mimeType: "multipart/alternative",
      parts: [
        { mimeType: "text/plain", body: { data: encodeBase64Url("PLAIN") } },
        { mimeType: "text/html", body: { data: encodeBase64Url("<p>HTML</p>") } },
      ],
    };
    expect(extractBody(payload, "text/plain")).toBe("PLAIN");
    expect(extractBody(payload, "text/html")).toBe("<p>HTML</p>");
  });

  it("returns undefined when no part matches", () => {
    const payload: gmail_v1.Schema$MessagePart = {
      mimeType: "text/plain",
      body: { data: encodeBase64Url("only plain") },
    };
    expect(extractBody(payload, "text/html")).toBeUndefined();
  });

  it("returns undefined for an undefined payload", () => {
    expect(extractBody(undefined, "text/plain")).toBeUndefined();
  });
});

describe("parseGmailMessage", () => {
  it("maps headers + body + internalDate + label-driven folder", () => {
    const msg: gmail_v1.Schema$Message = {
      id: "abc123",
      internalDate: "1700000000000",
      labelIds: ["INBOX", "UNREAD"],
      payload: {
        headers: [
          { name: "From", value: "no-reply@cognito.example" },
          { name: "To", value: "jaetill+gn-1@gmail.com" },
          { name: "Subject", value: "Your temporary password" },
        ],
        mimeType: "multipart/alternative",
        parts: [
          { mimeType: "text/plain", body: { data: encodeBase64Url("plaintext body") } },
          { mimeType: "text/html", body: { data: encodeBase64Url("<p>html body</p>") } },
        ],
      },
    };

    const out = parseGmailMessage(msg, "inbox");
    expect(out).not.toBeNull();
    expect(out!.id).toBe("abc123");
    expect(out!.from).toBe("no-reply@cognito.example");
    expect(out!.to).toBe("jaetill+gn-1@gmail.com");
    expect(out!.subject).toBe("Your temporary password");
    expect(out!.bodyText).toBe("plaintext body");
    expect(out!.bodyHtml).toBe("<p>html body</p>");
    expect(out!.receivedAt.getTime()).toBe(1_700_000_000_000);
    expect(out!.folder).toBe("inbox");
    expect(out!.labels).toEqual(["INBOX", "UNREAD"]);
  });

  it("returns null when the message has no id", () => {
    expect(parseGmailMessage({}, "inbox")).toBeNull();
  });

  it("treats missing headers as empty strings", () => {
    const out = parseGmailMessage({ id: "x", payload: {} }, "spam");
    expect(out!.from).toBe("");
    expect(out!.to).toBe("");
    expect(out!.subject).toBe("");
    expect(out!.bodyText).toBe("");
    expect(out!.bodyHtml).toBeUndefined();
    expect(out!.folder).toBe("spam");
  });
});

describe("GmailInboxProvider", () => {
  function makeMockClient(opts: {
    inboxIds?: string[];
    spamIds?: string[];
    messages?: Record<string, gmail_v1.Schema$Message>;
  }) {
    const messages = opts.messages ?? {};
    const list = vi.fn(async (req: { labelIds?: string[] }) => {
      const which = req.labelIds?.[0];
      const ids = which === "INBOX" ? (opts.inboxIds ?? []) : (opts.spamIds ?? []);
      return { data: { messages: ids.map((id) => ({ id })) } };
    });
    const get = vi.fn(async (req: { id: string }) => ({
      data: messages[req.id] ?? { id: req.id },
    }));
    const batchModify = vi.fn(async () => ({ data: {} }));
    const client = {
      users: {
        messages: { list, get, batchModify },
      },
    } as unknown as gmail_v1.Gmail;
    return { client, list, get, batchModify };
  }

  it("lists messages from INBOX + SPAM and tags the folder per message", async () => {
    const { client, list } = makeMockClient({
      inboxIds: ["i1"],
      spamIds: ["s1"],
      messages: {
        i1: {
          id: "i1",
          internalDate: "2000",
          payload: {
            headers: [{ name: "Subject", value: "in-inbox" }],
            mimeType: "text/plain",
            body: { data: encodeBase64Url("inbox body") },
          },
        },
        s1: {
          id: "s1",
          internalDate: "1000",
          payload: {
            headers: [{ name: "Subject", value: "in-spam" }],
            mimeType: "text/plain",
            body: { data: encodeBase64Url("spam body") },
          },
        },
      },
    });
    const provider = new GmailInboxProvider({
      baseEmail: "jaetill@gmail.com",
      gmail: client,
    });

    const out = await provider.listRecentMessages({ to: "jaetill+x@gmail.com" });

    expect(list).toHaveBeenCalledTimes(2);
    expect(out).toHaveLength(2);
    // Most recent first (i1 internalDate > s1).
    expect(out[0]!.id).toBe("i1");
    expect(out[0]!.folder).toBe("inbox");
    expect(out[1]!.id).toBe("s1");
    expect(out[1]!.folder).toBe("spam");
  });

  it("returns empty array when no messages match in either folder", async () => {
    const { client } = makeMockClient({});
    const provider = new GmailInboxProvider({
      baseEmail: "jaetill@gmail.com",
      gmail: client,
    });
    expect(await provider.listRecentMessages({ to: "x@y.com" })).toEqual([]);
  });

  it("markRead calls batchModify with removeLabelIds=[UNREAD]", async () => {
    const { client, batchModify } = makeMockClient({});
    const provider = new GmailInboxProvider({
      baseEmail: "jaetill@gmail.com",
      gmail: client,
    });
    await provider.markRead(["a", "b", "c"]);
    expect(batchModify).toHaveBeenCalledWith({
      userId: "me",
      requestBody: {
        ids: ["a", "b", "c"],
        removeLabelIds: ["UNREAD"],
      },
    });
  });

  it("markRead with empty array does not call the API", async () => {
    const { client, batchModify } = makeMockClient({});
    const provider = new GmailInboxProvider({
      baseEmail: "jaetill@gmail.com",
      gmail: client,
    });
    await provider.markRead([]);
    expect(batchModify).not.toHaveBeenCalled();
  });

  it("throws if neither oauth nor gmail client is supplied", () => {
    expect(
      () => new GmailInboxProvider({ baseEmail: "jaetill@gmail.com" }),
    ).toThrow(/oauth.*gmail/);
  });
});

describe("gmailOAuthFromEnv", () => {
  const savedEnv = { ...process.env };

  beforeEach(() => {
    delete process.env["GMAIL_TESTER_CLIENT_ID"];
    delete process.env["GMAIL_TESTER_CLIENT_SECRET"];
    delete process.env["GMAIL_TESTER_REFRESH_TOKEN"];
  });

  afterEach(() => {
    process.env = { ...savedEnv };
  });

  it("returns creds when all three env vars are set", () => {
    process.env["GMAIL_TESTER_CLIENT_ID"] = "cid";
    process.env["GMAIL_TESTER_CLIENT_SECRET"] = "csec";
    process.env["GMAIL_TESTER_REFRESH_TOKEN"] = "rt";
    expect(gmailOAuthFromEnv()).toEqual({
      clientId: "cid",
      clientSecret: "csec",
      refreshToken: "rt",
    });
  });

  it("throws listing each missing var", () => {
    process.env["GMAIL_TESTER_CLIENT_ID"] = "cid";
    expect(() => gmailOAuthFromEnv()).toThrow(
      /GMAIL_TESTER_CLIENT_SECRET.*GMAIL_TESTER_REFRESH_TOKEN/,
    );
  });
});
