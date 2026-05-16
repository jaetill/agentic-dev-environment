# `install-node-deps` composite action

Platform-standard Node.js setup + dependency install with the platform's known
quirks baked in (`--legacy-peer-deps`, optional lambda install).

## Usage

In a consuming project's workflow:

```yaml
jobs:
  whatever:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jaetill/agentic-dev-environment/.github/actions/install-node-deps@main
      # ... rest of the job
```

This replaces the previous 4-line pattern:

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 22
    cache: npm
- run: npm ci --legacy-peer-deps
- run: |
    if [ -f lambda/package.json ]; then
      npm ci --legacy-peer-deps --prefix lambda
    fi
```

## Inputs

| Input | Default | Purpose |
|---|---|---|
| `node-version` | `22` | Node.js major version |
| `cache` | `npm` | actions/setup-node cache key (set to empty string to disable) |
| `lambda-dir` | `lambda` | Lambda directory to consider; install is skipped if `<lambda-dir>/package.json` does not exist; set to empty string to skip the lambda step entirely |
| `skip-root-install` | `false` | Set to `"true"` for jobs that need Node but not deps |

## Versioning

Today: pin via `@main`. Acceptable while the action is unstable.

Once the action stabilizes (no breaking changes for ~2 weeks across all
consuming projects), tag the workspace at `actions/install-node-deps/v1` and
update consumers to pin `@actions/install-node-deps/v1`. The platform's tag
convention is documented in [Standard 09 (release-management)](../../../docs/standards/09-release-management.md).

## Cross-repo access

The workspace is private. Consuming projects (also under the `jaetill` account)
need explicit access enabled:

```sh
gh api -X PUT repos/jaetill/agentic-dev-environment/actions/permissions/access \
  -F access_level=user
```

Run once after enabling Actions on the workspace. Confirms with:

```sh
gh api repos/jaetill/agentic-dev-environment/actions/permissions/access
# → {"access_level": "user"}
```

## Why this is a composite action and not a reusable workflow

Composite actions can run as a step within an existing job. Reusable workflows
(`workflow_call`) replace the whole job. The install pattern is a step-level
concern (one of many in a job), so composite action is the right shape.

See [`docs/runbooks/platform-port-quirks.md`](../../../docs/runbooks/platform-port-quirks.md)
for the broader discussion of when to use composite actions vs reusable
workflows vs inlined steps.
