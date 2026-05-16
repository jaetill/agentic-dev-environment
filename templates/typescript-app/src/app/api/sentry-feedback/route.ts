/**
 * Sentry User Feedback webhook receiver per Standard 11 §1 Tier 1.
 *
 * Sentry forwards user-feedback events to this endpoint. We create a paired
 * GitHub Issue with `feedback:from-sentry` label so the triage-bot agent can
 * dedupe and classify alongside other feedback.
 *
 * Verify the Sentry signature header before processing.
 */

import { createHmac, timingSafeEqual } from 'node:crypto';

import { NextResponse } from 'next/server';

import { logger } from '@/lib/logger';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface SentryFeedbackPayload {
  data?: {
    feedback?: {
      contact_email?: string;
      message?: string;
      issue_url?: string;
      url?: string;
    };
  };
}

function verifySentrySignature(rawBody: string, signature: string | null, secret: string): boolean {
  if (signature === null || signature === '') return false;
  const expected = createHmac('sha256', secret).update(rawBody, 'utf8').digest('hex');
  const sigBuf = Buffer.from(signature);
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length) return false;
  return timingSafeEqual(sigBuf, expBuf);
}

export async function POST(request: Request): Promise<NextResponse> {
  const secret = process.env.SENTRY_WEBHOOK_SECRET;
  if (secret === undefined) {
    logger.error({ event: 'sentry-feedback.secret_missing' });
    return NextResponse.json({ error: 'service_unavailable' }, { status: 503 });
  }

  const rawBody = await request.text();
  const signature = request.headers.get('sentry-hook-signature');

  if (!verifySentrySignature(rawBody, signature, secret)) {
    logger.warn({ event: 'sentry-feedback.invalid_signature' });
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  let payload: SentryFeedbackPayload;
  try {
    payload = JSON.parse(rawBody) as SentryFeedbackPayload;
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400 });
  }

  const feedback = payload.data?.feedback;
  if (feedback === undefined || feedback.message === undefined) {
    return NextResponse.json({ error: 'no_feedback_in_payload' }, { status: 400 });
  }

  // Create a GitHub Issue with feedback:from-sentry label
  const owner = process.env.GITHUB_REPO_OWNER;
  const repo = process.env.GITHUB_REPO_NAME;
  const token = process.env.GITHUB_TOKEN;

  if (owner === undefined || repo === undefined || token === undefined) {
    logger.error({ event: 'sentry-feedback.config_missing' });
    return NextResponse.json({ error: 'service_unavailable' }, { status: 503 });
  }

  const title = `[bug] User feedback from Sentry: ${feedback.message.slice(0, 60)}${feedback.message.length > 60 ? '...' : ''}`;
  const body = [
    '## Description (from Sentry User Feedback)',
    feedback.message,
    '',
    '## Context',
    feedback.url !== undefined ? `- Page URL: ${feedback.url}` : null,
    feedback.issue_url !== undefined ? `- Sentry issue: ${feedback.issue_url}` : null,
    feedback.contact_email !== undefined ? `- Reporter email: ${feedback.contact_email}` : null,
    '',
    '## Triage',
    'This issue was auto-created by the Sentry feedback webhook. The `triage-bot` agent will classify on next scan.',
  ]
    .filter((line) => line !== null)
    .join('\n');

  const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/issues`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      title,
      body,
      labels: ['feedback:from-sentry', 'type:bug'],
    }),
  });

  if (!response.ok) {
    logger.error({
      event: 'sentry-feedback.github_issue_failed',
      status: response.status,
    });
    return NextResponse.json({ error: 'github_issue_creation_failed' }, { status: 502 });
  }

  return NextResponse.json({ status: 'received' }, { status: 201 });
}
