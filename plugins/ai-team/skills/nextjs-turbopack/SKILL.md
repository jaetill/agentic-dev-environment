---
name: nextjs-turbopack
description: Use when working on a Next.js 15+ App Router project that uses Turbopack as its bundler. Covers Sentry instrumentation, Google Fonts build-time fetch, App Router gotchas, the instrumentation-client.ts vs sentry.client.config.ts trap.
---

# Next.js + Turbopack

## When to consult

- The project's `package.json` has `next` ≥ 15 AND scripts use `--turbopack` (e.g. `next dev --turbopack`).
- You're configuring Sentry, OpenTelemetry, or any client-side instrumentation.
- You see build errors mentioning `instrumentation-client.ts`, font fetch failures, or hydration mismatches that don't reproduce with the Webpack bundler.

## Gotchas

### Sentry: `instrumentation-client.ts` replaces `sentry.client.config.ts` under Turbopack

**Symptom:** Sentry traces stop arriving after enabling Turbopack. No build error, no console warning.

**Root cause:** Turbopack does not run the webpack-only `sentry.client.config.ts` magic file. Sentry 8+ uses `instrumentation-client.ts` (next to `instrumentation.ts`) as the bundler-agnostic entry point. Old projects scaffolded with the Sentry wizard against webpack still have `sentry.client.config.ts` and silently lose client-side init under Turbopack.

**Fix:** Rename or move client init out of `sentry.client.config.ts` into `instrumentation-client.ts`. Verify by checking that `Sentry.init(...)` runs (set `debug: true` temporarily).

### Google Fonts fetched at build time, not runtime

**Symptom:** `next build` fails on a sandboxed CI runner with a network error fetching `fonts.googleapis.com`.

**Root cause:** `next/font/google` fetches font files at build time and embeds them in the output. Build runs without network → build fails.

**Fix:** Either allow build-time outbound network to `fonts.googleapis.com` and `fonts.gstatic.com`, or switch to `next/font/local` with the font files committed (e.g. via `npm i @fontsource/inter`).

### App Router gotchas

- `'use client'` directive must be the FIRST line. A comment above it makes the file a server component, often with confusing errors downstream.
- `cookies()` and `headers()` return Promises in 15+ — must be awaited.
- Server Actions need explicit `'use server'` and the module CANNOT be imported into a client component except via prop passing.

## Conventions

- Prefer Turbopack for dev (faster HMR) and webpack for production builds until Turbopack production stabilizes.
- Always co-locate route-level loading and error boundaries (`loading.tsx`, `error.tsx`) — App Router does not fall back to global handlers gracefully.

## See also

- [[vercel-deployment]] — Vercel deploys Next.js with NEXT_PUBLIC_* inlined at build time
- ADR-0011 — AI workflow policy that drove adopting Sentry as the error sink
