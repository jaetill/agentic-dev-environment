# Runbooks

Operational playbooks. One file per recurring operation: how to deploy, how to roll back, how to rotate a secret, how to respond to a specific class of alert, etc. Some files in this directory are also reference catalogs — collections of known patterns or quirks rather than procedures.

## Available

| File | Type | Purpose |
|---|---|---|
| [platform-port-quirks.md](platform-port-quirks.md) | catalog | Project-specific adaptations to apply when porting a new project to the platform |

## Format

### Procedural runbooks

Each procedural runbook should answer:

1. **When to use this** — the trigger condition.
2. **Prerequisites** — what you need open / installed / authenticated.
3. **Steps** — numbered, copy-pasteable, idempotent where possible.
4. **Verification** — how to confirm success.
5. **Rollback** — how to undo if it went wrong.
6. **Escalation** — who/what to notify if stuck.

### Reference catalogs

For docs that catalog known patterns / quirks / lookups (rather than procedures), each entry should answer:

1. **Symptom** — what you observe.
2. **Cause** — why it happens.
3. **Fix** — exact change to make.
4. **When it bites** — heuristic for predicting whether your situation triggers this.
5. **First seen** — project / PR / date for historical traceability.

The format will be locked in as part of the **documentation standard** (Standard 05 / ADR-0008).
