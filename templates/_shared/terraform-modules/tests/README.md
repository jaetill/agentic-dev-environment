# Module integration tests (Terratest)

Per [ADR-0004 §8](../../../../docs/adr/0004-testing.md): shared modules in this directory get **live integration tests** via Terratest because they're consumed by multiple projects. A bug in a shared module is a bug everywhere.

## Two layers of testing

Per Terratest 2026 best practices:

| Layer | Tool | Speed | Where it runs |
|---|---|---|---|
| **Static + plan** | Native `tofu test` (HCL) | Fast (~5–10s) | On every PR that touches the module |
| **Integration (deploy + verify + destroy)** | Terratest (Go) | Slow (3–10 min per test) | On release tag for `modules/v*.*.*` |

The plan-only HCL tests live alongside each module under `<module>/tests/plan.tftest.hcl`. The Go integration tests live here under `tests/integration/<module>_test.go`.

## Running locally

```bash
# Plan-only tests (fast)
cd templates/_shared/terraform-modules/lambda-base
tofu test

# Integration tests (slow; requires AWS credentials to a test account)
cd templates/_shared/terraform-modules/tests
go test -v -timeout 30m ./integration/...
```

## CI

- **On PR** (path-filtered to `templates/_shared/terraform-modules/**`): runs plan-only tests in parallel via `.github/workflows/test-modules-plan.yml`.
- **On tag matching `modules/v*.*.*`**: runs Terratest integration tests via `.github/workflows/test-modules-integration.yml` against a dedicated AWS test account (`AWS_TEST_ACCOUNT_ROLE_ARN`).

## Test isolation

Each test:

- Generates a unique resource prefix (e.g., `t-${random}`) so parallel test runs don't collide
- Runs in `t.Parallel()` mode (per Terratest best practice)
- Always tears down via `defer terraform.Destroy(t, options)` even on failure
- Uses a dedicated AWS test account separate from dev/staging/prod

## Cost discipline

Integration tests deploy real AWS resources for ~minutes per test. Per ADR-0007's performance budget discipline: tests run on tag, not per-PR. Per-test cost target: <$0.10. Total monthly cost target: <$5 across all module test runs.

## Adding tests

Each new shared module should ship with:

1. `<module>/tests/plan.tftest.hcl` — plan-only HCL tests (fast, run per-PR)
2. `tests/integration/<module>_test.go` — Terratest integration test (slow, run on tag)

Both layers should test:
- Required inputs validation
- Per-env defaults (where applicable)
- Optional behaviors (toggleable features)
- Output values
