# Runbooks

Operational playbooks for {{project_name}}. Format per platform [ADR-0008](https://github.com/{{github_username}}/agentic-dev-environment/blob/main/docs/adr/0008-documentation.md): tight 6-section (When / Prereqs / Steps / Verify / Rollback / Escalation).

## Default runbooks (from platform)

- [Deploy](deploy.md) — manual deploy procedure (when auto-deploy is bypassed)
- [Rollback](rollback.md) — manual rollback (when auto-rollback failed)
- [Incident response](incident-response.md) — general "something is broken in prod" procedure
- [Secret leak](secret-leak.md) — what to do when a secret is exposed
- [IaC recovery](iac-recover.md) — terraform state lost / corrupted recovery

## Project-specific runbooks

(Add as project-specific operational procedures emerge. Anything done twice gets a runbook the third time.)
