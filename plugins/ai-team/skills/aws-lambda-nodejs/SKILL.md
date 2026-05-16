---
name: aws-lambda-nodejs
description: Use when working on Node.js Lambda functions on AWS. Covers Node 20 SDK preinstall, bare-zip vs bundled-zip layouts, SecretsManager client caching, and the handler-must-match-filename rule.
---

# AWS Lambda (Node.js)

## When to consult

- Working in a `lambda/` directory with `.js` Lambda handlers.
- Configuring a Lambda's runtime, handler, or deploy artifact.
- Adding `@aws-sdk/*` packages to a Lambda's deps.

## Gotchas

### Node 20 runtime preinstalls SDK v3 — don't bundle it

**Symptom:** Cold-start time inflated to several seconds; deploy artifact > 5MB.

**Root cause:** Node 20 (and 18+) Lambda runtimes ship `@aws-sdk/*` clients preinstalled. Bundling them duplicates code and increases cold-start.

**Fix:** Mark `@aws-sdk/*` as `external` in your bundler (esbuild, webpack). Or just don't bundle — bare-zip works fine for single-file handlers.

### Bare-zip vs bundled-zip

- **Bare-zip**: `zip handler.zip handler.js node_modules/...` — Lambda extracts and runs. Fine for handlers with few deps.
- **Bundled-zip**: `esbuild handler.js --bundle --platform=node --target=node20 --outfile=dist/handler.js && zip handler.zip dist/handler.js` — single-file artifact. Faster cold-start when tree-shaken.

Use bundled-zip when the handler imports more than 2-3 npm packages.

### Handler name MUST match filename

**Symptom:** Lambda invoke returns "Runtime.HandlerNotFound" or "Cannot find module 'index'".

**Root cause:** The handler config (e.g. `groups.handler`) means "in `groups.js`, export `handler`." Renaming the file without updating the config breaks invocation silently in some IaC flows.

**Fix:** If the file is `groups.js`, the handler must be `groups.handler`. If you're using `index.js`, the handler is `index.handler`. Per the global CLAUDE.md rule (jaetill AWS Architecture Pattern, item 10): "Handler must match the JS filename — e.g. `groups.handler` for `groups.js`, NOT `index.handler` unless the file is actually `index.js`."

### SecretsManager: cache the client across invocations

**Symptom:** Lambdas hit Secrets Manager rate limits under load.

**Root cause:** Re-creating `SecretsManagerClient()` on every invocation; cold-starts re-init the client; warm invocations don't reuse.

**Fix:** Declare the client at module scope (outside the handler). Lambda reuses the module between warm invocations:

```js
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
const sm = new SecretsManagerClient({}); // module-scope; reused across invocations

let cachedSecret;
export const handler = async (event) => {
  if (!cachedSecret) {
    cachedSecret = (await sm.send(new GetSecretValueCommand({ SecretId: "..." }))).SecretString;
  }
  // ... use cachedSecret
};
```

## Conventions

- Per the global CLAUDE.md "jaetill AWS Architecture Pattern": one IAM role per Lambda app (never shared across apps). Roles named like `<app>-lambda-role` or function-specific like `MealPlannerSave-role-c47ma2hi`.
- All Lambdas in a project must have a corresponding deploy step in `.github/workflows/`. Missing the deploy step is a silent ship gap.
- Region is `us-east-2` per the global pattern.

## See also

- [[standards-iac]] — Lambda execution roles defined in Terraform
- [[standards-secrets]] — Secrets Manager is the runtime secret source
- [[cognito-pool-quirks]] — Cognito-triggered Lambdas have extra constraints
