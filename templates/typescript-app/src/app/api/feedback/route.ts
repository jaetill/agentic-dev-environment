/**
 * User-feedback endpoint per Standard 11.
 *
 * Wires:
 *   - Per-IP rate limiting (default 10/hour)
 *   - Honeypot field check (handled inside processFeedback)
 *   - Zod validation
 *   - GitHub Issue creation with `feedback:user-submitted` + `type:*` labels
 *   - Optional auto-reply email (TODO: wire SES)
 */

import { NextResponse } from 'next/server';

import { processFeedback } from '@/lib/feedback';
import { logger } from '@/lib/logger';
import { getClientIP, rateLimit } from '@/lib/rate-limit';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const RATE_LIMIT_PER_HOUR = 10;

export async function POST(request: Request): Promise<NextResponse> {
  const ip = getClientIP(request);
  const rl = rateLimit(`feedback:${ip}`, RATE_LIMIT_PER_HOUR);

  if (!rl.allowed) {
    return NextResponse.json(
      { error: 'rate_limited', retry_after_seconds: rl.retryAfterSeconds },
      { status: 429, headers: { 'Retry-After': String(rl.retryAfterSeconds) } },
    );
  }

  let rawInput: unknown;
  try {
    rawInput = await request.json();
  } catch {
    return NextResponse.json({ error: 'invalid_json' }, { status: 400 });
  }

  // Auto-capture user_agent if not provided
  if (
    typeof rawInput === 'object' &&
    rawInput !== null &&
    !('user_agent' in rawInput)
  ) {
    (rawInput as Record<string, unknown>).user_agent = request.headers.get('user-agent') ?? undefined;
  }

  const owner = process.env.GITHUB_REPO_OWNER;
  const repo = process.env.GITHUB_REPO_NAME;
  const token = process.env.GITHUB_TOKEN;

  if (owner === undefined || repo === undefined || token === undefined) {
    logger.error({ event: 'feedback.config_missing' });
    return NextResponse.json({ error: 'service_unavailable' }, { status: 503 });
  }

  try {
    const result = await processFeedback(rawInput, { owner, repo, token });
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof Error && error.name === 'ZodError') {
      return NextResponse.json(
        { error: 'validation_error', details: error.message },
        { status: 400 },
      );
    }
    logger.error({ event: 'feedback.error', error: error instanceof Error ? error.message : String(error) });
    return NextResponse.json({ error: 'internal_error' }, { status: 500 });
  }
}
