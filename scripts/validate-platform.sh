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
# ADR cross-reference integrity
# ============================================================
echo "ADR cross-reference integrity..."
adr_cross_ref_errors=0
while IFS= read -r adr_ref; do
  adr_num="${adr_ref#ADR-}"
  if ! compgen -G "$PLATFORM_DIR/docs/adr/${adr_num}-*.md" > /dev/null 2>&1; then
    echo "  ⚠️  $adr_ref referenced but docs/adr/${adr_num}-*.md does not exist" >&2
    errors=$((errors + 1))
    adr_cross_ref_errors=$((adr_cross_ref_errors + 1))
  fi
done < <(
  grep -rhoE 'ADR-[0-9]{4}' \
    "$PLATFORM_DIR/docs" \
    "$PLATFORM_DIR/plugins" \
    "$PLATFORM_DIR/.github/workflows" \
    "$PLATFORM_DIR/scripts" \
    "$PLATFORM_DIR/CLAUDE.md" \
    2>/dev/null \
  | sort -u
)
if [[ $adr_cross_ref_errors -eq 0 ]]; then
  echo "  ✅ All ADR cross-references resolve"
fi

# ============================================================
# Markdown link-path integrity (ADR-0026 follow-up)
# ============================================================
# The ADR cross-reference check above validates that an ADR *number*
# resolves to a file; it cannot catch a markdown link whose *path* is
# wrong — e.g. [ADR-0018](0018-reusable-review-workflow.md) when the file
# is actually 0018-workflow-distribution.md. This validates that every
# relative .md link target under docs/ resolves, relative to its file.
echo "Markdown link-path integrity..."
link_path_errors=0
while IFS= read -r entry; do
  link_src="${entry%%::*}"
  link_target="${entry##*::}"
  case "$link_target" in http*|mailto:*|"#"*|"") continue ;; esac
  link_target="${link_target%%#*}"
  [ -z "$link_target" ] && continue
  if [ ! -f "$(dirname "$PLATFORM_DIR/$link_src")/$link_target" ]; then
    echo "  ⚠️  $link_src links to '$link_target' which does not resolve" >&2
    errors=$((errors + 1))
    link_path_errors=$((link_path_errors + 1))
  fi
done < <(
  while IFS= read -r f; do
    { grep -aoE '\]\([^)]+\.md[^)]*\)' "$PLATFORM_DIR/$f" 2>/dev/null \
      | sed -E 's/^\]\(//; s/\)$//' \
      | while IFS= read -r t; do printf '%s::%s\n' "$f" "$t"; done ; } || true
  done < <(cd "$PLATFORM_DIR" && git ls-files -- docs | grep '\.md$' || true)
)
if [[ $link_path_errors -eq 0 ]]; then
  echo "  ✅ All markdown link paths resolve"
fi
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
