# Spec: Portal nudge feature (PR 1)

**Target repo:** `jaetill/jaetill-portal` (once `git init`'d + pushed)
**Branch:** `feat/portal-nudge`
**Scope:** Re-nudge stuck users (FORCE_CHANGE_PASSWORD), via admin button. Per-user + bulk.

## What this PR delivers

1. New Lambda action: re-nudge a stuck user by email
2. Per-user "Nudge" button on the admin table next to users with `status: 'FORCE_CHANGE_PASSWORD'`
3. "Nudge all stuck users" bulk button at the top of the admin table
4. 60-second per-user cooldown (in-memory Lambda Map, accident-protection only)
5. The nudge email is sent via Postmark from `jason@jaetill.com` (NOT Cognito's default; that path is unreliable and is the suspected cause of the original spam-routing bug)

## Out of scope (PR 2)

Migrating the INITIAL portal invite (`AdminCreateUser` → Cognito sends welcome email) to also use Postmark. Listed as task #31; do after PR 1 lands.

## Lambda changes (`lambda/invite.js`)

### New action handler

Reuse the existing POST `/invite` endpoint. Discriminate on `body.action`:

- `body.action === 'create'` (default; existing behavior) → create user + add groups
- `body.action === 'nudge'` (new) → re-nudge a single user
- `body.action === 'nudge-all-stuck'` (new) → iterate stuck users + nudge each

### `'nudge'` action implementation

```
Input: { action: 'nudge', email }
Auth: admins group required (same as create)

1. Validate email (reuse existing isValidInviteEmail-style check)
2. Cooldown check (60 sec, in-memory):
   - If lastNudgedAt[email] && (now - lastNudgedAt[email] < 60_000) → 429 with message
   - Otherwise set lastNudgedAt[email] = now (after success)
3. ListUsers filter=email to find the user. If not found → 404.
4. If UserStatus !== 'FORCE_CHANGE_PASSWORD' → 409 "user has already signed in".
5. Generate new temp password (reuse generateTempPassword()).
6. AdminSetUserPassword({ Username, Password: temp, Permanent: false }).
7. Send Postmark email from FROM_EMAIL with new temp password + sign-in URL.
   - Subject: "Reminder: complete your jaetill.com sign-in"
   - Body: text + html, includes email + temp password + sign-in URL
8. Return { sent: 1, email, status: 'nudged' }.
```

### `'nudge-all-stuck'` action implementation

```
Input: { action: 'nudge-all-stuck' }
Auth: admins group required

1. ListUsers (paginated, same pattern as handleListUsers).
2. Filter to UserStatus === 'FORCE_CHANGE_PASSWORD' only.
3. For each, check the in-memory cooldown. Skip those within 60s.
4. For each remaining: same flow as 'nudge' (generate temp, set, Postmark).
5. Return { sent, skipped, errors: [{ email, reason }, ...] }.
```

### In-memory cooldown

```js
// Module-scoped Map; survives warm Lambda invocations, resets on cold start.
// Accident-protection only — admin double-click shouldn't double-send.
const lastNudgedAt = new Map(); // email (lc) → epoch ms
const NUDGE_COOLDOWN_MS = 60_000;
```

### Postmark setup (mirror game-night-pwa)

Need to add Postmark dependency + secret:

- `package.json` add `node-fetch` if not present (or use built-in fetch in Node 20+)
- New env vars: `POSTMARK_KEY`, `FROM_EMAIL`
- Secret in AWS Secrets Manager: `portal/postmark` with the same API key game-night-pwa uses (it's `jaetill.com`-attached; both apps can use one key)
- Email template — see below

### Postmark email template

```
Subject: Reminder: complete your jaetill.com sign-in

TextBody:
  Hi,
  
  We sent you an invitation to sign in at jaetill.com but you haven't completed
  the sign-in yet. Here are fresh credentials:
  
  Email:           ${email}
  Temp password:   ${tempPassword}
  Sign-in URL:     https://just.jaetill.com/
  
  When you sign in, you'll be prompted to set a permanent password.
  
  If you didn't expect this email, you can ignore it.

HtmlBody:
  (same content, basic HTML — match game-night-pwa's invite template style)
```

Sign-in URL is the Cognito Hosted UI for the shared pool: `https://just.jaetill.com/`. Verify this matches your actual Hosted UI domain.

## UI changes (`src/js/main.js` + admin HTML)

### Per-user button

In the admin user table row rendering:

```js
if (user.status === 'FORCE_CHANGE_PASSWORD') {
  // render a <button class="btn-nudge" data-email="${user.email}">Nudge</button>
} else {
  // render '—' or status badge
}
```

Click handler: POST to /invite with `{ action: 'nudge', email }`. Display result toast.

### Bulk button at top of admin table

```html
<button id="btn-nudge-all" class="btn-bulk-nudge">
  Nudge all stuck users (<count>)
</button>
```

Count = number of users with `FORCE_CHANGE_PASSWORD` status. Disable if 0.

Click handler: confirm dialog ("This will email N users. Continue?"), then POST to /invite with `{ action: 'nudge-all-stuck' }`. Display summary toast.

### Toast / status messages

- Success: `Nudge sent to ${email}` or `Nudged ${sent} users (${skipped} skipped due to cooldown)`
- Error: `Failed to nudge: ${message}`

## Tests

Once portal has CI + the platform's test-inbox is wired, add `tests/e2e/portal-nudge-flow.spec.js`:

1. Admin creates a test user via `POST /invite` (action=create) → status FORCE_CHANGE_PASSWORD
2. Admin nudges via `POST /invite` (action=nudge) → returns 200
3. test-inbox waits for the Postmark nudge email
4. Verifies email lands in INBOX (not spam) ← the actual bug suspicion validated
5. Verifies email contains temp password + sign-in URL
6. (Stretch) Verifies cooldown by attempting a second nudge within 60s → expects 429

This depends on:
- Portal being on the platform with CI workflows
- test-inbox dep wired in portal's package.json
- AWS creds in CI for Cognito + Secrets Manager

For now: spec it; defer wiring until PR 1 + PR 2 land and we evaluate next steps.

## Files I'll touch in PR 1

- `lambda/invite.js` — add 'nudge' and 'nudge-all-stuck' action handlers, Postmark client, cooldown Map
- `package.json` — confirm fetch availability; add any postmark dep if not built-in
- `src/js/main.js` — admin table button rendering + click handlers
- (possibly) `src/css/...` for button styling — minimal

## Files I will NOT touch in PR 1

- `index.html`, `callback.html` — login flow unchanged
- The `AdminCreateUser` call (that's PR 2's job)
- Any existing test files (portal has none yet)

## Deploy gotchas to remember

Per workspace CLAUDE.md, portal "deploys are CLI-only (S3 + CloudFront + `aws lambda update-function-code`) until `git init` + push happens." After git init lands, decide whether to:
- Keep CLI-only deploys for now (faster iteration)
- OR wire a deploy.yml (proper, but more setup before PR 1 lands)

Recommend: keep CLI-only deploys for PR 1; wire deploy.yml as a separate post-platform-port concern.

## When Jason returns from break

1. Run the 3-step git init + GitHub push handoff (in my last chat message)
2. Confirm portal is on GitHub
3. Say "go" — I create `feat/portal-nudge` and implement against this spec
4. PR 1 ready for review in ~30-45 min of my time
