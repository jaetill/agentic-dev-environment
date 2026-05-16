---
name: vercel-deployment
description: Use when deploying a Next.js or static project to Vercel. Covers NEXT_PUBLIC_* build-time inlining trap, auto-deploy on push, preview vs production environments, and Vercel CLI workflows.
---

# Vercel deployment

## When to consult

- Project is hosted on Vercel (`vercel.json` present, or repo connected via Vercel dashboard).
- Configuring environment variables for a Next.js or static project on Vercel.
- Debugging why a value isn't appearing in the deployed app.
- Setting up preview deployments per PR.

## Gotchas

### `NEXT_PUBLIC_*` is inlined at BUILD time

**Symptom:** Updated `NEXT_PUBLIC_API_URL` in Vercel dashboard but the deployed app still uses the old value. Hard refresh, clear cache — still old.

**Root cause:** `NEXT_PUBLIC_*` vars are inlined into the client bundle at `next build` time. Changing the var in the Vercel dashboard does NOT change the already-built bundle — you must trigger a new build.

**Fix:** After changing any `NEXT_PUBLIC_*` var, redeploy. Easiest: re-trigger the latest deployment in the Vercel dashboard, or push an empty commit.

**Corollary:** Set `NEXT_PUBLIC_*` vars in the Vercel project BEFORE the first deploy of a feature that uses them. If you set the var after the deploy, the deploy is stale.

### Auto-deploy on push (default)

Every push to a PR branch creates a preview deployment. Every push to `main` (or your production branch) creates a production deployment. There is no manual "promote to production" step unless explicitly configured.

**Implication:** Pushing a broken commit to `main` ships it. Branch protection (per Standard 01) prevents this — never disable it on Vercel-connected repos.

### Preview vs production env vars

Vercel maintains separate env var sets per environment: Development / Preview / Production. A var only set for Production won't appear in Preview deployments.

**Convention:** Set all secrets for both Preview and Production. The exception is production-only credentials (e.g. production DB write keys), where the Preview should use a separate sandbox DB.

### `vercel env ls preview` may not show all preview vars

Some marketplace integrations (Neon, Upstash) provision env vars at deploy time, not via the standard env var system. `vercel env ls` won't show them. Look in the deployment's runtime env (via `vercel inspect` or the dashboard's deployment detail page).

## Conventions

- Use Vercel for Next.js. Use S3+CloudFront for static apps (per the jaetill AWS architecture pattern).
- Push to PR branch → preview URL appears in PR comment within 90s.
- Production branch matches the GitHub default branch (usually `main`).

## See also

- [[nextjs-turbopack]] — Next.js-specific gotchas
- [[neon-vercel-integration]] — Neon provisions env vars via marketplace integration
- [[standards-ci-cd]] — Vercel deploy is the CI/CD pipeline for these projects
