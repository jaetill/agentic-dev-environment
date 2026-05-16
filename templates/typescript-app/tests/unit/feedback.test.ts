/**
 * Unit tests for the feedback handler (Standard 11 §1 Tier 2).
 *
 * Tests are independent of the route handler — we exercise processFeedback
 * directly with a mocked fetch.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { processFeedback, FeedbackSchema } from '@/lib/feedback';

const FAKE_ISSUE_RESPONSE = {
  html_url: 'https://github.com/example/proj/issues/42',
  number: 42,
};

describe('FeedbackSchema validation', () => {
  it('accepts a valid bug submission', () => {
    const result = FeedbackSchema.safeParse({
      type: 'bug',
      description: 'The submit button is greyed out and clicking does nothing.',
    });
    expect(result.success).toBe(true);
  });

  it('rejects descriptions shorter than 10 characters', () => {
    const result = FeedbackSchema.safeParse({ type: 'bug', description: 'too short' });
    expect(result.success).toBe(false);
  });

  it('rejects descriptions longer than 2000 characters', () => {
    const result = FeedbackSchema.safeParse({
      type: 'bug',
      description: 'a'.repeat(2001),
    });
    expect(result.success).toBe(false);
  });

  it('rejects invalid type values', () => {
    const result = FeedbackSchema.safeParse({
      type: 'rant',
      description: 'I hate everything here.',
    });
    expect(result.success).toBe(false);
  });

  it('accepts optional email when valid', () => {
    const result = FeedbackSchema.safeParse({
      type: 'feature',
      description: 'Please add dark mode toggle to settings.',
      email: 'user@example.com',
    });
    expect(result.success).toBe(true);
  });

  it('rejects malformed email', () => {
    const result = FeedbackSchema.safeParse({
      type: 'feature',
      description: 'Please add dark mode toggle to settings.',
      email: 'not-an-email',
    });
    expect(result.success).toBe(false);
  });
});

describe('processFeedback', () => {
  const fakeOptions = { owner: 'example', repo: 'proj', token: 'fake-token' };

  beforeEach(() => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => FAKE_ISSUE_RESPONSE,
    } as Response);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('creates a GitHub issue and returns a feedback ID', async () => {
    const result = await processFeedback(
      {
        type: 'bug',
        description: 'Page crashes when I click the submit button.',
      },
      fakeOptions,
    );

    expect(result.status).toBe('received');
    expect(result.id).toMatch(/^FB-\d{4}-000042$/);
    expect(result.issue_url).toBe(FAKE_ISSUE_RESPONSE.html_url);
  });

  it('drops honeypot-triggered submissions silently', async () => {
    const result = await processFeedback(
      {
        type: 'feature',
        description: 'Please add lots of links to my fake site.',
        website: 'http://spam-bot-was-here.example.com',
      },
      fakeOptions,
    );

    expect(result.status).toBe('received');
    expect(result.id).toMatch(/^FB-DROPPED-\d+$/);
    // No GitHub call should have happened
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('throws when GitHub API rejects the request', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 401,
      text: async () => '{"message":"Bad credentials"}',
    } as Response);

    await expect(
      processFeedback(
        { type: 'bug', description: 'Something is broken in the app.' },
        fakeOptions,
      ),
    ).rejects.toThrow(/GitHub Issue creation failed/);
  });

  it('labels the issue with feedback:user-submitted and type:*', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => FAKE_ISSUE_RESPONSE,
    } as Response);
    global.fetch = fetchMock;

    await processFeedback(
      { type: 'feature', description: 'Add CSV export to the dashboard.' },
      fakeOptions,
    );

    const call = fetchMock.mock.calls[0];
    expect(call).toBeDefined();
    const body = JSON.parse((call?.[1] as RequestInit).body as string) as { labels: string[] };
    expect(body.labels).toContain('feedback:user-submitted');
    expect(body.labels).toContain('type:feature');
  });
});
