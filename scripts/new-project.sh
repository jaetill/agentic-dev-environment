#!/usr/bin/env bash
# new-project.sh — Scaffold a new project from a stack template.
#
# Per ADR-0001's two-layer platform model: this script applies a per-stack template
# (from templates/<stack>/) into a target directory, substitutes variables, wires
# git + GitHub + AWS OIDC + Sentry + Grafana, and propagates the .claude/ AI config.
#
# Usage:
#   ./new-project.sh --stack=<stack> --name=<name> [--target-dir=<dir>] [--description=<text>]
#
# Stacks: python-service, typescript-app, aws-iac
# (typescript-app and aws-iac templates are skeletons; full implementation pending.)

set -euo pipefail

# ============================================================
# Argument parsing
# ============================================================
STACK=""
NAME=""
TARGET_DIR=""
DESCRIPTION=""
GITHUB_USERNAME="${GITHUB_USER:-${USER:-}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SKIP_GITHUB="${SKIP_GITHUB:-false}"
SKIP_AWS="${SKIP_AWS:-false}"
SKIP_SENTRY="${SKIP_SENTRY:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack=*)        STACK="${1#*=}" ;;
    --name=*)         NAME="${1#*=}" ;;
    --target-dir=*)   TARGET_DIR="${1#*=}" ;;
    --description=*)  DESCRIPTION="${1#*=}" ;;
    --github-username=*) GITHUB_USERNAME="${1#*=}" ;;
    --aws-region=*)   AWS_REGION="${1#*=}" ;;
    --skip-github)    SKIP_GITHUB=true ;;
    --skip-aws)       SKIP_AWS=true ;;
    --skip-sentry)    SKIP_SENTRY=true ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# //'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2 ;;
  esac
  shift
done

# ============================================================
# Validation
# ============================================================
[[ -n "$STACK" ]] || { echo "ERROR: --stack required" >&2; exit 2; }
[[ -n "$NAME" ]] || { echo "ERROR: --name required" >&2; exit 2; }
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "ERROR: --name must be kebab-case" >&2; exit 2; }

case "$STACK" in
  python-service|typescript-app|aws-iac) ;;
  *) echo "ERROR: --stack must be one of: python-service, typescript-app, aws-iac" >&2; exit 2 ;;
esac

# Default target dir per global CLAUDE.md workspace
TARGET_DIR="${TARGET_DIR:-${HOME}/Documents/Source Code/${NAME}}"
PROJECT_SLUG=$(echo "$NAME" | tr '-' '_')

if [[ -e "$TARGET_DIR" ]]; then
  echo "ERROR: target directory already exists: $TARGET_DIR" >&2
  exit 3
fi

if [[ -z "$GITHUB_USERNAME" ]] && [[ "$SKIP_GITHUB" != "true" ]]; then
  echo "ERROR: GitHub username not detected. Set GITHUB_USER or pass --github-username" >&2
  exit 2
fi

# ============================================================
# Locate the platform repo (where this script lives)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$PLATFORM_DIR/templates/$STACK"
SHARED_DIR="$PLATFORM_DIR/templates/_shared"

[[ -d "$TEMPLATE_DIR" ]] || { echo "ERROR: template not found: $TEMPLATE_DIR" >&2; exit 4; }

echo "🚀 Scaffolding $NAME ($STACK) at $TARGET_DIR"
echo

# ============================================================
# Phase 1: Copy template files
# ============================================================
echo "📁 Copying template..."
mkdir -p "$TARGET_DIR"
cp -r "$TEMPLATE_DIR/." "$TARGET_DIR/"

# Rename __project_slug__ directory to actual slug
if [[ -d "$TARGET_DIR/src/__project_slug__" ]]; then
  mv "$TARGET_DIR/src/__project_slug__" "$TARGET_DIR/src/$PROJECT_SLUG"
fi

# Rename CLAUDE.template.md and README.template.md
[[ -f "$TARGET_DIR/CLAUDE.template.md" ]] && mv "$TARGET_DIR/CLAUDE.template.md" "$TARGET_DIR/CLAUDE.md"
[[ -f "$TARGET_DIR/README.template.md" ]] && mv "$TARGET_DIR/README.template.md" "$TARGET_DIR/README.md"

# ============================================================
# Phase 2: Variable substitution
# ============================================================
echo "🔧 Substituting template variables..."
substitute() {
  local file="$1"
  sed -i \
    -e "s|{{project_name}}|$NAME|g" \
    -e "s|{{project_slug}}|$PROJECT_SLUG|g" \
    -e "s|{{project_description}}|${DESCRIPTION:-A new $STACK project}|g" \
    -e "s|{{github_username}}|$GITHUB_USERNAME|g" \
    -e "s|{{aws_region}}|$AWS_REGION|g" \
    -e "s|{{author_name}}|${GIT_AUTHOR_NAME:-$USER}|g" \
    -e "s|{{author_email}}|${GIT_AUTHOR_EMAIL:-$USER@users.noreply.github.com}|g" \
    -e "s|{{license}}|MIT|g" \
    -e "s|{{has_live_data}}|TBD|g" \
    -e "s|{{describe_live_data}}|describe what user data this project handles, if any|g" \
    -e "s|{{project_specific_conventions}}|(Add any conventions specific to this project here.)|g" \
    "$file"
}

# Find all text files and substitute
find "$TARGET_DIR" -type f \
  \( -name "*.md" -o -name "*.toml" -o -name "*.yml" -o -name "*.yaml" \
     -o -name "*.json" -o -name "*.tf" -o -name "*.tfvars.example" \
     -o -name ".gitignore" -o -name ".env.local.template" \
     -o -name "*.py" -o -name "*.ts" -o -name "*.js" \) \
  -exec bash -c 'substitute "$1"' _ {} \;

# Note: in zsh, `find -exec bash -c` won't see substitute. Export it.
export -f substitute

# ============================================================
# Phase 3: Propagate .claude/ from shared
# ============================================================
echo "🤖 Propagating AI configuration..."
mkdir -p "$TARGET_DIR/.claude"
cp -r "$SHARED_DIR/claude/agents" "$TARGET_DIR/.claude/"
cp -r "$SHARED_DIR/claude/commands" "$TARGET_DIR/.claude/"
cp -r "$SHARED_DIR/claude/hooks" "$TARGET_DIR/.claude/"
cp "$SHARED_DIR/claude/settings.json" "$TARGET_DIR/.claude/settings.json"
chmod +x "$TARGET_DIR/.claude/hooks"/*.sh 2>/dev/null || true

# ============================================================
# Phase 4: Initialize git
# ============================================================
echo "📝 Initializing git..."
cd "$TARGET_DIR"
git init -b main
git config commit.gpgsign true 2>/dev/null || true   # Per ADR-0002 SSH signing
git add .
git -c user.name="${GIT_AUTHOR_NAME:-$USER}" -c user.email="${GIT_AUTHOR_EMAIL:-$USER@users.noreply.github.com}" \
  commit -m "chore: scaffold $NAME from $STACK template

Generated by agentic-dev-environment platform scaffolding script.
See https://github.com/$GITHUB_USERNAME/agentic-dev-environment for the standards
governing this project." \
  >/dev/null

# ============================================================
# Phase 5: Create GitHub repo + branch protection
# ============================================================
if [[ "$SKIP_GITHUB" != "true" ]]; then
  echo "📦 Creating GitHub repo..."
  if command -v gh >/dev/null; then
    gh repo create "$GITHUB_USERNAME/$NAME" \
      --public \
      --description "${DESCRIPTION:-A $STACK project}" \
      --source="$TARGET_DIR" \
      --push

    echo "🔒 Applying branch protection (Strict per ADR-0002)..."
    gh api -X PUT "repos/$GITHUB_USERNAME/$NAME/branches/main/protection" \
      --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "required_signatures": true
}
EOF

    echo "🔧 Configuring repo settings (squash merge only)..."
    gh api -X PATCH "repos/$GITHUB_USERNAME/$NAME" -f \
      'allow_squash_merge=true' -f 'allow_merge_commit=false' -f 'allow_rebase_merge=false' \
      -f 'allow_auto_merge=true' -f 'delete_branch_on_merge=true' >/dev/null

    echo "📋 Creating release-block label..."
    gh label create "release-block" -c "B60205" -d "Pause release-please auto-merge for this PR" -R "$GITHUB_USERNAME/$NAME" 2>/dev/null || true

    echo "🌍 Creating GitHub environments (dev, staging, prod)..."
    for env in dev staging prod; do
      gh api -X PUT "repos/$GITHUB_USERNAME/$NAME/environments/$env" >/dev/null
    done

    echo "✅ GitHub setup complete: https://github.com/$GITHUB_USERNAME/$NAME"
  else
    echo "⚠️  gh CLI not installed; skipping GitHub setup. Push manually."
  fi
fi

# ============================================================
# Phase 6: AWS OIDC setup (if AWS-deployed)
# ============================================================
if [[ "$SKIP_AWS" != "true" ]] && [[ -d "$TARGET_DIR/terraform" ]]; then
  echo "☁️  AWS OIDC role setup is deferred to first 'tofu apply' run."
  echo "   When you're ready: cd terraform/envs/dev && tofu init && tofu apply"
  echo "   This will create the IAM OIDC role per ADR-0006."
fi

# ============================================================
# Phase 7: Sentry project setup
# ============================================================
if [[ "$SKIP_SENTRY" != "true" ]]; then
  echo "🔍 Sentry project setup:"
  echo "   - Create Sentry project at https://sentry.io/organizations/<your-org>/projects/new/"
  echo "   - Get the DSN; store in 1Password as op://$NAME/dev/sentry_dsn (and staging, prod)"
  echo "   - Add SENTRY_AUTH_TOKEN to GitHub repo secrets for release tracking"
fi

# ============================================================
# Done
# ============================================================
echo
echo "✨ Done! $NAME scaffolded successfully."
echo
echo "Next steps:"
echo "  1. cd \"$TARGET_DIR\""
echo "  2. uv sync --dev   # (or pnpm install for typescript-app)"
echo "  3. Review CLAUDE.md and tailor project-specific notes"
echo "  4. Set up secrets:"
echo "     - 1Password vault: \"$NAME\" with sentry_dsn, otel_endpoint, etc."
echo "     - GitHub secrets: ANTHROPIC_API_KEY (for AI workflows), GRAFANA_API_KEY"
echo "  5. First feature commit: \"git checkout -b feat/initial-setup\""
echo "  6. Open the docs site (will go live on first merge to main):"
echo "     https://$GITHUB_USERNAME.github.io/$NAME/"
echo
echo "The 12 specialist subagents and 10 slash commands are wired up in .claude/."
echo "The hook policy (Mixed strictness) is active per .claude/settings.json."
echo "Welcome to the platform."
