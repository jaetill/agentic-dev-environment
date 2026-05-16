import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  AdminDeleteUserCommand,
  DescribeUserPoolCommand,
  ListUsersCommand,
  type CognitoIdentityProviderClient,
  type UserType,
} from "@aws-sdk/client-cognito-identity-provider";

import { cleanupCognitoTestUsers } from "../src/cleanup.js";

interface SendCall {
  type: "describe" | "list" | "delete";
  input: unknown;
}

function makeClient(opts: {
  poolName: string;
  pages?: Array<{ Users: UserType[]; PaginationToken?: string }>;
}): { client: CognitoIdentityProviderClient; calls: SendCall[] } {
  const pages = opts.pages ?? [{ Users: [] }];
  let pageIdx = 0;
  const calls: SendCall[] = [];

  const send = vi.fn(async (command: unknown) => {
    if (command instanceof DescribeUserPoolCommand) {
      calls.push({ type: "describe", input: command.input });
      return { UserPool: { Name: opts.poolName } };
    }
    if (command instanceof ListUsersCommand) {
      calls.push({ type: "list", input: command.input });
      const page = pages[pageIdx] ?? { Users: [] };
      pageIdx += 1;
      return page;
    }
    if (command instanceof AdminDeleteUserCommand) {
      calls.push({ type: "delete", input: command.input });
      return {};
    }
    throw new Error(`Unexpected command: ${command?.constructor?.name}`);
  });

  return {
    client: { send } as unknown as CognitoIdentityProviderClient,
    calls,
  };
}

function user(email: string, sub: string, username = email): UserType {
  return {
    Username: username,
    Attributes: [
      { Name: "email", Value: email },
      { Name: "sub", Value: sub },
    ],
  };
}

const ENV_OVERRIDE = "PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP";

describe("cleanupCognitoTestUsers", () => {
  const savedEnv = { ...process.env };

  beforeEach(() => {
    delete process.env[ENV_OVERRIDE];
  });

  afterEach(() => {
    process.env = { ...savedEnv };
  });

  it("deletes only users whose email starts with the alias prefix", async () => {
    const { client, calls } = makeClient({
      poolName: "my-test-pool",
      pages: [
        {
          Users: [
            user("jaetill+gn-1@gmail.com", "sub-1"),
            // server-side filter should never return this, but defense in depth:
            user("real-user@somewhere.com", "sub-evil"),
            user("jaetill+gn-2@gmail.com", "sub-2"),
          ],
        },
      ],
    });

    const result = await cleanupCognitoTestUsers({
      userPoolId: "us-east-2_test",
      region: "us-east-2",
      emailMatchesAlias: "jaetill+",
      client,
    });

    expect(result.deleted).toBe(2);
    expect(result.skipped).toBe(1);
    expect(result.deletedSubs.sort()).toEqual(["sub-1", "sub-2"]);
    const deletes = calls.filter((c) => c.type === "delete");
    expect(deletes.map((c) => (c.input as { Username: string }).Username)).toEqual([
      "jaetill+gn-1@gmail.com",
      "jaetill+gn-2@gmail.com",
    ]);
  });

  it("uses server-side `email ^=` filter", async () => {
    const { client, calls } = makeClient({ poolName: "test-pool" });
    await cleanupCognitoTestUsers({
      userPoolId: "us-east-2_test",
      region: "us-east-2",
      emailMatchesAlias: "jaetill+",
      client,
    });
    const list = calls.find((c) => c.type === "list");
    expect((list?.input as { Filter: string }).Filter).toBe('email ^= "jaetill+"');
  });

  it("paginates through multiple pages of users", async () => {
    const { client, calls } = makeClient({
      poolName: "test-pool",
      pages: [
        {
          Users: [user("jaetill+a@gmail.com", "sub-a")],
          PaginationToken: "page2",
        },
        { Users: [user("jaetill+b@gmail.com", "sub-b")] },
      ],
    });
    const result = await cleanupCognitoTestUsers({
      userPoolId: "us-east-2_test",
      region: "us-east-2",
      emailMatchesAlias: "jaetill+",
      client,
    });
    expect(result.deleted).toBe(2);
    const listCalls = calls.filter((c) => c.type === "list");
    expect(listCalls).toHaveLength(2);
    expect((listCalls[1]?.input as { PaginationToken?: string }).PaginationToken).toBe(
      "page2",
    );
  });

  it("refuses to run against a non-test pool without the env override", async () => {
    const { client } = makeClient({ poolName: "production-pool" });
    await expect(
      cleanupCognitoTestUsers({
        userPoolId: "us-east-2_prod",
        region: "us-east-2",
        emailMatchesAlias: "jaetill+",
        client,
      }),
    ).rejects.toThrow(/refusing to run.*production-pool/);
  });

  it("allows non-test pool when PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true", async () => {
    process.env[ENV_OVERRIDE] = "true";
    const { client } = makeClient({
      poolName: "production-pool",
      pages: [{ Users: [user("jaetill+gn-1@gmail.com", "sub-1")] }],
    });
    const result = await cleanupCognitoTestUsers({
      userPoolId: "us-east-2_prod",
      region: "us-east-2",
      emailMatchesAlias: "jaetill+",
      client,
    });
    expect(result.deleted).toBe(1);
  });

  it("refuses when poolNameContains doesn't match", async () => {
    process.env[ENV_OVERRIDE] = "true";
    const { client } = makeClient({ poolName: "prod-pool" });
    await expect(
      cleanupCognitoTestUsers({
        userPoolId: "us-east-2_prod",
        region: "us-east-2",
        emailMatchesAlias: "jaetill+",
        poolNameContains: "staging",
        client,
      }),
    ).rejects.toThrow(/does not contain "staging"/);
  });

  it("throws when emailMatchesAlias is empty", async () => {
    await expect(
      cleanupCognitoTestUsers({
        userPoolId: "us-east-2_test",
        region: "us-east-2",
        emailMatchesAlias: "",
      }),
    ).rejects.toThrow(/emailMatchesAlias is required/);
  });
});
