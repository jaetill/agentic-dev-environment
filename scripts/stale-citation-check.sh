#!/usr/bin/env bash
# stale-citation-check.sh — deterministic pre-LLM stale-citation check (ADR-0040)
#
# Before the promoter's LLM evaluation of a finding, this script checks whether
# the cited file or directory paths still exist on HEAD. A finding whose subject
# has been deleted or reverted is immortal — "re-evaluate next cycle" is a no-op
# on an absent path. This check closes those findings without burning LLM tokens.
#
# Env:
#   ISSUE_TITLE  — the issue title string
#   ISSUE_BODY   — the issue body text (may be multiline)
#
# Output (stdout, exit 0 always):
#   STALE <path> [<path>...]  — all extracted paths absent from HEAD
#   PRESENT                   — at least one extracted path exists on HEAD
#   NO_PATHS                  — no file/directory paths extractable
#
# Path extraction (in order of precedence):
#   1. Body field  **File:** <path>:<line>  (structured agent output)
#   2. Title convention  [agent] <path>:<line> — <description>
#
# "Stale" means ALL cited paths are absent — a finding with any surviving
# path is still actionable (line drift does not make a finding stale).
# A finding with no extractable paths is a vague finding; ADR-0031 owns it.

set -uo pipefail

TITLE="${ISSUE_TITLE:-}"
BODY="${ISSUE_BODY:-}"

# strip_line_number <raw> — strips a trailing :<digits> suffix that may be a
# single line, a range, or a comma-separated list (#508): "src/auth/session.js:42",
# "triage-scan.yml:390-391", and "claude-implementer-reusable.yml:252,381,467"
# all become the bare file path. A directory like "src/auth/" is returned unchanged.
strip_line_number() {
  local raw="$1"
  if [[ "$raw" =~ ^(.+):[0-9]+([,-][0-9]+)*$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$raw"
  fi
}

paths=()

# --- Primary: body **File:** field ---
# Matches lines of the form:  **File:** src/auth/session.js:42
# Case-insensitive on "File" to tolerate minor agent output variation.
while IFS= read -r line; do
  if [[ "$line" =~ \*\*[Ff]ile:\*\*[[:space:]]*([^[:space:]]+) ]]; then
    raw="${BASH_REMATCH[1]}"
    # Strip at most one trailing punctuation char that may close a sentence
    # (e.g. "...at src/foo.js:42." or "...at src/foo.js:42,")
    # Using % (shortest suffix) not %% (longest) so file extensions are safe.
    raw="${raw%[,.)]}"
    [[ -z "$raw" ]] && continue
    p="$(strip_line_number "$raw")"
    [[ -n "$p" ]] && paths+=("$p")
  fi
done <<< "$BODY"

# --- Fallback: title convention [agent] <path>:<line> — description ---
# Only fires when the body extraction found nothing.
if [[ ${#paths[@]} -eq 0 && -n "$TITLE" ]]; then
  # e.g., "[code-reviewer] src/auth/session.js:42 — null check missing"
  if [[ "$TITLE" =~ ^\[[^]]+\][[:space:]]+([^[:space:]]+) ]]; then
    raw="${BASH_REMATCH[1]}"
    # Require a slash — otherwise it's a symbol name, not a file path
    if [[ "$raw" == */* ]]; then
      p="$(strip_line_number "$raw")"
      [[ -n "$p" ]] && paths+=("$p")
    fi
  fi
fi

# --- Deduplicate ---
declare -A _seen
unique_paths=()
for p in "${paths[@]}"; do
  if [[ -z "${_seen[$p]+x}" ]]; then
    _seen["$p"]=1
    unique_paths+=("$p")
  fi
done

if [[ ${#unique_paths[@]} -eq 0 ]]; then
  echo "NO_PATHS"
  exit 0
fi

# --- Existence check against HEAD (current working tree checkout) ---
absent=()
for p in "${unique_paths[@]}"; do
  # #266: the path comes from attacker-influenceable issue content. Only probe
  # repo-relative paths — reject absolute paths and `..` traversal so crafted
  # content can't probe the CI runner filesystem. A suspicious path is treated
  # as present (not added to absent), so it can never drive a stale auto-close.
  case "$p" in /*|*..*) continue ;; esac
  if [[ ! -e "$p" ]]; then
    absent+=("$p")
  fi
done

# Any path that still exists → not stale
if [[ ${#absent[@]} -lt ${#unique_paths[@]} ]]; then
  echo "PRESENT"
  exit 0
fi

# All paths absent → stale
echo "STALE ${absent[*]}"
exit 0
