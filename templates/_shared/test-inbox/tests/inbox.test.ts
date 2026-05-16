import { describe, it, expect } from "vitest";
import * as pkg from "../src/index.js";

describe("@platform/test-inbox — package surface", () => {
  it("exports the documented public symbols", () => {
    // Phase 1 smoke test: just verifies the module loads and the symbol
    // table matches the docs. Real behavioural tests land in Phases 2-4.
    expect(pkg.TestInbox).toBeTypeOf("function");
    expect(pkg.GmailInboxProvider).toBeTypeOf("function");
    expect(pkg.CognitoInviteParser).toBeTypeOf("function");
    expect(pkg.buildAliasAddress).toBeTypeOf("function");
    expect(pkg.parseAliasAddress).toBeTypeOf("function");
    expect(pkg.cleanupCognitoTestUsers).toBeTypeOf("function");
    expect(pkg.gmailOAuthFromEnv).toBeTypeOf("function");
    expect(pkg.inboxFixture).toBeTypeOf("function");
  });
});
