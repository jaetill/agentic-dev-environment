import type { EmailMessage } from "../providers/provider.js";

export interface EmailParser<T> {
  /** Returns true if this parser believes the message matches its shape. */
  matches(message: EmailMessage): boolean;
  /** Extracts the structured payload. Throws if the message doesn't match. */
  parse(message: EmailMessage): T;
}
