# Runbook: Spam cleanup (user-feedback endpoint)

## When to use this

The `/api/feedback` endpoint is producing low-quality / abusive GitHub Issues despite the rate limiting + honeypot. Per Standard 11 §4.

## Prerequisites

- Repo write access
- (Optional) Cloudflare Turnstile account if not yet enabled

## Steps

1. **Bulk-close existing spam.**
   - Filter GitHub Issues by `feedback:user-submitted` + look at recent submissions.
   - Bulk-close as `closed:invalid` with a brief reason (e.g., "automated spam — IP blocked").

2. **Identify the abuse pattern.**
   - Are submissions all from one IP? → IP-block at Vercel edge or via the rate-limit allowlist.
   - Are submissions filling honeypot? → Verify honeypot is actually being checked (look at recent code).
   - Are submissions humanly-typed but abusive? → Enable Turnstile.

3. **Tighten controls** (escalate per scenario):
   - Lower the rate limit (e.g., from 10/hour to 3/hour) — set `RATE_LIMIT_PER_HOUR` env var.
   - Enable Cloudflare Turnstile by setting `NEXT_PUBLIC_TURNSTILE_SITE_KEY` + `TURNSTILE_SECRET_KEY`.
   - Add IP allow/blocklist in Vercel project settings.

4. **Rotate honeypot field name** if bots have learned to skip it. Edit the form's hidden field name.

5. **File a postmortem** if abuse was significant.

## Verification

- New spam submissions don't reach GitHub Issues (or are caught early)
- Real user feedback continues to flow

## Escalation

Persistent targeted attacks may warrant taking `/api/feedback` offline temporarily and forwarding to GitHub Discussions instead.
