---
name: postmark-email
description: Use when sending transactional email from a project — invites, magic links, password resets, notifications. Covers DKIM/SPF/DMARC setup, MessageAction=SUPPRESS pattern with Cognito, HTML entity escaping in passwords, and webhook bounces.
---

# Postmark transactional email

## When to consult

- Sending transactional email from any app.
- Wiring up a magic-link or invite flow.
- Investigating delivery failures (bounces, spam folder, signature errors).

## Gotchas

### DKIM/SPF/DMARC must all be green before sending

**Symptom:** First production email lands in spam.

**Root cause:** New sending domain has no reputation. SPF or DKIM not configured → email fails strict providers' filters.

**Fix:**
1. Verify the domain in Postmark (adds DNS records).
2. Set SPF: `v=spf1 include:spf.mtasv.net ~all` (or with your other senders).
3. Set DKIM: TXT record Postmark provides.
4. Set DMARC: start with `v=DMARC1; p=none; rua=mailto:dmarc@yourdomain` to observe; tighten to `p=quarantine` then `p=reject` over weeks.

All three must show "Verified" in Postmark dashboard before sending production volume.

### `MessageAction=SUPPRESS` + Postmark for Cognito invites

**Pattern:** Cognito's built-in invite email is ugly and not customizable. Per [[cognito-pool-quirks]], pass `MessageAction='SUPPRESS'` to `AdminCreateUser` and send your own invite via Postmark.

```python
import boto3
from postmark import PMMail

temp_password = generate_strong_temp_password()
cognito.admin_create_user(
    UserPoolId=POOL_ID, Username=email,
    UserAttributes=[{"Name": "email", "Value": email}],
    MessageAction="SUPPRESS",
    TemporaryPassword=temp_password,
)
PMMail(api_key=POSTMARK_TOKEN,
       sender="invites@yourdomain.com", to=email,
       subject="Your invite",
       html_body=render_template("invite.html", password=html.escape(temp_password))
).send()
```

### HTML entity escaping in passwords

**Symptom:** User receives invite with password like `P@ssw0rd&amp;!` and copy-pastes literally. Login fails.

**Root cause:** Passwords containing `&`, `<`, `>`, `"` get HTML-entity-encoded when rendered into the email template. The display shows entities, the literal copy-paste is the entity form, not the actual password.

**Fix:**
- Either generate temporary passwords that exclude `&<>"` characters.
- Or render the password in a `<pre>` block with explicit instructions: "Copy the password from the box below (it may show as text but it's your password)."
- Or use magic links instead of temporary passwords entirely.

### Webhook bounces

Configure Postmark to POST to a webhook URL on bounce/complaint/delivery events. Lambda handler should:
- Log every event.
- On hard bounce → mark user as undeliverable (so we stop sending).
- On soft bounce → backoff retry.
- On complaint → mark unsubscribed and stop sending.

Webhook URL must be authenticated (HMAC or shared secret) — Postmark won't refuse to POST to an unauthenticated URL.

## Conventions

- Sender address per app: `<purpose>@<app>.<rootdomain>` (e.g. `invites@meals.jaetill.com`). Never the bare root domain — DMARC failures cascade.
- Postmark API token in AWS Secrets Manager, never in env vars.
- E2E testing: use Gmail plus-aliases on `jaetill@gmail.com` per `project_test_inbox_decisions` memory.

## See also

- [[cognito-pool-quirks]] — `MessageAction=SUPPRESS` pattern
- [[standards-secrets]] — API token storage
- `templates/_shared/test-inbox/` workspace package — E2E test runner that checks for delivered emails
