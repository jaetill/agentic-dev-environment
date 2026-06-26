# Data-plane-read Deny overlay for drift roles (#297)

## What it is

An **optional, default-OFF** inline IAM Deny overlay for drift-detection roles
created by the `iam-github-oidc` module. Enable it per-consumer with:

```hcl
module "drift_role" {
  source                 = "../../../templates/_shared/terraform-modules/iam-github-oidc"
  # ...
  additional_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  deny_data_plane_reads  = true   # <-- opt in
}
```

When `true`, the module attaches an inline `aws_iam_role_policy` with a single
`Effect = "Deny"` statement (`Resource = "*"`) on the data-plane content-read
and credential-issuance actions listed below.

## Why (and why this approach over fully re-scoping)

Drift roles run `tofu plan -refresh-only` on a schedule. The pragmatic way to
give them "read enough to detect drift" has been to attach the AWS-managed
`ReadOnlyAccess` policy. But `ReadOnlyAccess` is broad: per Tempest SideChannel's
analysis it grants roughly **41 data-exfil content reads** — `s3:GetObject`,
`dynamodb:Scan`, `athena:GetQueryResults`, etc. — that a refresh-only plan never
needs. A compromised drift role could be used to read bucket and table contents.

Source: Tempest SideChannel, *"Unwanted permissions that may impact security when
using the ReadOnlyAccess policy in AWS"* —
<https://www.tempest.com.br/sidechannel/en/unwanted-permissions-that-may-impact-security-when-using-the-readonlyaccess-policy-in-aws>

Fully scoping the role (replacing `ReadOnlyAccess` with a hand-curated
allow-list of every describe/list/get action across every provider resource the
plan touches) is the "correct" least-privilege answer but is high-effort and
brittle: any new resource type added to a stack silently breaks drift detection
until the allow-list is extended.

**This overlay is the pragmatic middle:** keep `ReadOnlyAccess` (so the plan
keeps seeing everything it must), and layer an **explicit Deny** on just the
exfil subset that a refresh-only plan provably does not need. An explicit Deny
always beats the `ReadOnlyAccess` Allow, so the role can still detect drift but
can no longer read data-plane content. Default-OFF and safe-additive: existing
consumers are unchanged until they opt in.

## What is denied

```
s3:GetObject, s3:GetObjectVersion, s3-object-lambda:GetObject,
dynamodb:GetItem, dynamodb:BatchGetItem, dynamodb:Query, dynamodb:Scan, dynamodb:GetRecords,
dax:Query, dax:Scan,
cassandra:Select,
athena:GetQueryResults, athena:GetQueryExecution, athena:GetDatabase,
glue:GetTable, glue:GetTables, glue:GetDatabase, glue:GetDatabases,
kendra:Query,
datapipeline:QueryObjects,
es:ESHttpGet,
config:SelectResourceConfig,
cloudtrail:LookupEvents,
logs:StartQuery,
chime:Retrieve*,
connect:GetFederationToken,
gamelift:GetInstanceAccess,
ec2:GetPasswordData, ec2:GetConsoleOutput, ec2:GetConsoleScreenshot,
ecr:GetAuthorizationToken,
codeartifact:GetAuthorizationToken,
cognito-identity:GetCredentialsForIdentity, cognito-identity:GetOpenIdToken, cognito-identity:GetOpenIdTokenForDeveloperIdentity,
cognito-idp:GetSigningCertificate,
sts:GetSessionToken
```

## What is intentionally NOT denied (the drift-required exclusions)

These appear on Tempest's broad list but are **excluded** from the Deny because
`tofu plan -refresh-only` or common Terraform data sources legitimately need
them. Denying them would break drift detection with `AccessDenied`. **Do not add
them to the deny list** — this is the trap a future reader must avoid:

| Action | Why it's needed |
|---|---|
| `apigateway:GET` | Refresh reads API Gateway resources |
| `lambda:GetFunction` | Refresh reads Lambda function state |
| `ec2:DescribeInstanceAttribute` | Refresh reads EC2 instance attributes |
| `ssm:GetParameter` | Possible `aws_ssm_parameter` data source |
| `ssm:GetParameters` | Possible `aws_ssm_parameter(s)` data source |
| `ssm:GetParametersByPath` | Possible `aws_ssm_parameters_by_path` data source |
| `ssm:GetDocument` | Possible `aws_ssm_document` data source |

The same exclusion list and rationale are repeated as a comment in `main.tf`
above the `aws_iam_role_policy "deny_data_plane_reads"` resource.

## Note on secrets and KMS

`secretsmanager:GetSecretValue` and `kms:Decrypt` are **not** part of
`ReadOnlyAccess`, so they are intentionally absent from the Deny — there is
nothing to deny. The overlay narrows what `ReadOnlyAccess` itself granted; it
does not attempt to be a blanket exfil firewall.

## Per-repo rollout (Jason's to apply, repo by repo)

This is an IaC change that requires AWS credentials and touches IAM, so it is
applied manually, one repo at a time:

1. In the repo's drift-role module block, set `deny_data_plane_reads = true`.
2. Run `tofu plan`. **Review carefully:** the only change should be the new
   inline role policy (`aws_iam_role_policy.deny_data_plane_reads[0]` to be
   created). There should be **no drift** on any existing resource.
3. Run `tofu apply`.
4. After applying, wait for (or manually trigger) the next scheduled
   `iac-drift-detect` run and confirm it still **succeeds**.

### If drift detection starts failing after apply

A plan that now errors `AccessDenied` means a needed action got denied. Roll
back (see below), then report **which action** the error names so the deny list
can be corrected (the action likely belongs on the exclusions list).

## Rollback

Set `deny_data_plane_reads = false` and `tofu apply`. The inline policy is
destroyed and the role reverts to plain `ReadOnlyAccess` behavior.

---

Refs #297.
