#!/usr/bin/env bash
# tests/stale-citation-check.sh — unit tests for scripts/stale-citation-check.sh
#
# Run from the repo root:  bash tests/stale-citation-check.sh
# Exit 0 on all-pass; non-zero on any failure.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/stale-citation-check.sh"
failures=0

pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1" >&2; failures=$((failures + 1)); }

run() {
  local title="$1" body="$2"
  ISSUE_TITLE="$title" ISSUE_BODY="$body" bash "$SCRIPT"
}

echo "stale-citation-check.sh tests"
echo

# ── NO_PATHS ────────────────────────────────────────────────────────────────

out="$(run "General issue title" "No file reference here.")"
if [[ "$out" == "NO_PATHS" ]]; then
  pass "NO_PATHS: body with no **File:** field and title with no path"
else
  fail "NO_PATHS: expected 'NO_PATHS', got '$out'"
fi

out="$(run "[code-reviewer] missing-slash-no-path — something" "")"
if [[ "$out" == "NO_PATHS" ]]; then
  pass "NO_PATHS: title path token with no slash is ignored"
else
  fail "NO_PATHS: title without slash should produce NO_PATHS, got '$out'"
fi

# ── PRESENT: file exists ─────────────────────────────────────────────────────

# Use a file we know exists in every checkout of this repo
REAL_FILE="scripts/stale-citation-check.sh"

out="$(run "irrelevant" "**File:** ${REAL_FILE}:10")"
if [[ "$out" == "PRESENT" ]]; then
  pass "PRESENT: body **File:** path that exists on HEAD"
else
  fail "PRESENT: expected 'PRESENT' for existing path, got '$out'"
fi

out="$(run "[code-reviewer] ${REAL_FILE}:10 — something" "")"
if [[ "$out" == "PRESENT" ]]; then
  pass "PRESENT: title convention path that exists on HEAD"
else
  fail "PRESENT: expected 'PRESENT' for title path that exists, got '$out'"
fi

# Mixed: one present + one absent → PRESENT (any surviving path = not stale)
out="$(run "x" "$(printf '**File:** %s:1\n**File:** src/__deleted__/gone.ts:9' "$REAL_FILE")")"
if [[ "$out" == "PRESENT" ]]; then
  pass "PRESENT: mixed present+absent paths → PRESENT"
else
  fail "PRESENT: mixed paths should yield PRESENT, got '$out'"
fi

# ── STALE: file absent ───────────────────────────────────────────────────────

GONE="src/auth/session.js"

out="$(run "irrelevant" "**File:** ${GONE}:42")"
if [[ "$out" == "STALE ${GONE}" ]]; then
  pass "STALE: body **File:** path that does not exist → STALE <path>"
else
  fail "STALE: expected 'STALE ${GONE}', got '$out'"
fi

out="$(run "[security-reviewer] ${GONE}:99 — something" "")"
if [[ "$out" == "STALE ${GONE}" ]]; then
  pass "STALE: title convention path that does not exist → STALE <path>"
else
  fail "STALE: expected 'STALE ${GONE}' from title, got '$out'"
fi

# Directory citation (no line number)
GONE_DIR="src/game/"
out="$(run "x" "**File:** ${GONE_DIR}")"
if [[ "$out" == "STALE ${GONE_DIR}" ]]; then
  pass "STALE: directory citation that does not exist → STALE <path>"
else
  fail "STALE: expected 'STALE ${GONE_DIR}' for absent directory, got '$out'"
fi

# Multiple absent paths
GONE2="src/game/board.ts"
out="$(run "x" "$(printf '**File:** %s:1\n**File:** %s:2' "$GONE" "$GONE2")")"
if [[ "$out" == STALE* ]]; then
  pass "STALE: multiple absent paths all reported"
else
  fail "STALE: expected STALE for two absent paths, got '$out'"
fi

# ── Case-insensitive **file:** ───────────────────────────────────────────────

out="$(run "x" "**file:** ${GONE}:1")"
if [[ "$out" == "STALE ${GONE}" ]]; then
  pass "STALE: lowercase **file:** is recognised"
else
  fail "STALE: lowercase **file:** should be recognised, got '$out'"
fi

# ── Line-range annotations (path:N-M) ────────────────────────────────────────

# Existing file cited with a range should be PRESENT (regression from issue #386)
out="$(run "x" "**File:** ${REAL_FILE}:10-20")"
if [[ "$out" == "PRESENT" ]]; then
  pass "PRESENT: body **File:** with line-range (path:N-M) that exists on HEAD"
else
  fail "PRESENT: expected 'PRESENT' for existing path with line-range, got '$out'"
fi

out="$(run "[code-reviewer] ${REAL_FILE}:390-391 — something" "")"
if [[ "$out" == "PRESENT" ]]; then
  pass "PRESENT: title convention path with line-range that exists on HEAD"
else
  fail "PRESENT: expected 'PRESENT' for title path with line-range, got '$out'"
fi

# Absent file with range → STALE, path stripped of range
out="$(run "x" "**File:** ${GONE}:390-391")"
if [[ "$out" == "STALE ${GONE}" ]]; then
  pass "STALE: body **File:** absent path with line-range → STALE bare path"
else
  fail "STALE: expected 'STALE ${GONE}' for absent path with line-range, got '$out'"
fi

# ── Trailing punctuation strip ────────────────────────────────────────────────

# Trailing comma after an existing path (e.g. "path/a.md, path/b.md" → first token has comma)
out="$(run "x" "**File:** ${REAL_FILE},")"
if [[ "$out" == "PRESENT" ]]; then
  pass "PRESENT: trailing comma after existing path is stripped"
else
  fail "PRESENT: expected 'PRESENT' for path with trailing comma, got '$out'"
fi

# Trailing period after an absent path → STALE with bare path
out="$(run "x" "**File:** ${GONE}.")"
if [[ "$out" == "STALE ${GONE}" ]]; then
  pass "STALE: trailing period after absent path is stripped → STALE bare path"
else
  fail "STALE: expected 'STALE ${GONE}' for absent path with trailing period, got '$out'"
fi

# ── API mode (REPO set) ────────────────────────────────────────────────────
# These tests require GH_TOKEN (set in CI by the Actions context). Skip when
# running locally without credentials rather than hard-failing.

echo
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "  ⚠️  API mode tests skipped — GH_TOKEN not set"
else
  echo "API mode tests (REPO=jaetill/agentic-dev-environment)"

  run_api() {
    local title="$1" body="$2"
    REPO="jaetill/agentic-dev-environment" ISSUE_TITLE="$title" ISSUE_BODY="$body" bash "$SCRIPT"
  }

  # Path that exists in the repo → PRESENT via API
  out="$(run_api "irrelevant" "**File:** ${REAL_FILE}:10")"
  if [[ "$out" == "PRESENT" ]]; then
    pass "API PRESENT: path that exists in fleet repo returns PRESENT"
  else
    fail "API PRESENT: expected 'PRESENT' via API for existing path, got '$out'"
  fi

  # Path that does not exist in the repo → STALE via API
  out="$(run_api "irrelevant" "**File:** ${GONE}:42")"
  if [[ "$out" == "STALE ${GONE}" ]]; then
    pass "API STALE: path absent from fleet repo returns STALE"
  else
    fail "API STALE: expected 'STALE ${GONE}' via API for absent path, got '$out'"
  fi

  # Title convention with API mode
  out="$(run_api "[code-reviewer] ${REAL_FILE}:10 — something" "")"
  if [[ "$out" == "PRESENT" ]]; then
    pass "API PRESENT: title convention path that exists in fleet repo"
  else
    fail "API PRESENT: expected 'PRESENT' via API for title path, got '$out'"
  fi

  # Mixed present+absent → PRESENT via API
  out="$(run_api "x" "$(printf '**File:** %s:1\n**File:** %s:9' "$REAL_FILE" "$GONE")")"
  if [[ "$out" == "PRESENT" ]]; then
    pass "API PRESENT: mixed present+absent paths → PRESENT via API"
  else
    fail "API PRESENT: mixed paths should yield PRESENT via API, got '$out'"
  fi

  # Regression guard: REPO unset → local filesystem still works
  out="$(run "irrelevant" "**File:** ${REAL_FILE}:10")"
  if [[ "$out" == "PRESENT" ]]; then
    pass "Filesystem fallback: REPO unset still checks local working tree"
  else
    fail "Filesystem fallback: expected 'PRESENT' from local check, got '$out'"
  fi
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed." >&2
  exit 1
fi
