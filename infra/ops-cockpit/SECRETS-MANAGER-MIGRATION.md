# Ops Cockpit — Secrets Manager migration runbook (#91)

Moves the two provider-auth secrets out of `TF_VAR_*` (captured in Terraform
state) and into AWS Secrets Manager. **Jason runs every step below — Claude
cannot apply this and never handles the secret values.**

## The pattern — value never in Terraform state

- Terraform owns only the secret **container** (`aws_secretsmanager_secret`).
- There is **deliberately no** `aws_secretsmanager_secret_version` with a
  literal value — that would write the plaintext into config/state, the exact
  exposure #91 is about.
- The value is populated **out of band** (`aws secretsmanager put-secret-value`)
  and read back at plan time by a read-only
  `data "aws_secretsmanager_secret_version"`. The value flows into provider /
  data-source auth but is **never persisted by a Terraform resource**.

## Chicken-and-egg

The `data.aws_secretsmanager_secret_version.*` reads **fail if the secret has
no version yet**. So a single `tofu apply` of this whole change will NOT work
on a fresh secret. You must create the empty containers, populate them out of
band, then apply the rest. Ordered steps below.

## Prerequisite — IAM

The identity that runs `tofu apply` for ops-cockpit (your local AWS profile
today; the CI apply role if/when this is automated) needs, on the two secret
ARNs (`arn:aws:secretsmanager:us-east-2:<acct>:secret:ops-cockpit/grafana-api-key-*`
and `...ops-cockpit/github-token-*`):

- **Steady state:** `secretsmanager:GetSecretValue`,
  `secretsmanager:DescribeSecret`.
- **Bootstrap only:** `secretsmanager:CreateSecret`,
  `secretsmanager:PutSecretValue`, `secretsmanager:TagResource`.

Do not wire fleet IAM as part of this change — grant the running identity these
permissions out of band (your local profile likely already has admin; the CI
role would need a policy update in its own repo/module).

## Ordered apply

### 1. Create the empty containers (no value yet)

```powershell
cd infra\ops-cockpit
tofu init   # picks up the new hashicorp/aws provider

tofu apply `
  -target=aws_secretsmanager_secret.grafana_api_key `
  -target=aws_secretsmanager_secret.github_token
```

This creates the two secrets with no version. The `data` reads and the
repointed providers are NOT applied yet (targeted apply skips them).

### 2. Populate the values OUT OF BAND (never in Terraform)

```powershell
aws secretsmanager put-secret-value `
  --secret-id ops-cockpit/grafana-api-key `
  --secret-string '<grafana service-account token>' `
  --region us-east-2

aws secretsmanager put-secret-value `
  --secret-id ops-cockpit/github-token `
  --secret-string '<fine-grained read-only GitHub PAT>' `
  --region us-east-2
```

Use the same two values currently in `TF_VAR_grafana_api_key` /
`TF_VAR_github_token`. These commands put the plaintext only into Secrets
Manager — never into a `.tf` file, tfvars, or state.

### 3. Apply the rest (data sources + repointed providers)

```powershell
tofu apply
```

Now the `data.aws_secretsmanager_secret_version.*` reads succeed (the secrets
have versions), the Grafana provider authenticates from
`local.grafana_api_key`, and the `fleet-github` data source's `accessToken`
comes from `local.github_token`. Expect **no drift on the data source's
`secure_json_data_encoded`** — `main.tf` keeps its existing
`lifecycle { ignore_changes }` (the read-only Grafana SA token can't write the
PAT through anyway; see README "Rotate credentials").

### 4. Retire the env vars

Once step 3 applies clean and the dashboard renders, the
`TF_VAR_grafana_api_key` / `TF_VAR_github_token` env vars are no longer read by
this config. Remove them from your shell profile. (The `grafana_api_key` /
`github_token` Terraform variables are kept with `default = null` during the
migration window — remove them, plus their README / tfvars-example mentions, in
a later cleanup once you are confident nothing sets the stale env vars.)

## Rotation (new model)

To rotate either credential after migration, `put-secret-value` a new version
into the same secret, then `tofu apply` (the `data` read picks up the new
`AWSCURRENT` version). For the `fleet-github` PAT the data-source path still
carries the `ignore_changes` caveat from README "Rotate credentials" — the
Grafana-side rotation paths (UI / direct API) there remain the operative ones
for the live data source; Secrets Manager is now the source of record for the
value Terraform reads.

## Rollback

If the migration misbehaves, revert to the env-var model:

1. Revert the provider/data-source repoint:
   - `providers.tf`: `auth = var.grafana_api_key`
   - `main.tf`: `accessToken = var.github_token`
   - (and drop the `default = null` from the two variables if you want the old
     "must be set" behavior back)
2. Re-export the env vars:
   ```powershell
   $env:TF_VAR_grafana_api_key = "<grafana service-account token>"
   $env:TF_VAR_github_token    = "<fine-grained read-only PAT>"
   ```
3. `tofu apply`. The Secrets Manager secrets can be left in place (harmless) or
   removed with `tofu destroy -target=aws_secretsmanager_secret.grafana_api_key
   -target=aws_secretsmanager_secret.github_token` once nothing reads them.

## Status

**STAGED, UNVERIFIED.** This change cannot be plan-tested headlessly (no AWS
creds in the agent environment, and the secrets do not exist yet, so the data
reads would fail). Held for Jason's sequenced apply — do not merge or
auto-apply.
