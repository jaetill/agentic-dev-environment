---
name: cognito-pool-quirks
description: Use when working with AWS Cognito user pools — sign-up, sign-in, admin user creation, Hosted UI, custom auth flows. Covers AliasAttributes vs UsernameAttributes, ALLOW_USER_AUTH, Hosted UI username label, and AdminCreateUser TemporaryPassword rules.
---

# AWS Cognito user pool quirks

## When to consult

- Designing a user pool's auth flow (sign-up via Hosted UI, magic link, admin invite).
- Investigating why a user can't sign in despite the pool reporting them as confirmed.
- Configuring `AdminCreateUser`, `AdminInitiateAuth`, or any admin-flow API.

## Gotchas

### `AliasAttributes=['email']` forbids email usernames

**Symptom:** `AdminCreateUser` with `Username=<email>` returns "User account already exists" or "Username should not be of email format."

**Root cause:** When the pool has `AliasAttributes=['email']`, the `Username` field is treated as an opaque ID — it CANNOT be an email address. Email is a secondary alias.

**Fix:** Either:
1. Set `UsernameAttributes=['email']` (the OPPOSITE setting) — then email IS the username, and `Username` field IS the user's email.
2. Generate an opaque username (UUID) and store the email separately.

Once a pool is created, `UsernameAttributes` and `AliasAttributes` are **immutable**. To change, recreate the pool.

### `ALLOW_USER_AUTH` enables choice-based auth flow

For "let the user pick how they sign in" (password vs passwordless vs WebAuthn), the explicit-auth-flow must include `ALLOW_USER_AUTH`. Default Cognito pools only enable `ALLOW_REFRESH_TOKEN_AUTH` + one explicit flow.

If you see "Auth flow not enabled for this client" on a `USER_AUTH`-initiated call, add `ALLOW_USER_AUTH` to the app client config.

### Hosted UI username label is not customizable

**Symptom:** Hosted UI shows "Username" but the pool actually uses email as the alias — users get confused.

**Root cause:** Hosted UI's labels are not user-customizable for the standard fields. The label "Username" is hardcoded even when the user is meant to enter an email.

**Fix:** Either use `UsernameAttributes=['email']` (so the field literally IS email and the label is "Email"), or host your own sign-in UI instead of Hosted UI.

### `AdminCreateUser` requires `TemporaryPassword` unless `MessageAction=SUPPRESS`

**Symptom:** `AdminCreateUser` succeeds, but user receives an unwanted welcome email.

**Root cause:** Default `MessageAction` sends Cognito's templated invite email containing the temporary password.

**Fix:** Pass `MessageAction='SUPPRESS'` to skip the email entirely. Then deliver your own custom invite (via SES/Postmark) with whatever onboarding flow you want. See `test-inbox` for testing this end-to-end with plus-aliases.

```python
client.admin_create_user(
    UserPoolId=pool_id,
    Username=email,
    UserAttributes=[{"Name": "email", "Value": email}, {"Name": "email_verified", "Value": "true"}],
    MessageAction="SUPPRESS",  # don't send Cognito's email; we'll send our own
    TemporaryPassword=generate_strong_temp_password(),
)
```

### Test pool cleanup

For E2E tests that create real Cognito users: tests must clean up with `admin_delete_user` AND verify the pool is the test pool (alias-prefix guard) — never blindly delete from a pool ID variable. Per `project_test_inbox_decisions` memory.

## Conventions

- One Cognito pool per app. Sharing pools across apps is forbidden.
- Test pool name must include `-test-` segment; cleanup code guards on this prefix.
- All Cognito-triggered Lambdas (PreSignUp, PostConfirmation, CustomMessage) use the `apiKeyAuthorizer-lambda-role`-style scoped role per the global IAM pattern.

## See also

- [[postmark-email]] — used to send the actual invite/magic-link email after `MessageAction=SUPPRESS`
- [[aws-lambda-nodejs]] — Cognito triggers are Lambda functions
- `templates/_shared/test-inbox/` workspace package — E2E testing for Cognito invite flow
