#!/usr/bin/env bash
# tests/dreams-curate.sh — unit tests for the null out_store guard in scripts/dreams-curate.sh
#
# Run from the repo root:  bash tests/dreams-curate.sh
# Exit 0 on all-pass; non-zero on any failure.

set -uo pipefail

failures=0

pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1" >&2; failures=$((failures + 1)); }

echo "dreams-curate.sh — out_store null-guard tests"
echo

# ── jq extraction: verify null/empty when outputs has no memory_store ────────

RESP_EMPTY_OUTPUTS='{"id":"dream_1","status":"completed","outputs":[]}'
out_store=$(jq -r 'first(.outputs[] | select(.type == "memory_store")).memory_store_id' <<< "$RESP_EMPTY_OUTPUTS")
if [[ -z "$out_store" || "$out_store" == "null" ]]; then
  pass "jq: empty outputs array → out_store is null/empty (guard would trigger)"
else
  fail "jq: expected null/empty for empty outputs, got '$out_store'"
fi

RESP_WRONG_TYPE='{"id":"dream_1","status":"completed","outputs":[{"type":"session_summary","session_id":"s_abc"}]}'
out_store=$(jq -r 'first(.outputs[] | select(.type == "memory_store")).memory_store_id' <<< "$RESP_WRONG_TYPE")
if [[ -z "$out_store" || "$out_store" == "null" ]]; then
  pass "jq: no memory_store in outputs → out_store is null/empty (guard would trigger)"
else
  fail "jq: expected null/empty for missing memory_store type, got '$out_store'"
fi

RESP_WITH_STORE='{"id":"dream_1","status":"completed","outputs":[{"type":"memory_store","memory_store_id":"ms_abc123"}]}'
out_store=$(jq -r 'first(.outputs[] | select(.type == "memory_store")).memory_store_id' <<< "$RESP_WITH_STORE")
if [[ -n "$out_store" && "$out_store" != "null" ]]; then
  pass "jq: valid memory_store output → out_store extracted correctly ($out_store)"
else
  fail "jq: expected non-null store id, got '$out_store'"
fi

# ── guard blocks file deletion when out_store is null or empty ───────────────

TMPDIR_TEST=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

touch "$TMPDIR_TEST/feedback_testing.md"
touch "$TMPDIR_TEST/user_role.md"

# Inline simulation of the guard + deletion (mirrors scripts/dreams-curate.sh lines 144-148)
simulate_guard() {
  local out_store="$1"
  local mem_dir="$2"

  if [[ -z "$out_store" || "$out_store" == "null" ]]; then
    return 1  # guard fires → would exit 1 in the real script
  fi
  # Guard passed → simulate deletion
  rm -f "$mem_dir"/*.md
  return 0
}

# null → guard fires, files preserved
if ! simulate_guard "null" "$TMPDIR_TEST"; then
  if [[ -f "$TMPDIR_TEST/feedback_testing.md" && -f "$TMPDIR_TEST/user_role.md" ]]; then
    pass "guard: null out_store aborts before deletion — memory files preserved"
  else
    fail "guard: null out_store triggered guard but files were deleted"
  fi
else
  fail "guard: null out_store should have triggered guard but did not"
fi

# empty → guard fires, files preserved
if ! simulate_guard "" "$TMPDIR_TEST"; then
  if [[ -f "$TMPDIR_TEST/feedback_testing.md" && -f "$TMPDIR_TEST/user_role.md" ]]; then
    pass "guard: empty out_store aborts before deletion — memory files preserved"
  else
    fail "guard: empty out_store triggered guard but files were deleted"
  fi
else
  fail "guard: empty out_store should have triggered guard but did not"
fi

# valid store id → guard passes, deletion runs
if simulate_guard "ms_abc123" "$TMPDIR_TEST"; then
  if [[ ! -f "$TMPDIR_TEST/feedback_testing.md" && ! -f "$TMPDIR_TEST/user_role.md" ]]; then
    pass "guard: valid out_store passes — deletion proceeds as expected"
  else
    fail "guard: valid out_store passed but deletion did not run"
  fi
else
  fail "guard: valid out_store should pass through guard but was blocked"
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed." >&2
  exit 1
fi
