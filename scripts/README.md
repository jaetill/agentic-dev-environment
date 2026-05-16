# Scripts

Bootstrap and maintenance utilities for the platform.

## Planned scripts

| Script | Purpose | Status |
|---|---|---|
| `new-project.sh` | Scaffold a new project from a template into a target directory; initialize git, push to GitHub, wire up gates | Planned |
| `apply-standards.sh` | Retrofit an existing project to the current platform standards (idempotent; reports diffs before applying) | Planned (deferred — see ADR-0001) |
| `update-projects.sh` | Pull platform updates into all known scaffolded projects (with confirmation per project) | Planned |
| `validate-platform.sh` | CI helper — verify that templates, workflows, and standards docs are internally consistent | Planned |

All scripts will be POSIX-shell where reasonable, Python where shell becomes painful. No project-specific logic in scripts; logic lives in templates and workflows.
