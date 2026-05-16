import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { TestInbox } from "../src/inbox.js";
import type {
  EmailMessage,
  InboxProvider,
  ListCriteria,
} from "../src/providers/provider.js";

function mkMsg(partial: Partial<EmailMessage>): EmailMessage {
  return {
    id: "id",
    from: "no-reply@example.com",
    to: "jaetill+gn-1@gmail.com",
    subject: "",
    bodyText: "",
    receivedAt: new Date(1_700_000_000_000),
    folder: "inbox",
    labels: [],
    ...partial,
  };
}

class FakeProvider implements InboxProvider {
  public listCalls: ListCriteria[] = [];
  public readonly markRead = vi.fn(async () => {});

  constructor(private readonly batches: EmailMessage[][]) {}

  async listRecentMessages(criteria: ListCriteria): Promise<EmailMessage[]> {
    this.listCalls.push(criteria);
    return this.batches.shift() ?? [];
  }
}

describe("TestInbox", () => {
  const savedEnv = { ...process.env };

  beforeEach(() => {
    delete process.env["GMAIL_TESTER_EMAIL"];
  });

  afterEach(() => {
    process.env = { ...savedEnv };
  });

  it("composes the alias address from baseEmail + project + runId + testName", () => {
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1234",
      testName: "admin-invite",
      provider: new FakeProvider([]),
    });
    expect(inbox.address).toBe("jaetill+gn-1234-admin-invite@gmail.com");
  });

  it("falls back to GMAIL_TESTER_EMAIL when baseEmail not supplied", () => {
    process.env["GMAIL_TESTER_EMAIL"] = "jaetill@gmail.com";
    const inbox = new TestInbox({
      project: "gn",
      runId: "1",
      provider: new FakeProvider([]),
    });
    expect(inbox.address).toBe("jaetill+gn-1@gmail.com");
  });

  it("throws when baseEmail is not provided and env is missing", () => {
    expect(
      () =>
        new TestInbox({
          project: "gn",
          runId: "1",
          provider: new FakeProvider([]),
        }),
    ).toThrow(/baseEmail is required/);
  });

  it("waitForEmail returns the first matching message", async () => {
    const match = mkMsg({ id: "m1", subject: "Your invitation" });
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider: new FakeProvider([[match]]),
    });
    const out = await inbox.waitForEmail({
      subjectMatches: /invitation/,
      pollIntervalMs: 5,
      timeoutMs: 1000,
    });
    expect(out.id).toBe("m1");
    expect(inbox.lastWasInSpam()).toBe(false);
  });

  it("waitForEmail flags spam folder via lastWasInSpam", async () => {
    const match = mkMsg({ id: "m1", subject: "Your invitation", folder: "spam" });
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider: new FakeProvider([[match]]),
    });
    await inbox.waitForEmail({
      subjectMatches: /invitation/,
      pollIntervalMs: 5,
      timeoutMs: 1000,
    });
    expect(inbox.lastWasInSpam()).toBe(true);
  });

  it("waitForEmail skips messages that don't match criteria and polls again", async () => {
    const skip = mkMsg({ id: "skip", subject: "newsletter" });
    const match = mkMsg({ id: "match", subject: "Your invitation" });
    const provider = new FakeProvider([[skip], [match]]);
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider,
    });
    const out = await inbox.waitForEmail({
      subjectMatches: /invitation/,
      pollIntervalMs: 1,
      timeoutMs: 1000,
    });
    expect(out.id).toBe("match");
    expect(provider.listCalls.length).toBeGreaterThanOrEqual(2);
  });

  it("waitForEmail throws when no match arrives before timeout", async () => {
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider: new FakeProvider([]),
    });
    await expect(
      inbox.waitForEmail({
        subjectMatches: /never/,
        pollIntervalMs: 5,
        timeoutMs: 30,
      }),
    ).rejects.toThrow(/no matching message/);
  });

  it("waitForCognitoInvite extracts password + url from a Cognito-style email", async () => {
    const cognitoMsg = mkMsg({
      id: "c1",
      subject: "Your temporary password",
      to: "jaetill+gn-1@gmail.com",
      bodyText:
        "Your username is jaetill+gn-1@gmail.com and temporary password is Pa55w0rd!.\n\nSign in at https://auth.jaetill.com/login",
    });
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider: new FakeProvider([[cognitoMsg]]),
    });
    const out = await inbox.waitForCognitoInvite({ timeoutMs: 1000 });
    expect(out.tempPassword).toBe("Pa55w0rd!");
    expect(out.loginUrl).toBe("https://auth.jaetill.com/login");
    expect(out.email).toBe("jaetill+gn-1@gmail.com");
    expect(out.raw.id).toBe("c1");
  });

  it("lastWasInSpam throws before any email is retrieved", () => {
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider: new FakeProvider([]),
    });
    expect(() => inbox.lastWasInSpam()).toThrow(/no email retrieved/);
  });

  it("cleanup marks all messages addressed to this alias as read", async () => {
    const messages = [mkMsg({ id: "a" }), mkMsg({ id: "b" })];
    const provider = new FakeProvider([messages]);
    const inbox = new TestInbox({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1",
      provider,
    });
    await inbox.cleanup();
    expect(provider.markRead).toHaveBeenCalledWith(["a", "b"]);
    expect(provider.listCalls[0]?.to).toBe("jaetill+gn-1@gmail.com");
  });
});
