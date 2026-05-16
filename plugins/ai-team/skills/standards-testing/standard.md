# Standard 03 — Testing

**Status:** 🟩 Decided (2026-05-08)
**ADR:** [ADR-0004](../adr/0004-testing.md)
**Extensions:** [ADR-0014](../adr/0014-email-workflow-testing.md) — §14 Testing email-bearing workflows

The testing standard is the safety net that the CI/CD shipping authority (ADR-0003) is trusting. Tests catch regressions; coverage tells us where we haven't tested; mutation testing tells us whether the tests we have actually catch bugs.

## Summary

| Concern | Choice |
|---|---|
| Test shape | Per-stack: pyramid (Python, TS APIs); trophy (TS web/UI); integration-heavy (IaC) |
| Coverage thresholds | **Tiered by criticality**: 90% critical / 80% default / 60% utility (line); branch ~10pp lower |
| Mutation testing | Required on critical paths; optional elsewhere |
| Frameworks | pytest, Vitest, Playwright, Hypothesis, mutmut/stryker, schemathesis, Terratest |
| Test layers | Defined operationally (unit, integration, e2e, smoke, contract) |
| Flaky test policy | Immediate fix-or-remove; no grace period |

## 1. Test shape (per stack)

Different stacks have different bug distributions, and "the right pyramid" is the one that catches your stack's bugs cheapest.

| Stack | Shape | Why |
|---|---|---|
| Python services / CLIs | **Classic pyramid** (lots of unit, fewer integration, few e2e) | Lots of pure-function logic; unit tests are cheap and catch most regressions. |
| TypeScript API services | **Classic pyramid** | Same reasoning. |
| TypeScript web / UI | **Testing trophy** (static + lots of integration > unit > e2e) | Bugs concentrate at component-integration boundaries; pure-unit tests of UI components are mostly noise. |
| AWS IaC (Terraform, CDK) | **Integration-heavy** | "Unit-testing" infra has limited value; the real test is whether `terraform plan` / `cdk synth` produces what you intend, and whether deployment to a test account succeeds. |

These are defaults. A project can override its shape with an ADR.

## 2. Coverage thresholds (tiered by criticality)

A single project-wide coverage number is too blunt — it underweights critical code and overweights utility code. We tier coverage by risk.

### Tiers

| Tier | Examples | Line cov. | Branch cov. | Mutation testing |
|---|---|---|---|---|
| **Critical** | Auth, authz, session handling, payment flows, data integrity (migrations, write paths), anything in an ADR-gated category | **≥ 90%** | **≥ 80%** | **Required** |
| **Default** | Business logic, API handlers, services, components, anything not explicitly tiered | **≥ 80%** | **≥ 70%** | Optional |
| **Utility** | Small helpers, glue code, type adapters, internal tooling | **≥ 60%** | **≥ 50%** | Not expected |

### Configuration

Tier assignment lives in the project's coverage config, mapping path globs to thresholds.

**pytest-cov example (`.coveragerc` or `pyproject.toml`):**

```toml
[tool.coverage.report]
fail_under = 80  # default-tier floor

[tool.coverage.path_thresholds]  # platform extension via custom plugin
"src/auth/**" = 90
"src/payments/**" = 90
"src/migrations/**" = 90
"src/utils/**" = 60
```

**Vitest example (`vitest.config.ts`):**

```ts
export default defineConfig({
  test: {
    coverage: {
      thresholds: {
        '**/src/auth/**': { lines: 90, branches: 80 },
        '**/src/payments/**': { lines: 90, branches: 80 },
        '**/src/utils/**': { lines: 60, branches: 50 },
        // default fallback
        global: { lines: 80, branches: 70 },
      },
    },
  },
});
```

### Excluded from coverage

- Auto-generated code (`*.gen.ts`, OpenAPI clients, GraphQL codegen output)
- Database migration *runners* (the migrations themselves are tested via dedicated integration tests)
- Type-only files (`*.d.ts`, type modules in Python)
- `__init__.py` and `index.ts` re-export files
- Test files themselves

### Enforcement

- Coverage runs on every PR.
- If any tier's threshold is missed → CI fails → merge blocked.
- Coverage report is posted as a PR comment by the test-writer agent, with a tier-by-tier breakdown.
- Total project coverage is reported but not separately enforced — the per-tier thresholds are what blocks.

## 3. Mutation testing

Mutation testing measures *whether tests catch bugs*, not whether they execute lines. It's expensive but the gold standard for critical code.

| Concern | Policy |
|---|---|
| Where required | All "Critical" tier paths |
| Where optional | Default tier (project may opt in) |
| Tooling | `mutmut` (Python), `stryker` (JS/TS) |
| When run | On a separate workflow, not per-PR. Runs on every release tag. |
| Threshold | Mutation score ≥ 75% on critical paths (mutants killed / total mutants). |
| Failure mode | If mutation score drops below threshold on a release, the release tag is blocked from promoting to staging until tests are improved. |

The PR-blocking gate is *line + branch coverage on critical paths*, which is fast. Mutation is the slower confirmation that those tests are actually doing work.

## 4. Frameworks per stack

| Stack | Framework | Notes |
|---|---|---|
| Python | **pytest** | Default; with `pytest-cov` for coverage, `pytest-asyncio` for async, `hypothesis` for property-based |
| TypeScript / Node | **Vitest** | Chosen over Jest: faster, Vite-native, near-100% Jest API compatibility |
| React | **Vitest + Testing Library** | Tests behavior over implementation |
| E2E (web) | **Playwright** | Multi-browser, headed/headless, screenshot+video on failure |
| Terraform | **terraform validate + tflint + tfsec/checkov + Terratest** (for live tests) | Static + actual-deploy validation |
| AWS CDK | **Vitest + CDK assertions** (`@aws-cdk/assertions`) | CDK is code; test it like code |
| API contract | **schemathesis** (Python) | Auto-generated tests from OpenAPI spec |
| Property-based | **Hypothesis** (Python) / **fast-check** (TS) | Encouraged for data transformations; not required |
| Mutation | **mutmut** (Python) / **stryker** (TS) | Critical paths only |

## 5. Test layer definitions

These definitions are *operational*: they determine which layer a given test belongs to and which CI gate runs it. The testing agents (test-writer, functional-tester, e2e-tester) use these to know what to author.

| Layer | Definition | Speed budget | Run when |
|---|---|---|---|
| **Unit** | One function/class in isolation. No I/O, no DB, no network, no filesystem (except `tmpdir` for clearly-temporary writes). | <10ms each | On every PR |
| **Integration** | Multiple components together. May use a real DB (ephemeral / containerized via Testcontainers or similar). May call internal services. | <1s each | On every PR |
| **E2E** | The deployed application from outside (HTTP, browser via Playwright). | seconds each | On merge to `main` (against dev) and on tag (against staging) |
| **Smoke** | Post-deploy sanity: a handful of "is the app alive" checks against critical endpoints. | <30s total | After every deploy, before health-watch window |
| **Contract** | API contract between services. Schema-driven (OpenAPI). | seconds each | On API spec change; on every release |

Tests are organized in directories that match these layers (`tests/unit/`, `tests/integration/`, `tests/e2e/`, `tests/smoke/`, `tests/contract/`).

## 6. Flaky test policy — immediate fix-or-remove

Flakiness is the single biggest threat to the AI-shipping-authority model. A flaky test that auto-retries to green creates an invisible safety hole.

### Detection

A test is flagged as flaky when:

- It fails on a CI run, then passes on a re-run with no code change, **OR**
- The CI infrastructure detects intermittent pass/fail across recent runs (configurable: 3 of last 20 runs differ in outcome).

### Action — immediate

When a flake is detected:

1. **Merge is blocked** on the PR that surfaced the flake (or on `main` if detected post-merge).
2. The architect + test-writer agents are dispatched immediately to investigate.
3. The test must be either **fixed** (root-caused, made deterministic) or **removed** (with an issue created documenting why) before merge can proceed.
4. There is no quarantine, no grace period, no "we'll get to it later." Flakes are fixed at the moment of detection.

### Why no grace period

Industry practice (Google, Atlassian) often uses 7-day quarantine because they can't afford to block 100 teams while one team fixes a flake. That math doesn't apply here — it's solo work + AI labor. Immediate enforcement keeps the safety net real.

### What "fixing a flake" means

- **Identify the source** (timing, ordering, network, DB state, randomness, time-of-day).
- **Eliminate the source** (use deterministic time, freeze randomness, use proper waits not sleeps, isolate test data).
- **Document the fix** in the test file with a comment if the cause was non-obvious.
- **Don't hide it with retries.** Auto-retry is the smell, not the cure.

## 7. Test data strategy

| Concern | Choice |
|---|---|
| Fixtures vs factories | **Factories** (factory_boy / fishery). Fixtures only for static reference data. |
| Mocking external services | OK for unit tests. Discouraged in integration tests (use a real test instance). |
| Database in integration tests | **Real ephemeral DB** (Testcontainers, or `pytest-postgresql`). No SQLite-as-stand-in. |
| Test data isolation | Each test gets a fresh transaction (rolled back after) or a fresh schema. No shared state between tests. |
| Production data in non-prod envs | **Forbidden.** Dev/staging use seeded/factory data only. (Cross-cutting with the secrets standard.) |

## 8. Snapshot testing policy

Snapshots are useful but easily abused.

| Allowed | Forbidden |
|---|---|
| Component visual output (React, rendered HTML) | Logic output (function return values) |
| Stable, reviewed snapshots that capture *intended* output | "Green" snapshots that just record current behavior |
| Snapshots reviewed in PRs as code | Auto-updating snapshots in CI without review |

Snapshots count toward coverage but not toward mutation testing.

## 9. Property-based testing — encouraged where it earns its keep

Recommended for:

- Data transformations (parsers, serializers, encoders)
- Algorithms (sorting, search, math)
- Anything with strong invariants (e.g., "round-trip serialize/deserialize == identity")

Not required, but if a project uses Hypothesis or fast-check, the `test-writer` agent should treat it as the preferred style for these code paths.

## 10. Performance / load testing

| Type | Required? | Where |
|---|---|---|
| Smoke perf check (response time within bounds) | Yes | Post-deploy, in the smoke test layer |
| Load testing | No (project-specific) | Defer to project-level decision |
| Profiling regression detection | No | Defer to observability standard |

## 11. AI agent roles in testing

Cross-references the AI workflows standard (ADR-0011 / Standard 10). Listed here for clarity:

| Agent | Testing role |
|---|---|
| `test-writer` | Authors unit + integration tests for new/changed code; updates them when behavior changes |
| `functional-tester` | Runs and authors functional + integration tests, especially against staging |
| `e2e-tester` | Authors and runs Playwright suites; investigates e2e failures |
| `architect` | Decides test shape for new modules; resolves "should this be tested at unit or integration level?" |
| `incident-responder` | Triages flaky test detection events; coordinates fix |

## 12. Setup checklist

When bootstrapping a new project, the `new-project.sh` script will:

- [ ] Create `tests/` directory with subdirectories for each layer (unit/, integration/, e2e/, smoke/, contract/)
- [ ] Wire pytest / Vitest / Playwright per stack
- [ ] Configure tiered coverage in `pyproject.toml` / `vitest.config.ts`
- [ ] Add path globs for critical / utility tier (defaults: `src/auth/**`, `src/payments/**`, `src/migrations/**` → critical; `src/utils/**`, `src/lib/helpers/**` → utility)
- [ ] Add Hypothesis / fast-check as dev deps
- [ ] Add mutation tooling (mutmut / stryker) configured for critical paths
- [ ] Add Testcontainers (or pytest-postgresql) for real-DB integration tests
- [ ] Add a flake-detection workflow that runs each PR's tests twice and flags discrepancy
- [ ] Add a release-time mutation testing workflow

## 13. Anti-patterns to avoid

- ❌ **Auto-retry to mask flakes.** This is how the safety net silently rots. Fix or remove.
- ❌ **SQLite as a stand-in for Postgres** (or any prod DB). Subtle behavior differences hide bugs.
- ❌ **Mocks in integration tests.** If you're mocking, you're back to a unit test — name it accordingly.
- ❌ **Tests that depend on test order.** Flaky-by-design.
- ❌ **Coverage as a vanity number.** The point is regression catching, not the percentage.
- ❌ **Snapshot tests for logic.** Snapshots are for visual output; assertions are for behavior.
- ❌ **Tests that depend on real network calls** (other than e2e). Use a fake or a local server.
- ❌ **Skipping tier configuration.** Without per-path thresholds, the tiered coverage model collapses to a project-wide average and stops doing its job.

## 14. Testing email-bearing workflows

Workflows that emit user-facing email — Cognito invites, magic links, password
resets, notifications, nudges — fail in ways unit tests can't see:
emails that don't send, send but land in spam, send but with broken content,
or send to the wrong recipient. The fix is a shared component that exercises
the full path (app → SES → Gmail) and reads back the result, including the
**spam folder**.

**ADR reference:** [ADR-0014](../adr/0014-email-workflow-testing.md) —
covers provider choice, address strategy, Cognito cleanup safety, and secret
storage.

### Component

`@platform/test-inbox` lives at
[`templates/_shared/test-inbox/`](../../templates/_shared/test-inbox/) and
exposes:

- **`TestInbox` class** — programmatic API: `inbox.address`,
  `inbox.waitForEmail(criteria)`, `inbox.waitForCognitoInvite()`,
  `inbox.lastWasInSpam()`, `inbox.cleanup()`.
- **Playwright fixture** — `import { test, expect } from
  "@platform/test-inbox/playwright"`. Generates a unique alias per test;
  auto-marks emails read on teardown.
- **`cleanupCognitoTestUsers`** — safety-guarded helper for removing test
  users from a Cognito pool. See §14.4 for the guard contract.

### 14.1 Install in a consumer project

```jsonc
// package.json
{
  "devDependencies": {
    "@platform/test-inbox": "file:../../Agentic Dev Environment/templates/_shared/test-inbox"
  }
}
```

The `file:` form matches the `templates/_shared/terraform-modules/`
precedent and will convert cleanly to a normal version pin once the
workspace publishes versioned packages.

### 14.2 Environment surface

| Env var | Purpose |
|---|---|
| `GMAIL_TESTER_EMAIL` | Base address — default `jaetill@gmail.com` (plus-aliased per test). |
| `GMAIL_TESTER_CLIENT_ID` | OAuth client ID. |
| `GMAIL_TESTER_CLIENT_SECRET` | OAuth client secret. |
| `GMAIL_TESTER_REFRESH_TOKEN` | Long-lived refresh token for the tester account. |
| `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP` | Required when running `cleanupCognitoTestUsers` against a Cognito pool whose name does not contain "test". The alias-prefix guard is the load-bearing safety in this mode. |

### 14.3 Secret retrieval in CI

Secrets live in AWS Secrets Manager at `platform/test-inbox/gmail-tester`
(keys: `clientId`, `clientSecret`, `refreshToken`). Each consumer repo's
existing GitHub OIDC role needs `secretsmanager:GetSecretValue` scoped to
that secret ARN. In a workflow:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-2

- name: Load Gmail tester credentials
  run: |
    SECRET=$(aws secretsmanager get-secret-value \
      --secret-id platform/test-inbox/gmail-tester \
      --query SecretString --output text)
    echo "GMAIL_TESTER_CLIENT_ID=$(echo "$SECRET" | jq -r .clientId)" >> $GITHUB_ENV
    echo "GMAIL_TESTER_CLIENT_SECRET=$(echo "$SECRET" | jq -r .clientSecret)" >> $GITHUB_ENV
    echo "GMAIL_TESTER_REFRESH_TOKEN=$(echo "$SECRET" | jq -r .refreshToken)" >> $GITHUB_ENV
    echo "GMAIL_TESTER_EMAIL=jaetill@gmail.com" >> $GITHUB_ENV
```

Locally, drop the same vars into `.env.local` (gitignored).

### 14.4 Cognito cleanup contract (load-bearing safety)

`cleanupCognitoTestUsers` deletes Cognito users whose email matches a test
alias prefix. Five layered guards protect against accidental deletion of
real users:

1. `emailMatchesAlias` parameter is required and non-empty.
2. Server-side Cognito filter: `email ^= "<alias>"` (prefix match).
3. Client-side re-check: each returned user's email must `startsWith(alias)`.
4. Pool-name must contain `test` **or** env var
   `PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true` must be set.
5. Optional `poolNameContains` parameter for a consumer-specific extra check.

**Weakening any of these requires superseding ADR-0014.** In particular:
do not switch the `startsWith` check to `contains` or a regex without
re-arguing the safety case.

`PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true` should only ever be set in
the test command itself, never exported in a shell profile. If set
globally, guard #4 collapses and only the alias-prefix check stands
between a typo and real-user deletion.

### 14.5 Usage pattern (manual fixture wiring)

When this package is consumed via `file:`, importing
`@platform/test-inbox/playwright` can trip Playwright's "Requiring
@playwright/test second time" guard because two node_modules trees both
hold `@playwright/test`. The resilient pattern uses the pure
`inboxFixture` against the consumer's own `@playwright/test`:

```ts
// tests/e2e/admin-invite-flow.spec.ts
import { test as base, expect } from "@playwright/test";
import { inboxFixture, cleanupCognitoTestUsers } from "@platform/test-inbox";

const test = base.extend({
  inbox: async ({}, use, testInfo) => {
    await inboxFixture(
      {
        inboxProject: "gn",
        inboxRunId: process.env.GITHUB_RUN_ID ?? String(Date.now()),
        inboxOverrides: {},
        title: testInfo.title,
      },
      use,
    );
  },
});

test.afterAll(async () => {
  await cleanupCognitoTestUsers({
    userPoolId: "us-east-2_xneeJzaDJ",
    region: "us-east-2",
    emailMatchesAlias: "jaetill+gn-",
  });
});

test("admin invite delivers a usable temp password", async ({ inbox }) => {
  // ... drive the workflow under test using inbox.address ...
  const invite = await inbox.waitForCognitoInvite({ timeoutMs: 60_000 });
  expect(invite.tempPassword).toMatch(/.{8,}/);
  expect(inbox.lastWasInSpam()).toBe(false);   // <-- catches spam-folder bug
});
```

The `@platform/test-inbox/playwright` sugar entry point exports
extended `test` and `expect` for setups that successfully dedupe
`@playwright/test` (workspace-based monorepos). Prefer manual wiring
when in doubt.

### 14.6 Refresh token rotation runbook

Gmail OAuth refresh tokens can be invalidated by Google for inactivity,
scope changes, or if a user revokes consent. Symptom: integration tests
start failing with `invalid_grant` or `401 Unauthorized` from the Gmail API.

Recovery:

1. From the machine that owns the OAuth client, run an interactive
   `oauth2 flow` to mint a new refresh token against `jaetill@gmail.com`
   with scopes `gmail.readonly` + `gmail.modify`.
2. Update `platform/test-inbox/gmail-tester` in AWS Secrets Manager —
   replace the `refreshToken` field only.
3. Re-run the failing test locally to confirm.
4. CI runs the next workflow execution will pick up the new token via
   `secretsmanager:GetSecretValue`.

The `clientId` and `clientSecret` only change if the OAuth client itself
is rotated (rare); the runbook above covers the common case.

### 14.7 Local Gmail hygiene

When `GMAIL_TESTER_EMAIL=jaetill@gmail.com`, test mail lands in the real
account. Set a Gmail filter to keep the noise out of the inbox view:

- **Filter:** `to:(jaetill+gn-* OR jaetill+portal-* OR jaetill+ai-teacher-*)`
- **Actions:** Skip Inbox; Apply label `tester/`

The tester label gives an audit trail (don't auto-delete) and keeps the
real inbox clean.
