/**
 * User-feedback handling per Standard 11.
 *
 * Validates input, creates a GitHub Issue with structured labels, returns a
 * feedback ID + issue URL. Rate limiting + honeypot check happen in the route
 * handler before this function is called.
 *
 * Tested independently of the route handler in tests/unit/feedback.test.ts.
 */

import { z } from 'zod';

import { logger, redactPII } from './logger';

export const FeedbackSchema = z.object({
  type: z.enum(['bug', 'feature', 'other']),
  description: z.string().min(10).max(2000),
  email: z.string().email().optional(),
  page_url: z.string().url().optional(),
  user_agent: z.string().optional(),
  // Honeypot — bots fill all fields. Real submissions have this empty.
  website: z.string().max(0).optional(),
});

export type FeedbackInput = z.infer<typeof FeedbackSchema>;

export interface FeedbackResult {
  id: string;
  status: 'received';
  issue_url?: string;
}

interface CreateIssueOptions {
  owner: string;
  repo: string;
  token: string;
}

/**
 * Create a GitHub Issue for the feedback. Per Standard 11 §2 label scheme.
 */
async function createGitHubIssue(
  input: FeedbackInput,
  options: CreateIssueOptions,
): Promise<{ url: string; number: number }> {
  const { type, description, email, page_url, user_agent } = input;

  const titlePrefix = `[${type}]`;
  const titleBody = description.length > 60 ? `${description.slice(0, 60)}...` : description;
  const title = `${titlePrefix} ${titleBody}`;

  const bodyParts = [
    `## Description`,
    description,
    '',
    '## Context',
    page_url !== undefined ? `- Page URL: ${page_url}` : null,
    user_agent !== undefined ? `- User agent: \`${user_agent}\`` : null,
    email !== undefined ? `- Reporter email: ${email} (will receive resolution updates)` : null,
    '',
    '## Triage',
    'This issue will be classified by the `triage-bot` agent on its next scheduled scan.',
  ]
    .filter((line) => line !== null)
    .join('\n');

  const labels = [`feedback:user-submitted`, `type:${type}`];

  const response = await fetch(
    `https://api.github.com/repos/${options.owner}/${options.repo}/issues`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${options.token}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ title, body: bodyParts, labels }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `GitHub Issue creation failed: ${response.status} ${await response.text()}`,
    );
  }

  const issue = (await response.json()) as { html_url: string; number: number };
  return { url: issue.html_url, number: issue.number };
}

/**
 * Process a feedback submission. The route handler should call this after
 * rate-limit + honeypot checks pass.
 */
export async function processFeedback(
  rawInput: unknown,
  options: CreateIssueOptions,
): Promise<FeedbackResult> {
  const input = FeedbackSchema.parse(rawInput);

  // Honeypot check — bots fill the `website` field
  if (input.website !== undefined && input.website !== '') {
    logger.warn(redactPII({ event: 'feedback.honeypot_triggered', input }));
    // Return success to bots (don't tip them off) but don't actually file
    return { id: `FB-DROPPED-${Date.now()}`, status: 'received' };
  }

  const issue = await createGitHubIssue(input, options);
  const id = `FB-${new Date().getFullYear()}-${String(issue.number).padStart(6, '0')}`;

  logger.info(
    redactPII({
      event: 'feedback.received',
      id,
      type: input.type,
      issue_number: issue.number,
      has_email: input.email !== undefined,
    }),
  );

  return { id, status: 'received', issue_url: issue.url };
}
