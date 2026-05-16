import {
  AdminDeleteUserCommand,
  CognitoIdentityProviderClient,
  DescribeUserPoolCommand,
  ListUsersCommand,
  type ListUsersCommandOutput,
  type UserType,
} from "@aws-sdk/client-cognito-identity-provider";

export interface CognitoCleanupOptions {
  /** Cognito user pool ID, e.g. "us-east-2_XXXXXXXXX". */
  userPoolId: string;
  /** AWS region for the pool. */
  region: string;
  /**
   * Delete only users whose primary email STARTS WITH this string.
   * Must be the tester alias prefix (e.g. "jaetill+") so production users
   * can never match. The startsWith check is load-bearing — do not weaken
   * it to contains/regex without revisiting the safety argument.
   */
  emailMatchesAlias: string;
  /**
   * Optional belt-and-suspenders guard: refuse to run unless the pool's
   * Name contains this substring. Leave undefined to skip the name check
   * (rely on `emailMatchesAlias` alone).
   */
  poolNameContains?: string;
  /** Injected client for tests. */
  client?: CognitoIdentityProviderClient;
}

export interface CognitoCleanupResult {
  deleted: number;
  /** Users matched the alias but were skipped because of safety guards. */
  skipped: number;
  /** Sub-IDs of users that were deleted, for audit. */
  deletedSubs: string[];
}

const PROD_CLEANUP_OVERRIDE_VAR = "PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP";

/**
 * Delete Cognito users whose email matches the test alias prefix.
 *
 * Safety guards (per ADR-0014, layered):
 *   1. `emailMatchesAlias` is required, must be non-empty.
 *   2. Server-side filter uses `^=` (startsWith) so the pool's filter index
 *      narrows results before we touch anything.
 *   3. Client-side: each returned user's email must START WITH the alias.
 *      A user with a "+" anywhere else in the local-part will not match.
 *   4. Unless `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true`, the function
 *      refuses to run against pools whose Name does not contain "test".
 *      Override exists for the documented case where the only Cognito
 *      pool available is production (jaetill setup) and the alias guard
 *      is trusted.
 *   5. If `poolNameContains` is set, the pool Name must also match it
 *      (independent of the "test" check above).
 */
export async function cleanupCognitoTestUsers(
  opts: CognitoCleanupOptions,
): Promise<CognitoCleanupResult> {
  if (!opts.emailMatchesAlias) {
    throw new Error("cleanupCognitoTestUsers: emailMatchesAlias is required");
  }

  const client =
    opts.client ?? new CognitoIdentityProviderClient({ region: opts.region });

  // Guard 4 + 5: pool-name checks.
  const allowProd = process.env[PROD_CLEANUP_OVERRIDE_VAR] === "true";
  const describe = await client.send(
    new DescribeUserPoolCommand({ UserPoolId: opts.userPoolId }),
  );
  const poolName = describe.UserPool?.Name ?? "";

  if (opts.poolNameContains && !poolName.includes(opts.poolNameContains)) {
    throw new Error(
      `cleanupCognitoTestUsers: pool "${poolName}" does not contain "${opts.poolNameContains}"`,
    );
  }
  if (!poolName.toLowerCase().includes("test") && !allowProd) {
    throw new Error(
      `cleanupCognitoTestUsers: refusing to run against pool "${poolName}" (name does not contain "test"). ` +
        `Set ${PROD_CLEANUP_OVERRIDE_VAR}=true to override; the alias-prefix guard is the load-bearing safety.`,
    );
  }

  // List + filter.
  let deleted = 0;
  let skipped = 0;
  const deletedSubs: string[] = [];
  let paginationToken: string | undefined;

  do {
    const listInput: ConstructorParameters<typeof ListUsersCommand>[0] = {
      UserPoolId: opts.userPoolId,
      Filter: `email ^= "${opts.emailMatchesAlias}"`,
      Limit: 60,
    };
    if (paginationToken !== undefined) listInput.PaginationToken = paginationToken;
    const list: ListUsersCommandOutput = await client.send(new ListUsersCommand(listInput));

    for (const user of list.Users ?? []) {
      const email = readEmailAttr(user);
      if (!email || !email.startsWith(opts.emailMatchesAlias)) {
        skipped += 1;
        continue;
      }
      if (!user.Username) {
        skipped += 1;
        continue;
      }
      await client.send(
        new AdminDeleteUserCommand({
          UserPoolId: opts.userPoolId,
          Username: user.Username,
        }),
      );
      deleted += 1;
      const sub = readAttr(user, "sub");
      if (sub) deletedSubs.push(sub);
    }
    paginationToken = list.PaginationToken;
  } while (paginationToken);

  return { deleted, skipped, deletedSubs };
}

function readAttr(user: UserType, name: string): string | undefined {
  return user.Attributes?.find((a) => a.Name === name)?.Value;
}

function readEmailAttr(user: UserType): string | undefined {
  return readAttr(user, "email");
}
