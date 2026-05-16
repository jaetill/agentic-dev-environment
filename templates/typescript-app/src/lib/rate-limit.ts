/**
 * Per-IP rate limiting for the user-feedback endpoint per Standard 11 §4.
 *
 * Default 10 submissions per hour per IP. In-memory implementation suitable
 * for a single-instance Vercel Function. For multi-region or multi-instance
 * deployments, swap for Upstash Redis / Vercel KV / DynamoDB.
 */

interface RateLimitState {
  count: number;
  windowStart: number;
}

const WINDOW_MS = 60 * 60 * 1000; // 1 hour
const DEFAULT_LIMIT = 10;

// In-memory store. Per-instance only; replace with Redis/KV for production scale.
const store = new Map<string, RateLimitState>();

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfterSeconds: number;
}

export function rateLimit(
  identifier: string,
  limit: number = DEFAULT_LIMIT,
): RateLimitResult {
  const now = Date.now();
  const existing = store.get(identifier);

  if (existing === undefined || now - existing.windowStart >= WINDOW_MS) {
    // Window expired or first request — reset
    store.set(identifier, { count: 1, windowStart: now });
    return { allowed: true, remaining: limit - 1, retryAfterSeconds: 0 };
  }

  if (existing.count >= limit) {
    const retryAfterMs = WINDOW_MS - (now - existing.windowStart);
    return {
      allowed: false,
      remaining: 0,
      retryAfterSeconds: Math.ceil(retryAfterMs / 1000),
    };
  }

  existing.count += 1;
  store.set(identifier, existing);
  return { allowed: true, remaining: limit - existing.count, retryAfterSeconds: 0 };
}

/**
 * Helper: extract client IP from a request, with sensible fallbacks for Vercel +
 * standard proxy headers.
 */
export function getClientIP(request: Request): string {
  const forwardedFor = request.headers.get('x-forwarded-for');
  if (forwardedFor !== null && forwardedFor !== '') {
    // First IP in the chain is the originating client
    const first = forwardedFor.split(',')[0]?.trim();
    if (first !== undefined && first !== '') return first;
  }
  const realIP = request.headers.get('x-real-ip');
  if (realIP !== null && realIP !== '') return realIP;
  return 'unknown';
}
