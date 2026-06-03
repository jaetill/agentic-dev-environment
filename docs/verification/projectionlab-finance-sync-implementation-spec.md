# projectionlab-finance-sync — Implementation Spec

**Status:** Spec (not yet executed)
**Date:** 2026-05-11
**Target repo:** `E:\Users\tille\Documents\Source Code\projectionlab-finance-sync` (does not yet exist)
**Platform:** [Agentic Dev Environment](../../README.md), v0.1.x
**Audience:** the implementer agent (per ADR-0026 autonomous-team architecture observed in game-night-pwa), or a human implementing the project end-to-end.
**Approach:** Greenfield scaffold (not retrofit). Apply the platform's standards from the start, with deviations documented up front because this project is unusually stripped-down (no backend, no AWS, no observability stack).

---

## 1. Executive summary

`projectionlab-finance-sync` is a **Tampermonkey userscript** that pushes Jason's financial data into [ProjectionLab](https://projectionlab.com) via its browser-side Plugin API (`window.projectionlabPluginAPI`). The source-of-truth for financial data is a `jason_finance.md` memo (private, lives elsewhere — not in this repo) which Claude transforms into a `plan.json` on demand. The userscript reads `plan.json` and the user's PL Plugin API key from Tampermonkey storage, then pushes accounts, balances, milestones, income/expenses into PL.

This is the **smallest-surface project** the platform has met so far. Most of the 11 platform standards don't apply meaningfully:

| Stack expectation | Reality | Result |
|---|---|---|
| Backend service (Lambda / Vercel / etc.) | None — browser-side only | Skip Phase 5/6/7 entirely |
| AWS infrastructure | None | Skip IaC standard |
| Deploy pipeline to production | Userscript hosted via GitHub Pages for direct Tampermonkey install | Replaces "deploy" with "publish a versioned .user.js" |
| Observability (Sentry, Grafana, CloudWatch) | Browser-side; no telemetry feasible without compromising privacy of `plan.json` | Skip Phase 5 |
| User feedback | Single-user (Jason) for now; GitHub Issues if widened | Skip Standard 11 (link to GH Issues in README only) |
| Live users / live data | Real financial data, but only Jason ever runs the script | Treat with the same care as live multi-user data |

What **does** apply with full force:

- **Standard 04 (Quality gates)** — security scanning is launch-critical. plan.json or API key in a commit = serious privacy leak.
- **Standard 07 (Secrets management)** — heavy emphasis. Real account balances must never enter Git.
- **Standard 05 (Documentation)** — the userscript needs install runbook, account-mapping doc, key-rotation runbook.
- **Standard 09 (Release management)** — release-please + Conventional Commits → semver tags drive userscript `@version` and Tampermonkey auto-update.
- **Standard 10 (AI workflows)** — the 12-agent roster + hooks + slash commands apply as in any project.
- **Standard 01 (Source control)** — GitHub Flow on `main` (greenfield; no legacy branch to worry about); SSH-signed commits; strict branch protection (signed commits + linear history + no force-push to `main` is the actual blast-radius defense for this repo).

The handoff: this spec, broken into implementer-sized tickets, lands an installable userscript with signed commits, structured docs, release-please-driven versioning, and rigorous secret discipline — without any backend / infra / observability machinery.

---

## 2. Project context

### What the userscript does

1. **Page detect** — only activates on `https://app.projectionlab.com/*`.
2. **Wait for the Plugin API** — `window.projectionlabPluginAPI` is loaded by PL itself; userscript waits for it.
3. **Read configuration** — from Tampermonkey's `GM_getValue` storage:
   - `apiKey` — the PL Plugin API Key (user-set once via menu)
   - `plan` — the full `plan.json` blob (user-set via paste or file selection)
   - `accountMap` — optional override mapping from `plan.json` account names to PL account IDs
4. **Sync** — call the PL Plugin API to upsert accounts, balances, milestones, income/expenses.
5. **Report** — show a small floating status panel (success counts, errors, last-sync timestamp). No remote telemetry.

### Source of `plan.json`

- **Generation:** Claude reads Jason's `jason_finance.md` memo (private; not in this repo) and writes `plan.json` per a documented schema. The Python extract script `extract/memo_to_plan.py` is **deferred** — Claude regenerates on demand. The repo ships `data/plan.example.json` (sanitized template) committed; `data/plan.json` (real data) is gitignored.
- **Schema:** see §6.5 below. Stable shape; versioned via a `schemaVersion` field.

### Distribution model

- Userscript file `userscript/pl-sync.user.js` hosted via **GitHub Pages** at `https://jaetill.github.io/projectionlab-finance-sync/pl-sync.user.js`.
- Tampermonkey points at that URL for `@updateURL` + `@downloadURL`.
- Each release tag (`v1.0.0`, `v1.1.0`, etc.) bumps the `@version` in the userscript header.
- release-please drives the version + changelog.

### Security boundaries

- **`plan.json`** — account balances, scenarios, financial milestones. Never enters Git. Gitleaks scans for accidents. A custom pre-commit hook also refuses any file matching `data/plan.json` (defense in depth — gitleaks scans content; this scans paths).
- **PL Plugin API Key** — stored only in Tampermonkey local storage (`GM_setValue`). Never typed into a committed file. `.env.example` does NOT contain a placeholder for it (we don't even want the field name to exist in repo-tracked files where a copy-paste could land a real value).
- **GitHub repo is PUBLIC** — portfolio piece. Anyone can read the source. Anyone can read the schema. No one can see Jason's real numbers because they're not in the repo.

### Community reference

[georgeck/projectionlab-monarchmoney-import](https://github.com/georgeck/projectionlab-monarchmoney-import) — solves a similar problem (importing Monarch Money exports into PL). Different upstream source (Monarch JSON vs. our `plan.json` from a Markdown memo), similar Plugin API pattern. **Read it** before authoring `pl-sync.user.js`.

---

## 3. Stack reality vs platform assumptions

### Six documented deviations (to be captured in project ADR-0001)

| Platform default | Project reality | Why |
|---|---|---|
| **Backend service** (Lambda / Vercel / etc.) | None — browser-side userscript only | The PL Plugin API is intentionally client-side; no server adds value, only attack surface |
| **AWS infrastructure** | None | No backend means no AWS |
| **Sentry / observability** | None | Browser-side userscript; remote telemetry would itself be a privacy leak (sends user's PL session details somewhere). Errors shown in the in-page status panel only. |
| **Deploy pipeline** | GitHub Pages hosts the `.user.js`; Tampermonkey auto-updates from there | Userscripts are distributed by URL, not deployed |
| **Live data** but **single user** | Jason is the only user (initially) | Some Standard 11 conventions are over-spec for "you are the user"; we keep the basics (GitHub Issues link in README) and skip the in-app widget |
| **Default branch `main`** (platform default) — *matches* | `main` (greenfield; no legacy `master`) | No deviation here; called out for parity with game-night-pwa's ADR-0001 which had to document `master` |

Note: the userscript is **JavaScript, not TypeScript** — same as game-night-pwa. The platform's typescript-app template is again the wrong reference; use platform standards directly, not template files.

---

## 4. Gap analysis per standard

| # | Standard | Applies? | What lands |
|---|---|---|---|
| 01 | Source control | ✅ Full | GitHub Flow on `main`, Conventional Commits, SSH-signed commits, branch protection (signed + linear + no force-push), squash merge. |
| 02 | CI/CD | ⚠️ Partial | CI runs lint + test + build (concatenate the userscript with its metadata header). No prod deploy step — release-please tag triggers GitHub Pages republish of the latest `.user.js`. No auto-rollback (nothing to roll back beyond `git revert`). |
| 03 | Testing | ✅ Full | Vitest + happy-dom; stub `window.projectionlabPluginAPI` in tests. Tiered coverage: critical paths = sync logic + key handling (90/80); util/UI = 60/50. |
| 04 | Quality gates | ✅ Full (security-critical) | ESLint flat config (JS variant, browser globals + Tampermonkey `GM_*` globals), Prettier, pre-commit (gitleaks + commitlint + lint-staged + **custom plan.json path block**), Semgrep + gitleaks + GitHub secret scanning. |
| 05 | Documentation | ✅ Full | MADR ADRs, runbooks (install, key rotation, plan.json regeneration, GH Pages republish), MkDocs Material site, architecture overview. |
| 06 | Observability | ❌ Skip | In-page status panel only. No Sentry, no CloudWatch, no Grafana. |
| 07 | Secrets management | ✅ Full (security-critical) | `plan.json` + API key NEVER in Git. 1Password CLI for personal vault (Jason's working copy of `plan.json` lives there if cached locally; though primary source is `jason_finance.md`). No `.env` file in the repo at all — the only secrets-adjacent file is `.env.example` and even that doesn't list the API key (we don't want anyone seeing the field name in repo-tracked files and pasting a real value). |
| 08 | IaC | ❌ Skip | No infrastructure. |
| 09 | Release management | ✅ Full | release-please (release-type: simple, since we're not a publishable npm package but we DO want semver tags); Conventional Commits drive `@version` in userscript header via a build step. |
| 10 | AI workflows | ✅ Full | 12 specialist subagents, 10 slash commands, Mixed-strictness hooks, ADR-gated category detection on PRs. |
| 11 | User feedback | ⚠️ Partial | No widget. README has a "Found a bug? File an issue: <link>" line. If/when widened beyond Jason, revisit Standard 11 fully via ADR-0002. |

---

## 5. Anti-list — what NOT to do

Explicit don'ts. Each one would either break security, scope-creep, or violate the spec.

- ❌ **Do NOT commit `data/plan.json`.** It's in `.gitignore`. A pre-commit path-check hook ALSO refuses it as defense in depth. Gitleaks scans every commit's content.
- ❌ **Do NOT add a `.env` file to the repo.** Not even an empty placeholder. The userscript reads its secrets from Tampermonkey's `GM_getValue`, not from a `.env`. `.env.example` may exist for documenting non-secret build-time vars only (e.g., `PL_BASE_URL` if it ever needs overriding for staging), and must NOT contain placeholders for the API key.
- ❌ **Do NOT write a server component.** No Vercel function, no Lambda, no Cloudflare Worker. The whole point is browser-only.
- ❌ **Do NOT add Sentry or any remote telemetry.** Any error reporting that leaves the browser is a privacy leak.
- ❌ **Do NOT add Vite or Webpack as a runtime framework.** A simple build script (or even concatenation) produces the `.user.js`. The userscript is a single hand-readable file with a metadata header; bundling adds complexity for no win.
- ❌ **Do NOT add Next.js / React / a UI framework.** The status panel is a few lines of vanilla DOM. Userscripts are typically <1000 lines; framework overhead doesn't pay off.
- ❌ **Do NOT auto-format `userscript/pl-sync.user.js` in a way that mangles its `// ==UserScript== ... // ==/UserScript==` metadata block.** Prettier and ESLint must be configured to leave that block alone.
- ❌ **Do NOT commit any real PL account ID or balance** to `data/plan.example.json`. Use clearly fake values (`account-id-12345`, `Acme Brokerage`, `$100.00`).
- ❌ **Do NOT publish the Python extract script (`extract/memo_to_plan.py`) yet.** Defer; ship as a stub with the documented interface (`jason_finance.md → plan.json schema`). Claude regenerates `plan.json` on demand for now.
- ❌ **Do NOT skip SSH commit signing.** This repo is public and contains references to financial-data tooling; signed-commits-only is the discipline that prevents impersonation in commit logs.
- ❌ **Do NOT include `plan.json` as a hardcoded constant in the userscript.** That would defeat the entire repo-secrecy model. The userscript must read from Tampermonkey storage at runtime.

---

## 6. Phased plan (compressed)

Phases align with the platform application procedure, but several are no-ops here. Each phase is independently shippable as its own PR.

### Phase 1 — Repo scaffold + documentation (lowest risk; ship first)

Files to create:

```
projectionlab-finance-sync/
├── README.md                                — install + use + security model
├── LICENSE                                  — MIT (or pick; document in ADR if not MIT)
├── .gitignore                               — must include data/plan.json + api-key.local
├── .editorconfig
├── CLAUDE.md                                — project-specific Claude context
├── package.json                             — devDeps + scripts (no runtime deps)
├── eslint.config.js                         — flat config, JS, browser + Tampermonkey globals
├── .prettierrc.json
├── .prettierignore
├── .pre-commit-config.yaml                  — gitleaks + commitlint + lint-staged + plan-path-block
├── .lintstagedrc.json
├── commitlint.config.js
├── vitest.config.js                         — happy-dom + tiered coverage
├── mkdocs.yml
├── .release-please-config.json              — release-type: simple
├── .release-please-manifest.json            — {".": "0.1.0"}
├── data/
│   ├── plan.example.json                    — sanitized template, committed
│   └── README.md                            — explains schema + that plan.json is gitignored
├── userscript/
│   ├── pl-sync.user.js                      — Phase 3 (stub here in Phase 1)
│   ├── header.template.js                   — userscript metadata template
│   └── README.md                            — Tampermonkey install instructions
├── extract/
│   └── README.md                            — describes the deferred memo_to_plan.py + the interface
├── docs/
│   ├── index.md
│   ├── architecture/overview.md
│   ├── adr/
│   │   ├── template.md                      — copy from platform
│   │   ├── index.md
│   │   └── 0001-platform-adoption.md        — documents the 6 deviations from §3
│   ├── runbooks/
│   │   ├── index.md
│   │   ├── install.md                       — for the user installing the userscript
│   │   ├── key-rotation.md                  — rotating the PL Plugin API key
│   │   ├── plan-regeneration.md             — how Claude regenerates plan.json from jason_finance.md
│   │   ├── pages-republish.md               — how the .user.js gets republished after a release
│   │   ├── secret-leak.md                   — what to do if plan.json or API key leaks
│   │   └── incident-response.md             — general "userscript is broken" procedure
│   ├── pl-api-cheatsheet.md                 — Plugin API reference (URLs, method names, gotchas)
│   ├── account-mapping.md                   — how plan.json account names map to PL account IDs
│   └── decisions.md                         — running notes that may become ADRs
└── .github/
    └── workflows/
        ├── ci.yml                           — lint + test (Phase 2 details)
        ├── release.yml                      — release-please (Phase 4)
        ├── docs.yml                         — MkDocs build + GH Pages deploy
        └── deploy-userscript.yml            — Phase 4 detail: republish .user.js to GH Pages on release
```

**What this phase delivers:**

- A scaffolded repo with all the structure in place
- The published docs site at `https://jaetill.github.io/projectionlab-finance-sync/` (built from `docs/` via MkDocs Material)
- ADR-0001 documenting the deviations
- Five runbooks covering install + key rotation + plan regeneration + pages republish + secret leak
- Schema for `data/plan.example.json`

### Phase 2 — AI configuration (additive; no behavior change)

Files to add (copy verbatim from platform):

```
.claude/
├── agents/                  — 12 files
├── commands/                — 10 files
├── hooks/                   — 10 .sh files + README.md
└── settings.json            — platform's standard hook policy
```

Greenfield repo means no `.claude/worktrees/` or `mcp.json` to merge with. Pure copy.

### Phase 3 — Userscript itself + tests

Files to create:

- `userscript/header.template.js` — the `// ==UserScript== ... // ==/UserScript==` block with placeholders for `@version` (filled at build time)
- `userscript/pl-sync.user.js` — the actual userscript (see §6.4 below for the structure)
- `userscript/build.js` — small Node script that reads the header template + the source, substitutes `@version` from `.release-please-manifest.json`, writes to `dist/pl-sync.user.js`
- `tests/unit/sync.test.js` — exercises the sync logic against a stubbed `projectionlabPluginAPI`
- `tests/unit/plan-validation.test.js` — exercises the `plan.json` validator
- `tests/unit/account-mapping.test.js` — exercises the account-name → account-ID mapping
- `tests/setup.js` — registers `GM_*` stubs + `window.projectionlabPluginAPI` stub for happy-dom

**Coverage targets per ADR-0004:**

- Critical (90/80): `userscript/src/sync.js` (the core push logic), `userscript/src/auth.js` (API key handling)
- Default (80/70): everything else under `userscript/src/`
- Utility (60/50): UI rendering helpers

### Phase 4 — CI workflows + release-please

Files to create:

- `.github/workflows/ci.yml` — runs lint + test on every PR
- `.github/workflows/claude-pr-review.yml` — 1-line wrapper (or inlined, per game-night-pwa's pattern observed when the platform repo isn't published — TODO check by the time this lands)
- `.github/workflows/release.yml` — inlined release-please (NOT a reusable workflow reference, since the platform isn't published — pattern matches game-night-pwa's inlined version)
- `.github/workflows/docs.yml` — MkDocs build + GH Pages deploy
- `.github/workflows/deploy-userscript.yml` — on release tag, build the `.user.js` (with the new version baked into the header) + publish to GH Pages

GitHub Pages serves both the docs site AND the `.user.js`. The deploy-userscript workflow uploads the userscript to a sibling path so both coexist:

```
https://jaetill.github.io/projectionlab-finance-sync/        — docs site (MkDocs)
https://jaetill.github.io/projectionlab-finance-sync/pl-sync.user.js   — the userscript
```

The Tampermonkey `@updateURL` and `@downloadURL` both point at the second URL.

### Phase 5 — Skipped (no observability)

Browser-side userscript with private user data → no remote telemetry. In-page status panel only.

### Phase 6 — Skipped (no IaC)

No infrastructure.

### Phase 7 — Partial (GitHub Issues link only)

README has:

```markdown
## Found a bug?

[Open an issue](https://github.com/jaetill/projectionlab-finance-sync/issues/new).
```

That's it. If the project widens beyond Jason as a user, revisit Standard 11 fully via ADR-0002.

---

## 7. File-by-file specifications

### 7.1 — `package.json`

```json
{
  "name": "projectionlab-finance-sync",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "description": "Tampermonkey userscript that syncs Jason's financial data into ProjectionLab via the browser Plugin API.",
  "scripts": {
    "test": "vitest run --passWithNoTests",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "build": "node userscript/build.js",
    "prepare": "husky || true"
  },
  "devDependencies": {
    "@commitlint/cli": "^19.5.0",
    "@commitlint/config-conventional": "^19.5.0",
    "@eslint/js": "^9.13.0",
    "@vitest/coverage-v8": "^2.0.0",
    "eslint": "^9.13.0",
    "eslint-plugin-import": "^2.31.0",
    "eslint-plugin-promise": "^7.1.0",
    "eslint-plugin-unused-imports": "^4.1.0",
    "globals": "^15.11.0",
    "happy-dom": "^15.0.0",
    "husky": "^9.1.0",
    "lint-staged": "^15.2.0",
    "prettier": "^3.3.0",
    "vitest": "^2.0.0"
  }
}
```

**Notable:** no Sentry, no AWS SDKs, no Vite, no React. Build is a tiny Node script.

### 7.2 — `.gitignore`

```gitignore
# Dependencies
node_modules/
.pnpm-store/

# Build output
dist/

# Testing / coverage
coverage/
.vitest-cache/

# CRITICAL — financial data, never commit
data/plan.json
api-key.local
*.local

# Environment files (we don't ship any, but defensive)
.env
.env.*
!.env.example

# Editor / OS
.vscode/*
!.vscode/extensions.json
.idea/
.DS_Store
Thumbs.db
*.swp
*~

# MkDocs
site/

# Pre-commit
.pre-commit-cache/

# ESLint / Prettier caches
.eslintcache
.prettiercache

# Claude / AI runtime
.claude/audit.log
.claude/sessions/
.claude/last-test-result
```

### 7.3 — `.pre-commit-config.yaml`

Includes a **custom local hook** that refuses any `data/plan.json` path, as defense in depth on top of `.gitignore` and gitleaks:

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: check-merge-conflict

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.2
    hooks:
      - id: gitleaks

  - repo: https://github.com/alessandrojcm/commitlint-pre-commit-hook
    rev: v9.16.0
    hooks:
      - id: commitlint
        stages: [commit-msg]
        additional_dependencies: ['@commitlint/config-conventional']

  - repo: local
    hooks:
      - id: lint-staged
        name: lint-staged
        entry: npx lint-staged
        language: system
        types: [text]
        pass_filenames: false

      - id: block-plan-json
        name: Refuse to commit data/plan.json
        # Triggers even if someone deliberately bypasses .gitignore with `git add -f`.
        # Exit non-zero if a staged path matches data/plan.json or api-key.local.
        entry: bash -c 'if git diff --cached --name-only | grep -E "^(data/plan\.json|api-key\.local)$" >/dev/null; then echo "BLOCKED: data/plan.json or api-key.local must never be committed (per spec §5 anti-list)"; exit 1; fi'
        language: system
        pass_filenames: false
        always_run: true
```

### 7.4 — `userscript/pl-sync.user.js` structure

```javascript
// ==UserScript==
// @name         ProjectionLab Finance Sync
// @namespace    https://github.com/jaetill/projectionlab-finance-sync
// @version      0.1.0
// @description  Push plan.json into ProjectionLab via the Plugin API
// @author       Jason Tilley
// @match        https://app.projectionlab.com/*
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @grant        unsafeWindow
// @updateURL    https://jaetill.github.io/projectionlab-finance-sync/pl-sync.user.js
// @downloadURL  https://jaetill.github.io/projectionlab-finance-sync/pl-sync.user.js
// @run-at       document-idle
// @license      MIT
// ==/UserScript==

(function () {
  'use strict';

  // ---------- Configuration helpers (Tampermonkey storage) ----------

  function getApiKey() { /* GM_getValue('apiKey', null) */ }
  function setApiKey(key) { /* GM_setValue('apiKey', key) */ }
  function getPlan() { /* GM_getValue('plan', null) — JSON-parsed */ }
  function setPlan(planJsonString) { /* parse, validate via planValidator, GM_setValue */ }
  function getAccountMap() { /* GM_getValue('accountMap', {}) */ }

  // ---------- Plan validation ----------

  function validatePlan(plan) {
    // Enforce schemaVersion + required top-level keys
    // (Test target: tests/unit/plan-validation.test.js)
  }

  // ---------- Account mapping ----------

  function resolveAccountId(planAccountName, accountMap, pl) {
    // 1. Check explicit accountMap override
    // 2. Fuzzy-match against pl.getAccounts() names
    // 3. If still unresolved, log to status panel for user to fix
    // (Test target: tests/unit/account-mapping.test.js)
  }

  // ---------- Sync logic (critical-tier coverage) ----------

  async function syncPlan(plan, pl) {
    // Idempotent: read existing PL state, diff against plan, push only changes.
    // (Test target: tests/unit/sync.test.js with stubbed pl)
  }

  // ---------- UI: floating status panel ----------

  function renderStatusPanel(state) {
    // Vanilla DOM. Shows: connected? api key set? plan set?
    // Last sync timestamp + counts (synced N accounts, M milestones, errors).
  }

  // ---------- Tampermonkey menu commands ----------

  GM_registerMenuCommand('Set PL API Key', () => {
    const key = prompt('Paste your ProjectionLab Plugin API Key:');
    if (key) setApiKey(key);
  });

  GM_registerMenuCommand('Set plan.json', () => {
    const blob = prompt('Paste plan.json contents:');
    if (blob) setPlan(blob);
  });

  GM_registerMenuCommand('Sync now', async () => {
    const pl = await waitForPluginAPI();
    const plan = getPlan();
    if (!plan) { return alert('No plan set; use "Set plan.json" first'); }
    await syncPlan(plan, pl);
  });

  // ---------- Bootstrap ----------

  function waitForPluginAPI(timeoutMs = 30000) {
    // Poll for unsafeWindow.projectionlabPluginAPI
  }

  // Mount status panel; user triggers sync via menu (no auto-sync on page load —
  // explicit-action principle for a tool that mutates financial data)
  renderStatusPanel(/* initial state */);
})();
```

**Key constraints for the implementer:**

- Keep the metadata block exactly at top of file; Prettier/ESLint must ignore lines until the `// ==/UserScript==` close.
- `@version` is the placeholder `0.1.0` in source; build step replaces it with the version from `.release-please-manifest.json`.
- No `import` / `export` statements — userscripts execute as a single IIFE in the page context. The codebase can be modularized into `userscript/src/*.js` files that get concatenated by `build.js`, or it can be a single file. Implementer's call.
- `unsafeWindow` is required to access `projectionlabPluginAPI` because Tampermonkey wraps `window` by default.

### 7.5 — `data/plan.example.json` schema

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-05-11T00:00:00Z",
  "asOfDate": "2026-05-11",
  "accounts": [
    {
      "name": "Acme Brokerage Taxable",
      "type": "TAXABLE_BROKERAGE",
      "balance": 100000.00,
      "currency": "USD",
      "owner": "self"
    },
    {
      "name": "Acme 401k",
      "type": "TRADITIONAL_401K",
      "balance": 200000.00,
      "currency": "USD",
      "owner": "self"
    }
  ],
  "income": [
    {
      "label": "Day job salary",
      "amount": 100000.00,
      "frequency": "ANNUAL",
      "startDate": "2026-01-01",
      "endDate": null,
      "growthRate": 0.03
    }
  ],
  "expenses": [
    {
      "label": "Living expenses",
      "amount": 60000.00,
      "frequency": "ANNUAL",
      "category": "ESSENTIAL"
    }
  ],
  "milestones": [
    {
      "label": "Mortgage paid off",
      "date": "2032-06-01",
      "kind": "DEBT_PAID"
    }
  ]
}
```

**Notes:**

- `schemaVersion` is mandatory. Bump when the userscript needs to understand new fields.
- All values in `plan.example.json` are clearly fake (round numbers, "Acme" naming).
- The validator (`validatePlan` in the userscript) enforces this shape. Real `plan.json` matches the shape but with real data.

### 7.6 — `docs/adr/0001-platform-adoption.md`

Documents the 6 deviations from §3:

1. No backend service (browser-side only)
2. No AWS infrastructure
3. No Sentry / observability
4. Deploy = userscript-publish-to-GitHub-Pages (not Lambda / Vercel / etc.)
5. Single user (Jason) initially; Standard 11 reduced to a GitHub Issues link
6. `main` branch matches platform default (no deviation; called out for parity)

Use MADR 4.x bundled-sub-decisions form. Reference the platform repo's standards by URL.

### 7.7 — `docs/runbooks/install.md`

User-facing install procedure. Audience is the userscript installer (currently Jason; potentially others later).

```markdown
# Install ProjectionLab Finance Sync

## When to use this

You want to push your `plan.json` into ProjectionLab and you haven't installed
the userscript yet.

## Prerequisites

- A browser with Tampermonkey installed
  ([Chrome](https://chrome.google.com/webstore/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo),
  [Firefox](https://addons.mozilla.org/firefox/addon/tampermonkey/), etc.)
- A ProjectionLab account (paid tier required for Plugin API access)
- Your PL Plugin API Key (Settings → Developer → Plugin API)
- Your `plan.json` (generated by Claude from your `jason_finance.md` memo;
  see [`plan-regeneration.md`](plan-regeneration.md))

## Steps

1. Visit https://jaetill.github.io/projectionlab-finance-sync/pl-sync.user.js
2. Tampermonkey will prompt to install. Review the metadata block (`@match`,
   `@grant`, etc.), then click **Install**.
3. Navigate to https://app.projectionlab.com.
4. Click the Tampermonkey icon → ProjectionLab Finance Sync → **Set PL API Key**.
   Paste your API key.
5. Same menu → **Set plan.json**. Paste the contents of your `plan.json`.
6. Same menu → **Sync now**. Watch the status panel for results.

## Verification

- Status panel shows "API key: set ✅ / plan: set ✅".
- After "Sync now": status panel shows synced counts (N accounts, M milestones).
- In ProjectionLab, navigate to Accounts — your accounts from `plan.json`
  should be present with the correct balances.

## Rollback

The userscript is idempotent — running it again with the same `plan.json`
should be a no-op. If a sync produces wrong data:

1. In PL: edit the affected items manually, OR delete them and re-sync from
   a corrected `plan.json`.
2. Open the Tampermonkey dashboard, locate this userscript, click "Disable" to
   stop further syncs while you investigate.

## Escalation

[File an issue](https://github.com/jaetill/projectionlab-finance-sync/issues/new)
with the status-panel error message (no `plan.json` data — that's private).
```

### 7.8 — Other runbooks (briefer specifications)

- **`key-rotation.md`** — How to rotate the PL Plugin API Key. Steps: revoke in PL Settings → generate new → Tampermonkey menu → Set PL API Key → paste new.
- **`plan-regeneration.md`** — Documents the `jason_finance.md → plan.json` flow. The actual extraction is currently Claude-driven (Jason asks Claude in a session to read the memo and produce a fresh `plan.json` matching `data/plan.example.json`'s schema). The `extract/memo_to_plan.py` stub documents the interface for a future implementation.
- **`pages-republish.md`** — How GitHub Pages republishes the `.user.js` after a release tag (via the `deploy-userscript.yml` workflow). Manual override: re-run the workflow via `workflow_dispatch`.
- **`secret-leak.md`** — If `plan.json` or the API key ever land in a public place: (1) revoke the PL API key immediately; (2) rotate per `key-rotation.md`; (3) if `plan.json` leaked, the financial data is exposed — there's no rotating that, only mitigating future exposure; consider whether to file a security incident with anyone affected (depends on what's in the plan).
- **`incident-response.md`** — Generic "userscript broken in prod" procedure. Mostly: disable in Tampermonkey, file an issue, investigate via the status panel + browser DevTools console (the userscript logs to console with a `[pl-sync]` prefix).

---

## 8. Implementer-sized tickets

If using the autonomous-team model (ADR-0026 per game-night-pwa), break this spec into implementer-sized tickets (50 LOC / 3 files / 1 component cap each). Suggested decomposition:

| # | Ticket | Files | LOC est. |
|---|---|---|---|
| 1 | Scaffold: package.json, .gitignore, .editorconfig, LICENSE, README skeleton | 5 files | ~80 |
| 2 | Quality gate configs: eslint, prettier, pre-commit (incl. plan-path-block), lintstaged, commitlint | 6 files | ~150 |
| 3 | Vitest config + tests/setup.js with GM_* stubs | 2 files | ~60 |
| 4 | Docs scaffolding: docs/index, architecture/overview, adr/{template,index,0001}, runbooks/index | 7 files | ~300 |
| 5 | Runbook: install.md | 1 file | ~80 |
| 6 | Runbook: key-rotation.md + plan-regeneration.md | 2 files | ~80 |
| 7 | Runbook: pages-republish.md + secret-leak.md + incident-response.md | 3 files | ~120 |
| 8 | mkdocs.yml + docs.yml workflow | 2 files | ~100 |
| 9 | Platform AI configuration: copy 12 agents + 10 commands + 10 hooks + settings.json | 33 files | ~0 LOC (copies) |
| 10 | data/plan.example.json + data/README.md | 2 files | ~80 |
| 11 | Userscript metadata template (header.template.js) + build.js | 2 files | ~120 |
| 12 | Userscript: configuration helpers (getApiKey/setApiKey/getPlan/setPlan/getAccountMap) | 1 file | ~80 |
| 13 | Userscript: plan validator + tests | 2 files | ~150 |
| 14 | Userscript: account mapping + tests | 2 files | ~150 |
| 15 | Userscript: sync logic (critical) + tests | 2 files | ~250 |
| 16 | Userscript: status panel UI | 1 file | ~120 |
| 17 | Userscript: bootstrap + menu commands (assembles all of the above into pl-sync.user.js) | 1 file | ~80 |
| 18 | CI: ci.yml + claude-pr-review.yml | 2 files | ~150 |
| 19 | CI: release.yml + release-please configs | 3 files | ~80 |
| 20 | CI: deploy-userscript.yml (publishes .user.js to GH Pages on release) | 1 file | ~100 |
| 21 | extract/README.md (deferred Python stub interface) | 1 file | ~80 |
| 22 | Final README polish + cross-links | 1 file | ~100 |

22 implementer-sized tickets. Could collapse to ~12-15 if appetite is higher.

---

## 9. Verification steps

After each phase:

| Phase | Verify |
|---|---|
| 1 — Scaffold + docs | `mkdocs build --strict` succeeds; ADR-0001 + 5 runbooks present; pre-commit installs and runs gitleaks/commitlint cleanly |
| 2 — AI configuration | 12 agents + 10 commands + 10 hooks in `.claude/`; settings.json valid JSON |
| 3 — Userscript + tests | `npm test` passes (with `--passWithNoTests` initially; real tests added per ticket); `npm run build` produces a valid `.user.js` with substituted version |
| 4 — CI workflows | Test PR triggers `claude-pr-review`; release-please opens a release PR on `main`; merge of release PR triggers `deploy-userscript` which publishes the `.user.js` to GH Pages |
| End-to-end | Visit `https://jaetill.github.io/projectionlab-finance-sync/pl-sync.user.js` in Tampermonkey → install → on PL → menu → Set API Key → Set plan.json → Sync now → see counts in status panel + accounts in PL |

---

## 10. Open questions (resolve before execution)

- **GitHub username:** spec assumes `jaetill`. Confirm matches Jason's GitHub.
- **License:** spec assumes MIT. Confirm or document the alternate in ADR-0001.
- **PL Plugin API documentation URL:** the spec assumes `window.projectionlabPluginAPI` is the entrypoint. Read `docs/pl-api-cheatsheet.md` (which the implementer will write from PL's own docs + the georgeck reference) to confirm exact method names: `getAccounts`, `setAccount`, `addMilestone`, etc.
- **PL Plugin API requires which subscription tier?** Document in `install.md` so users know what to buy.
- **Account types in `plan.json`:** the example uses `TAXABLE_BROKERAGE`, `TRADITIONAL_401K`. Confirm PL's exact enum names before locking the schema in ADR-0002 (or whichever ADR captures the schema).
- **Schema migrations:** when `schemaVersion` bumps, what's the migration path? Probably the userscript reads any version and validates; Claude regenerates `plan.json` matching the new schema. Document this in the validator's behavior.
- **Multi-user future:** if/when widened beyond Jason, what changes? Standard 11 would apply more fully (in-app feedback widget or GitHub Discussions). Consider in ADR-0001's deferred items list.

---

## 11. Summary

**What this spec delivers when fully implemented:**

- A clean greenfield repo with platform standards applied from day one
- A working Tampermonkey userscript published via GitHub Pages with semver auto-update
- Rigorous secret discipline: `plan.json` and the API key never enter Git, defended by three layers (gitignore, gitleaks content scanning, custom path-block pre-commit hook)
- 5 runbooks covering install + key rotation + plan regeneration + Pages republish + secret leak + incident response
- Auto-generated docs site at `https://jaetill.github.io/projectionlab-finance-sync/`
- 12 platform agents available; CI runs AI review on every PR; release-please drives versioning
- Conventional Commits + SSH-signed commits + strict branch protection — public repo with verified-author signal

**What this spec deliberately does NOT include:**

- Any backend service or AWS infrastructure
- Sentry or other remote telemetry
- Vite / Webpack / Next.js / any framework heavier than vanilla JS
- A live extraction pipeline from `jason_finance.md` (deferred; Claude-driven for now)
- A user feedback widget (single-user; GitHub Issues link only)
- Multi-user provisioning, account sharing, or any feature beyond "Jason syncs his own plan"

**The implementer agent's contract:**

- Read this spec.
- Open ticket #1, implement it within the scope cap (50 LOC / 3 files), open a PR, let code-reviewer + security-reviewer run, address blocking findings, get merged.
- Move to ticket #2. Repeat.
- After ticket #22, run the end-to-end verification from §9.
- If any ticket reveals that this spec is wrong (e.g., a PL Plugin API method doesn't exist), file a defect issue with `origin:internal-review` and pause until the spec is updated.

This is a portfolio piece. The point isn't just that the userscript works — it's that the *workflow* around it (platform standards + automated review + secure secret handling on a public repo + agent-driven implementation) demonstrates the discipline the platform was built to enforce.
