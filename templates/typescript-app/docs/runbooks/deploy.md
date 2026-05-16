# Runbook: Manual deploy

## When to use this

You should rarely need this. Per platform [ADR-0003](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0003-ci-cd.md), deploys are fully automated through release-please + the deploy workflow. Use this only if the auto-deploy workflow is broken and a deploy is genuinely time-critical.

## Prerequisites

- Vercel CLI installed (`pnpm dlx vercel`)
- Vercel auth token in 1Password (`op read op://{{project_name}}/dev/vercel_token`)
- The release tag you want to deploy (e.g., `v1.4.2`)

## Steps

1. **Checkout the release tag locally:**
   ```bash
   git fetch --tags
   git checkout v1.4.2
   ```

2. **Build production bundle:**
   ```bash
   pnpm install --frozen-lockfile
   pnpm build
   ```

3. **Deploy to the target environment:**
   ```bash
   op run --env-file=.env.local.template -- pnpm dlx vercel deploy --prod
   ```
   Success looks like: `https://<project-name>-<hash>.vercel.app` URL printed.

4. **Promote alias** (if not auto-promoted):
   ```bash
   op run --env-file=.env.local.template -- pnpm dlx vercel alias set <deployment-url> {{project_name}}.vercel.app
   ```

## Verification

- HTTP 200 from `/api/health` and `/api/ready`
- No errors in Sentry for 5 min post-deploy
- Vercel dashboard shows the new deployment as live
- Visit the homepage; verify the build hash matches the tag

## Rollback

See [`rollback.md`](rollback.md). Vercel makes rollback trivial via "Promote to production" on a previous deployment.

## Escalation

For solo: that's you. If you're stuck >30 minutes, document the state and consider taking the site offline (Vercel maintenance mode).
