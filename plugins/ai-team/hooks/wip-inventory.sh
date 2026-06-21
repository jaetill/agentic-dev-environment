#!/usr/bin/env bash
# SessionStart hook — WIP inventory at session start.
# Surfaces uncommitted changes, local-only / ahead-of-origin branches, and open PRs.
# Enforces the session-hygiene rule from CLAUDE.md: "Inventory unmerged work at session start."
# Non-blocking: always exits 0. Skips silently in CI / autonomous loop.

set -euo pipefail

# Skip in CI / autonomous loop — runs from clean checkouts, non-interactive
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  exit 0
fi

# Skip if not in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# 1. Uncommitted changes
status_summary=$(git status --short 2>/dev/null | head -n 50)  # cap output (#258): bound the blob injected into session context

# 2. Local branches with unpushed commits
# git branch output is always: "* <name>" (current) or "  <name>" (other) — 2-char prefix
wip_branches=()
while IFS= read -r line; do
  branch="${line:2}"
  [[ -z "$branch" ]] && continue
  # Skip the detached-HEAD pseudo-entry "(HEAD detached at ...)" (#252)
  [[ "$branch" == "("* ]] && continue
  tracking=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)
  if [[ -z "$tracking" ]]; then
    wip_branches+=("  $branch (no upstream — local only)")
  else
    ahead=$(git rev-list --count "${tracking}..${branch}" 2>/dev/null || echo 0)
    if [[ "$ahead" -gt 0 ]]; then
      wip_branches+=("  $branch (+${ahead} ahead of origin)")
    fi
  fi
done < <(git branch --no-color 2>/dev/null)  # --no-color (#230): color.ui=always corrupts branch names

# 3. Open PRs — structured JSON query to avoid injecting free-form PR titles
# (prompt-injection mitigation: omit user-controlled title/body fields; keep only
# safe structural identifiers)
open_prs=""
if command -v gh &>/dev/null && command -v jq &>/dev/null; then
  open_prs=$(gh pr list --state open --json number,headRefName,state,updatedAt 2>/dev/null \
    | jq -r '.[] | "#\(.number) \(.headRefName | gsub("[^A-Za-z0-9._/-]";"?")) [\(.state)] \(.updatedAt)"' \
    || true)
fi

# Only output the section if there is something worth surfacing
if [[ -z "$status_summary" ]] && [[ ${#wip_branches[@]} -eq 0 ]] && [[ -z "$open_prs" ]]; then
  exit 0
fi

echo "### WIP inventory"
echo ""

if [[ -n "$status_summary" ]]; then
  echo "**Uncommitted changes:**"
  echo '```'
  echo "$status_summary"
  echo '```'
fi

if [[ ${#wip_branches[@]} -gt 0 ]]; then
  echo "**Local branches with unmerged commits:**"
  printf '%s\n' "${wip_branches[@]}"
  echo ""
fi

if [[ -n "$open_prs" ]]; then
  echo "**Open PRs:**"
  echo "$open_prs"
  echo ""
fi

echo "> Review before starting new work. (CLAUDE.md session-hygiene)"
echo ""

exit 0
