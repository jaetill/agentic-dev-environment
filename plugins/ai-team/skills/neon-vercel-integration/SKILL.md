---
name: neon-vercel-integration
description: Use when a project uses Neon Postgres provisioned via the Vercel marketplace integration. Covers cancel-and-retry pattern, per-PR branch lifecycle, DATABASE_URL visibility in vercel env ls, and postcss audit noise.
---

# Neon + Vercel integration

## When to consult

- Project uses Neon Postgres AND is deployed on Vercel.
- DATABASE_URL was provisioned via the Neon marketplace integration (not manually).
- Investigating why a Drizzle/Prisma migration fails on a Vercel preview deploy.

## Gotchas

### `DATABASE_URL` does NOT appear in `vercel env ls preview`

**Symptom:** Local `vercel env pull .env.preview.local` doesn't include `DATABASE_URL`, but it works in deployed preview environments.

**Root cause:** The Neon marketplace integration provisions per-deployment env vars dynamically — they're injected at deploy time, not stored in the standard env var system. `vercel env ls` only shows the standard env vars.

**Fix:** Don't try to mirror `DATABASE_URL` locally from Vercel. Instead, either:
- Use a separate local Neon branch (free tier supports it).
- Use a local Postgres for development.
- Pull `DATABASE_URL` from the deployment's runtime env via `vercel inspect <deployment-url>` for debugging only.

### Cancel-and-retry deploy pattern

**Symptom:** Concurrent pushes to the same branch trigger overlapping deploys; Neon branches get into weird states (provisioning a branch while the previous deploy is still tearing one down).

**Fix:** Cancel the in-flight deploy when a newer commit arrives. Vercel does this by default for the same branch — verify it's not disabled in your project settings.

### Per-PR Neon branch lifecycle

Each PR preview deployment provisions a fresh Neon branch (off `main` Neon branch). The branch is torn down when the PR is closed.

**Implication:** Migrations run on the per-PR branch, not on `main`. A migration that succeeds on a PR preview doesn't guarantee it'll succeed against `main` data — same schema, different row counts and shapes.

**Mitigation:** Run migrations against a copy of production data periodically (e.g. a `migration-test` branch refreshed weekly).

### PostCSS audit noise (when project also has Tailwind)

`npm audit` from a Next.js + Neon + Tailwind 4 project shows 10+ findings, most in transitive PostCSS deps. Triage in one pass; don't `npm audit fix` blindly. See [[vite-tailwind4]] for the same pattern.

## Conventions

- Neon branches are ephemeral. Don't store data in them you can't reconstruct.
- The main Neon branch IS the production database. Treat it accordingly.

## See also

- [[vercel-deployment]] — env var lifecycle
- [[nextjs-turbopack]] — Next.js stack pairs commonly with Neon
- [[standards-secrets]] — Marketplace-provisioned secrets are a special case
