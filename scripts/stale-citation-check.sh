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
#   REPO         — optional; when set (e.g. "jaetill/ai-teacher"), checks path
#                  existence via the GitHub API (GET /repos/{REPO}/contents/{path})
#                  instead of the local filesystem. Required for fleet-repo issues
#                  whose checkout is not present locally. Omit for platform-repo
#                  issues where the working tree is the platform checkout.
#                  Uses GH_TOKEN from the environment for API authentication.
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
REPO="${REPO:-}"

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

# --- Deduplicate and cap ---
# Cap at 20 paths: an issue with more cited paths than this is anomalous and
# could exhaust the GitHub API rate limit (5 000 req/hr) if many crafted issues
# are scanned in one fleet pass.
declare -A _seen
unique_paths=()
for p in "${paths[@]}"; do
  if [[ ${#unique_paths[@]} -ge 20 ]]; then
    break
  fi
  if [[ -z "${_seen[$p]+x}" ]]; then
    _seen["$p"]=1
    unique_paths+=("$p")
  fi
done

if [[ ${#unique_paths[@]} -eq 0 ]]; then
  echo "NO_PATHS"
  exit 0
fi

# --- Existence check ---
# #266: reject absolute paths, '..' traversal, and URL meta-characters from
# attacker-influenceable issue content. Suspicious paths are treated as present
# so they never drive a stale auto-close.
#
# When REPO is set, check existence via the GitHub API (fleet-repo issues are
# not checked out locally, so a -e test would always be false). When REPO is
# unset/empty, check the local working tree (platform-repo issues, which are
# correctly checked out in the triage runner).
if [[ -n "$REPO" && ! "$REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.+-]+$ ]]; then
  echo "PRESENT"
  exit 0
fi

absent=()
for p in "${unique_paths[@]}"; do
  if [[ "$p" == /* || "$p" == *..* || "$p" == *'?'* || "$p" == *'#'* || "$p" == *'&'* || "$p" == *'%'* ]]; then
    continue
  fi
  if [[ -n "$REPO" ]]; then
    # Fleet-repo path: the platform checkout does not contain fleet-repo files.
    # Use the GitHub contents API; only a true HTTP 404 means absent. Other
    # non-zero exits (rate limit, network error, expired token) are treated as
    # present to avoid false stale auto-closes.
    # gh api emits "HTTP 404: Not Found (…)" on stderr for missing paths.
    api_err=$(gh api "repos/$REPO/contents/$p" 2>&1 >/dev/null)
    api_exit=$?
    if [[ $api_exit -ne 0 && "$api_err" == *"HTTP 404"* ]]; then
      absent+=("$p")
    fi
  else
    # Platform-repo path: check the local working tree at HEAD.
    if [[ ! -e "$p" ]]; then
      absent+=("$p")
    fi
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
