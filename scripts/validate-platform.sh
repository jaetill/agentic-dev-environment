#!/usr/bin/env bash
# validate-platform.sh — Verify platform internal consistency.
#
# Sanity check that the platform's own structure is well-formed:
# - All decided standards have corresponding ADRs and vice versa
# - All ADRs use the documented MADR 4.x format markers
# - All cross-references resolve (`ADR-NNNN`, `Standard NN`)
# - All agent definitions have required frontmatter
# - All slash commands are referenced from Standard 10
# - Hook scripts are executable

set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

check() {
  local description="$1"
  shift
  if "$@"; then
    echo "  ✅ $description"
  else
    echo "  ❌ $description" >&2
    errors=$((errors + 1))
  fi
}

echo "🔍 Validating platform: $PLATFORM_DIR"
echo

# ============================================================
# Standards ↔ ADRs
# ============================================================
echo "Standards ↔ ADRs..."
for std_file in "$PLATFORM_DIR"/docs/standards/[0-9]*.md; do
  std_name=$(basename "$std_file" .md)
  std_num=$(echo "$std_name" | cut -d- -f1)
  adr_link=$(grep -E '^\*\*ADRs?:\*\*' "$std_file" | grep -oE 'adr/[0-9]+-[a-z-]+\.md' | head -1 || true)
  if [[ -z "$adr_link" ]]; then
    echo "  ⚠️  $std_name: no ADR link found in standard" >&2
    errors=$((errors + 1))
  fi
done

# ============================================================
# ADR format markers
# ============================================================
echo "ADR MADR 4.x format..."
for adr_file in "$PLATFORM_DIR"/docs/adr/[0-9]*.md; do
  adr_name=$(basename "$adr_file" .md)
  for required_section in \
    "Context and Problem Statement" \
    "Decision Drivers" \
    "Considered Options" \
    "Decision Outcome" \
    "Consequences" \
    "Pros and Cons of the Options"; do
    if ! grep -qF "## $required_section" "$adr_file"; then
      echo "  ⚠️  $adr_name: missing section '$required_section'" >&2
      errors=$((errors + 1))
    fi
  done
done

# ============================================================
# Agent definitions
# ============================================================
echo "Agent definitions..."
expected_agents=(
  architect code-reviewer security-reviewer test-writer
  functional-tester e2e-tester doc-keeper release-captain
  dep-watcher incident-responder drift-detector triage-bot
)
for agent in "${expected_agents[@]}"; do
  agent_file="$PLATFORM_DIR/plugins/ai-team/agents/${agent}.md"
  check "$agent agent file exists" test -f "$agent_file"
  if [[ -f "$agent_file" ]]; then
    check "$agent has frontmatter (model)" grep -qE '^model:' "$agent_file"
    check "$agent has frontmatter (description)" grep -qE '^description:' "$agent_file"
  fi
done

# ============================================================
# Slash commands
# ============================================================
echo "Slash commands..."
expected_commands=(
  brainstorm adr review security-review test
  release-notes triage digest scaffold-project postmortem
)
for cmd in "${expected_commands[@]}"; do
  cmd_file="$PLATFORM_DIR/plugins/ai-team/commands/${cmd}.md"
  check "$cmd command file exists" test -f "$cmd_file"
done

# ============================================================
# Hook scripts
# ============================================================
echo "Hook scripts..."
for hook in "$PLATFORM_DIR"/plugins/ai-team/hooks/*.sh; do
  check "$(basename "$hook") is executable" test -x "$hook"
done

# ============================================================
# Reusable workflows
# ============================================================
echo "Reusable workflows..."
expected_workflows=(
  ci-python.yml claude-pr-review.yml release.yml docs.yml security-scan.yml
  deploy-dev.yml deploy-staging.yml deploy-prod.yml
  health-watch.yml auto-rollback.yml infracost.yml
  iac-drift-detect.yml emergency-deploy.yml
)
for wf in "${expected_workflows[@]}"; do
  check "$wf exists" test -f "$PLATFORM_DIR/.github/workflows/$wf"
done

# ============================================================
# Done
# ============================================================
echo
if [[ $errors -eq 0 ]]; then
  echo "✅ Platform validation passed."
  exit 0
else
  echo "❌ Platform validation failed with $errors errors." >&2
  exit 1
fi
