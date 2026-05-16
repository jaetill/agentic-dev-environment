---
name: vite-tailwind4
description: Use when working on a Vite + Tailwind 4 project. Covers the @tailwindcss/vite peer-dep conflict, PostCSS audit noise, and the --legacy-peer-deps convention.
---

# Vite + Tailwind 4

## When to consult

- `package.json` has `vite` ≥ 8 AND `tailwindcss` ≥ 4 (or `@tailwindcss/vite`).
- `npm install` errors with `ERESOLVE` mentioning `vite` and `@tailwindcss/vite` peer ranges.
- `npm audit` returns inflated counts referencing PostCSS plugins.

## Gotchas

### `npm install` fails with ERESOLVE on Vite 8 + @tailwindcss/vite

**Symptom:** Fresh `npm install` aborts with a peer-dependency conflict between Vite 8 and `@tailwindcss/vite` (which lists Vite 7 as its peer at time of writing).

**Root cause:** `@tailwindcss/vite` hasn't bumped its peer range to allow Vite 8. The actual integration works fine; the peer range is stale.

**Fix:** Always use `npm install --legacy-peer-deps` on projects on Vite 8 + Tailwind 4. Apply to every npm command (install, ci, update) until `@tailwindcss/vite` bumps its peer range.

### PostCSS audit noise

**Symptom:** `npm audit` reports 10+ vulnerabilities, mostly transitive PostCSS plugins.

**Root cause:** Old PostCSS plugin transitive deps surface as CVEs even when not exercised at build/runtime.

**Fix:** Triage in a single audit pass. Most are noise. Do NOT `npm audit fix` blindly — it can downgrade Tailwind. Use `npm audit --omit=dev` to focus on runtime exposure.

## Conventions

- Always `npm install --legacy-peer-deps` (and `npm ci --legacy-peer-deps` in CI).
- Vite config uses the Tailwind 4 plugin (`import tailwind from '@tailwindcss/vite'`), not PostCSS-based Tailwind 3 config.
- `tailwind.config.js` is OPTIONAL in v4 (CSS-first); only add it if you need to customize the theme via JS.

## See also

- [[vercel-deployment]] — Vercel builds run `npm ci`; ensure project sets `--legacy-peer-deps` via `.npmrc` or build command override
- [[playwright-e2e]] — also affected by peer-dep churn
