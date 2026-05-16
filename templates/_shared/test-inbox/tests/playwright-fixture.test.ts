import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { inboxFixture } from "../src/inbox-fixture-core.js";
import type { TestInbox } from "../src/inbox.js";
import type { InboxProvider } from "../src/providers/provider.js";

const fakeProvider: InboxProvider = {
  listRecentMessages: vi.fn(async () => []),
  markRead: vi.fn(async () => {}),
};

describe("inboxFixture lifecycle (Playwright-free core)", () => {
  const savedEnv = { ...process.env };

  beforeEach(() => {
    process.env["GMAIL_TESTER_EMAIL"] = "jaetill@gmail.com";
  });

  afterEach(() => {
    process.env = { ...savedEnv };
    vi.clearAllMocks();
  });

  it("creates an inbox keyed to project/runId/title, then calls cleanup on teardown", async () => {
    let observed: TestInbox | null = null;
    await inboxFixture(
      {
        inboxProject: "gn",
        inboxRunId: "run-42",
        inboxOverrides: { provider: fakeProvider },
        title: "admin invite delivers a temp password",
      },
      async (inbox) => {
        observed = inbox;
      },
    );
    expect(observed).not.toBeNull();
    expect(observed!.address).toBe(
      "jaetill+gn-run-42-admin-invite-delivers-a-temp-password@gmail.com",
    );
    expect(fakeProvider.listRecentMessages).toHaveBeenCalledWith({
      to: observed!.address,
    });
    expect(fakeProvider.markRead).toHaveBeenCalled();
  });

  it("runs cleanup even when the test body throws", async () => {
    await expect(
      inboxFixture(
        {
          inboxProject: "gn",
          inboxRunId: "run-1",
          inboxOverrides: { provider: fakeProvider },
          title: "fails",
        },
        async () => {
          throw new Error("test body exploded");
        },
      ),
    ).rejects.toThrow(/test body exploded/);
    expect(fakeProvider.markRead).toHaveBeenCalled();
  });

  it("swallows cleanup errors and does not mask test success", async () => {
    const explodingProvider: InboxProvider = {
      listRecentMessages: vi.fn(async () => []),
      markRead: vi.fn(async () => {
        throw new Error("gmail down");
      }),
    };
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});

    await inboxFixture(
      {
        inboxProject: "gn",
        inboxRunId: "run-1",
        inboxOverrides: { provider: explodingProvider },
        title: "happy path",
      },
      async () => {},
    );

    expect(warn).toHaveBeenCalledWith(expect.stringMatching(/cleanup failed.*gmail down/));
    warn.mockRestore();
  });
});
