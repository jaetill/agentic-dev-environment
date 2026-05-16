export interface EmailMessage {
  id: string;
  from: string;
  to: string;
  subject: string;
  bodyText: string;
  bodyHtml?: string;
  receivedAt: Date;
  folder: "inbox" | "spam";
  labels: string[];
}

export interface ListCriteria {
  /** Limit to messages addressed to this exact address (full plus-aliased). */
  to?: string;
  /** Limit to messages received after this timestamp. */
  sentAfter?: Date;
  /** Subject filter (server-side hint where supported). */
  subjectContains?: string;
  /** Maximum number of messages to return per folder. */
  limit?: number;
}

export interface InboxProvider {
  /**
   * List messages from inbox + spam folders matching criteria.
   * Order: most recent first. Provider attaches `folder` per message.
   */
  listRecentMessages(criteria: ListCriteria): Promise<EmailMessage[]>;

  /**
   * Mark a list of message ids as read in their respective folders.
   * Provider-specific (Gmail removes UNREAD label, etc.).
   */
  markRead(messageIds: string[]): Promise<void>;
}
