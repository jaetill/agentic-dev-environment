#!/usr/bin/env bash
# initial-commit.sh — One-time bootstrap of the platform repo's git state.
#
# Initializes git, makes the first commit, and tags `modules/v0.1.0` for the
# shared Terraform modules. Run from the platform repo root once.
#
# Per ADR-0002 (Source Control): main branch + Conventional Commits + signed.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -d .git ]]; then
  echo "ERROR: .git already exists. Refusing to re-initialize." >&2
  exit 1
fi

echo "🌱 Initializing platform repo..."
git init -b main

# Configure SSH commit signing per ADR-0002 if a signing key is available
if git config --global --get user.signingkey >/dev/null; then
  git config commit.gpgsign true
  git config gpg.format ssh
  echo "✅ SSH commit signing enabled (using global signingkey)."
else
  echo "⚠️  No global SSH signing key configured; commits will be unsigned."
  echo "   To enable per ADR-0002:"
  echo "     git config --global gpg.format ssh"
  echo "     git config --global user.signingkey ~/.ssh/id_ed25519.pub"
  echo "     git config --global commit.gpgsign true"
fi

echo "📝 Staging all files..."
git add .

echo "💾 Initial commit..."
git commit -m "chore: scaffold agentic-dev-environment platform foundation

- 10 standards (source control, CI/CD, testing, quality gates, documentation,
  observability, secrets, IaC, releases, AI workflows)
- 11 ADRs in MADR 4.x format with three documented extensions
- AI configuration: 12 specialist subagents + 10 slash commands + Mixed-strictness
  hooks (block destructive bash + secrets exposure; warn on lint/tests; inject
  context on prompt; audit bash)
- Per-stack templates (python-service complete; typescript-app + aws-iac deferred)
- Shared Terraform modules: iam-github-oidc, lambda-base, observability-baseline
  with native plan-only tests + Terratest integration tests
- 13 reusable GitHub Actions workflows + 2 module-test workflows
- 5 scaffolding scripts (new-project, bootstrap-tfstate, bootstrap-grafana,
  validate-platform, this script)
- AI shipping authority model: head agent + 12 subagents; ADR-gated categories
  are the only forced-human-gate; all routine work is autonomous"

echo "🏷️  Tagging modules/v0.1.0..."
git tag -a "modules/v0.1.0" -m "Initial release of shared Terraform modules.

Includes:
- iam-github-oidc: complete with native plan tests
- lambda-base: complete with native plan tests + Terratest
- observability-baseline: complete with native plan tests + Terratest

Status: 0.1.0 signals 'early' — verification with a real project pending.
Bump to 1.0.0 after first successful project scaffold + integration test pass."

echo
echo "✅ Initial commit + modules/v0.1.0 tag created."
echo
echo "Next steps:"
echo "  1. Create the GitHub repo: gh repo create <username>/agentic-dev-environment --public --source=. --push"
echo "  2. Push tags: git push --tags"
echo "  3. Apply branch protection per ADR-0002 (gh API call)"
echo "  4. Configure GitHub repo secrets: ANTHROPIC_API_KEY (and optional SEMGREP_TOKEN, INFRACOST_API_KEY)"
echo "  5. Run scripts/bootstrap-tfstate.sh in your AWS account (one-time)"
echo "  6. Run scripts/bootstrap-grafana.sh in your AWS account (one-time)"
echo "  7. Verify the platform: bash scripts/validate-platform.sh"
echo "  8. Scaffold your first project: scripts/new-project.sh --stack=python-service --name=<name>"
