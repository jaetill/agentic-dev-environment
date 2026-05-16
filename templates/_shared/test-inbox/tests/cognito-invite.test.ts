import { describe, it, expect } from "vitest";
import { CognitoInviteParser } from "../src/parsers/cognito-invite.js";
import type { EmailMessage } from "../src/providers/provider.js";

function msg(partial: Partial<EmailMessage>): EmailMessage {
  return {
    id: "id",
    from: "no-reply@example.com",
    to: "jaetill+gn-1@gmail.com",
    subject: "",
    bodyText: "",
    receivedAt: new Date(),
    folder: "inbox",
    labels: [],
    ...partial,
  };
}

const DEFAULT_COGNITO_BODY = `Your username is jaetill+gn-1@gmail.com and temporary password is Pa55w0rd!.\n\nPlease sign in at https://auth.jaetill.com/login?client_id=abc`;

describe("CognitoInviteParser.matches", () => {
  const parser = new CognitoInviteParser();

  it("matches on subject hint 'invitation'", () => {
    expect(
      parser.matches(msg({ subject: "Your invitation to Game Night" })),
    ).toBe(true);
  });

  it("matches on subject hint 'temporary password'", () => {
    expect(parser.matches(msg({ subject: "Your temporary password" }))).toBe(true);
  });

  it("matches when body contains a password phrase", () => {
    expect(parser.matches(msg({ bodyText: DEFAULT_COGNITO_BODY }))).toBe(true);
  });

  it("does not match unrelated emails", () => {
    expect(parser.matches(msg({ subject: "Order confirmation", bodyText: "thanks" }))).toBe(
      false,
    );
  });
});

describe("CognitoInviteParser.parse", () => {
  const parser = new CognitoInviteParser();

  it("extracts email + tempPassword + loginUrl from the default template", () => {
    const out = parser.parse(
      msg({
        subject: "Your temporary password",
        bodyText: DEFAULT_COGNITO_BODY,
      }),
    );
    expect(out.email).toBe("jaetill+gn-1@gmail.com");
    expect(out.tempPassword).toBe("Pa55w0rd!");
    expect(out.loginUrl).toBe("https://auth.jaetill.com/login?client_id=abc");
  });

  it("accepts 'Password: XXX' phrasing", () => {
    const out = parser.parse(
      msg({
        bodyText: "Password: T3mp-pass\n\nLogin at https://abc.amazoncognito.com/login",
      }),
    );
    expect(out.tempPassword).toBe("T3mp-pass");
    expect(out.loginUrl).toBe("https://abc.amazoncognito.com/login");
  });

  it("trims a trailing period from the password capture", () => {
    const out = parser.parse(
      msg({
        bodyText:
          "Your temporary password is Abc12345.\nSign in at https://auth.jaetill.com/login",
      }),
    );
    expect(out.tempPassword).toBe("Abc12345");
  });

  it("throws when no password is present", () => {
    expect(() =>
      parser.parse(msg({ bodyText: "Welcome! Click here: https://auth.jaetill.com/x" })),
    ).toThrow(/no temporary password/);
  });

  it("throws when no recognised login URL is present", () => {
    expect(() =>
      parser.parse(
        msg({ bodyText: "Your temporary password is Pa55w0rd!\nSign in at https://random.example/foo" }),
      ),
    ).toThrow(/no recognised login URL/);
  });
});
