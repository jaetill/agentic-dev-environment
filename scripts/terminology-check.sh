#!/usr/bin/env bash
# terminology-check.sh — enforce that deprecated fleet terms don't leak
# into operational files. The canonical glossary lives at
# docs/standards/00-terminology.md and explains the rationale.
#
# A "deprecated term" is one that had a canonical role at some point but
# was superseded. It may legitimately appear in HISTORICAL contexts
# (ADRs, runbooks, this script's own comments) — but should not appear
# in OPERATIONAL files (live workflows, scripts, agent prompts) without
# an explicit inline exception.
#
# Exit codes:
#   0 — no violations
#   1 — one or more violations found
set -euo pipefail

# Repo root — assume we're called from the repo root.
REPO_ROOT="$(pwd)"

# Operational contexts: files that drive runtime behaviour. Drift in these
# directly produces incidents.
OPERATIONAL_GLOBS=(
  ".github/workflows/*.yml"
  ".github/workflows/*.yaml"
  "scripts/*.sh"
  "scripts/*.py"
  "plugins/ai-team/agents/*.md"
)

# Inline-exception marker form. A line containing
#   terminology-check: deprecated-<slug>-ok-here
# anywhere in the 5 lines preceding a match suppresses that match for
# that <slug> only. The 5-line window covers the natural case of a
# multi-line comment block whose only marker is at the block's start.
INLINE_EXCEPTION_WINDOW=5
match_has_inline_exception() {
  local file="$1"
  local line_num="$2"
  local slug="$3"
  local start_line=$((line_num - INLINE_EXCEPTION_WINDOW))
  if [[ "$start_line" -lt 1 ]]; then
    start_line=1
  fi
  local end_line=$((line_num - 1))
  if [[ "$end_line" -lt 1 ]]; then
    return 1
  fi
  local window
  window="$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)"
  if echo "$window" | grep -qF "terminology-check: deprecated-${slug}-ok-here"; then
    return 0
  fi
  return 1
}

# Search a single (term, slug) pair against the operational globs and
# report violations. Returns the number of violations found.
check_term() {
  local term="$1"   # the literal string or regex to grep for
  local slug="$2"   # short slug used in the inline-exception marker
  local description="$3"   # human-readable description shown in the error
  local local_violations=0

  for glob in "${OPERATIONAL_GLOBS[@]}"; do
    # shellcheck disable=SC2086
    for file in $glob; do
      [[ -f "$file" ]] || continue
      # Skip the script itself — it must reference the deprecated terms
      # to know what to check for.
      if [[ "$file" == "scripts/terminology-check.sh" ]]; then
        continue
      fi
      # Find matches with line numbers.
      while IFS=: read -r line_num line_content; do
        if [[ -z "$line_num" ]]; then continue; fi
        if match_has_inline_exception "$file" "$line_num" "$slug"; then
          continue
        fi
        echo "::error file=${file},line=${line_num}::terminology-check: deprecated term '${term}' (${description}) appears in operational file. See docs/standards/00-terminology.md > Deprecated terms. If this reference is legitimate, add 'terminology-check: deprecated-${slug}-ok-here' on the preceding line."
        local_violations=$((local_violations + 1))
      done < <(grep -nE "$term" "$file" 2>/dev/null || true)
    done
  done

  return "$local_violations"
}

violations=0

# Deprecated terms list. Each is (regex, slug, description).
# When you add a new deprecation:
#   1. Add a row to docs/standards/00-terminology.md > Deprecated.
#   2. Add a call here.
#   3. Sweep operational files for the old term in the same PR.
#
# Per ADR-0041 (2026-06-10):
check_term 'app/claude' 'app-claude' 'pre-ADR-0041 implementer PR-author login; superseded by app/jaetill-ai-triage-team' || violations=$((violations + $?))
check_term 'IMPLEMENTER_PAT' 'implementer-pat' 'pre-ADR-0041 implementer git-auth secret; superseded by FLEET_APP installation token' || violations=$((violations + $?))

if [[ "$violations" -gt 0 ]]; then
  echo "::error::terminology-check found $violations violation(s). See docs/standards/00-terminology.md for the deprecated-term policy."
  exit 1
fi

echo "✅ terminology-check: no deprecated terms in operational files"
