import { describe, it, expect } from "vitest";
import { buildAliasAddress, parseAliasAddress } from "../src/address.js";

describe("buildAliasAddress", () => {
  it("composes a basic project/runId alias", () => {
    expect(
      buildAliasAddress({
        baseEmail: "jaetill@gmail.com",
        project: "gn",
        runId: "1234",
      }),
    ).toBe("jaetill+gn-1234@gmail.com");
  });

  it("appends testName when provided", () => {
    expect(
      buildAliasAddress({
        baseEmail: "jaetill@gmail.com",
        project: "gn",
        runId: "1234",
        testName: "admin-invite",
      }),
    ).toBe("jaetill+gn-1234-admin-invite@gmail.com");
  });

  it("sanitizes unsafe characters to hyphens", () => {
    expect(
      buildAliasAddress({
        baseEmail: "jaetill@gmail.com",
        project: "game.night/pwa",
        runId: "run id #5",
        testName: "user@admin",
      }),
    ).toBe("jaetill+game-night-pwa-run-id-5-user-admin@gmail.com");
  });

  it("rejects a baseEmail without exactly one @", () => {
    expect(() =>
      buildAliasAddress({
        baseEmail: "no-at-sign",
        project: "p",
        runId: "r",
      }),
    ).toThrow(/exactly one @/);
  });

  it("rejects a baseEmail that already has a + alias", () => {
    expect(() =>
      buildAliasAddress({
        baseEmail: "jaetill+already@gmail.com",
        project: "p",
        runId: "r",
      }),
    ).toThrow(/already contain a \+ alias/);
  });

  it("rejects when sanitization eliminates project or runId", () => {
    expect(() =>
      buildAliasAddress({
        baseEmail: "jaetill@gmail.com",
        project: "!!!",
        runId: "1",
      }),
    ).toThrow(/non-empty sanitized segments/);
  });
});

describe("parseAliasAddress", () => {
  it("inverts buildAliasAddress for a basic alias", () => {
    const parts = parseAliasAddress("jaetill+gn-1234@gmail.com");
    expect(parts).toEqual({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1234",
    });
  });

  it("recovers testName segments containing hyphens", () => {
    const parts = parseAliasAddress("jaetill+gn-1234-admin-invite-redirect@gmail.com");
    expect(parts).toEqual({
      baseEmail: "jaetill@gmail.com",
      project: "gn",
      runId: "1234",
      testName: "admin-invite-redirect",
    });
  });

  it("returns null for addresses with no + alias", () => {
    expect(parseAliasAddress("jaetill@gmail.com")).toBeNull();
  });

  it("returns null when alias has fewer than 2 segments", () => {
    expect(parseAliasAddress("jaetill+gn@gmail.com")).toBeNull();
  });

  it("returns null for malformed input", () => {
    expect(parseAliasAddress("not-an-email")).toBeNull();
  });
});
