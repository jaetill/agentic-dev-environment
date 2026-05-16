import type { EmailMessage } from "../providers/provider.js";
import type { EmailParser } from "./parser.js";

export interface CognitoInvitePayload {
  email: string;
  tempPassword: string;
  loginUrl: string;
}

/**
 * Default Cognito-Hosted-UI invite email body looks like:
 *
 *   Your username is {username} and temporary password is {####}.
 *
 * Most consumers override the template, so this parser is tolerant: it
 * looks for the password pattern AND a hosted-UI URL anywhere in the body.
 *
 * The temp password is matched with a non-greedy character class up to the
 * first whitespace, period, or angle bracket — Cognito-generated passwords
 * never contain whitespace and are typically printable ASCII.
 */

// Matches "temporary password is XXXX" or "Password: XXXX" / "Password:XXXX".
const PASSWORD_PATTERNS = [
  /(?:temporary\s+password|temp\s+password|password)\s*(?:is\s+|:\s*)([^\s.<>"']+)/i,
];

// URLs we recognise as login destinations.
const LOGIN_URL_HOSTS = ["amazoncognito.com", "jaetill.com"];

const LOGIN_URL_PATTERN = /https?:\/\/[^\s<>"']+/g;

const COGNITO_SUBJECT_HINTS = ["invitation", "invite", "temporary password"];

export class CognitoInviteParser implements EmailParser<CognitoInvitePayload> {
  matches(message: EmailMessage): boolean {
    const subject = message.subject.toLowerCase();
    if (COGNITO_SUBJECT_HINTS.some((hint) => subject.includes(hint))) return true;
    return this.findPassword(message.bodyText) !== null;
  }

  parse(message: EmailMessage): CognitoInvitePayload {
    const tempPassword = this.findPassword(message.bodyText);
    if (!tempPassword) {
      throw new Error(
        `CognitoInviteParser: no temporary password found in body of message ${message.id}`,
      );
    }
    const loginUrl = this.findLoginUrl(message.bodyText);
    if (!loginUrl) {
      throw new Error(
        `CognitoInviteParser: no recognised login URL in body of message ${message.id}`,
      );
    }
    return {
      email: message.to,
      tempPassword,
      loginUrl,
    };
  }

  private findPassword(body: string): string | null {
    for (const pattern of PASSWORD_PATTERNS) {
      const m = body.match(pattern);
      if (m?.[1]) return m[1];
    }
    return null;
  }

  private findLoginUrl(body: string): string | null {
    const urls = body.match(LOGIN_URL_PATTERN) ?? [];
    for (const url of urls) {
      if (LOGIN_URL_HOSTS.some((host) => url.includes(host))) return url;
    }
    return null;
  }
}
