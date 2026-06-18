#!/usr/bin/env bash
# tests/dreams-curate-path-check.sh — unit tests for path-containment logic in scripts/dreams-curate.sh
#
# Run from the repo root:  bash tests/dreams-curate-path-check.sh
# Exit 0 on all-pass; non-zero on any failure.

set -uo pipefail

failures=0
pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1" >&2; failures=$((failures + 1)); }

# Replicate the path-containment check from scripts/dreams-curate.sh lines 166-171
check_path() {
  local MEMORY_DIR="$1" mem_path="$2"
  local out_path="$MEMORY_DIR/${mem_path#/}"
  local real_out
  real_out=$(realpath -m "$out_path")
  [[ "$real_out" == "$MEMORY_DIR/"* ]]
}

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT
MEMORY_DIR="$TMPDIR_BASE/memory"
mkdir "$MEMORY_DIR"

echo "dreams-curate.sh path-containment tests"
echo

# ── valid paths — must be accepted ───────────────────────────────────────────

if check_path "$MEMORY_DIR" "/foo.md"; then
  pass "simple file under MEMORY_DIR is accepted"
else
  fail "simple file under MEMORY_DIR should be accepted"
fi

if check_path "$MEMORY_DIR" "/subdir/bar.md"; then
  pass "nested file under MEMORY_DIR is accepted"
else
  fail "nested file under MEMORY_DIR should be accepted"
fi

# ── path traversal — must be rejected ────────────────────────────────────────

# mem_path = "/../.github/workflows/evil.yml"
# ${mem_path#/} → "../.github/workflows/evil.yml"
# resolves to $TMPDIR_BASE/.github/workflows/evil.yml — outside MEMORY_DIR
if ! check_path "$MEMORY_DIR" "/../.github/workflows/evil.yml"; then
  pass "single ../ after leading-slash strip is rejected"
else
  fail "single ../ after leading-slash strip should be rejected"
fi

# mem_path = "/../../.github/workflows/evil.yml"
# ${mem_path#/} → "../../.github/workflows/evil.yml"
# out_path literally starts with $MEMORY_DIR/ but resolves outside — the
# simple string check (without realpath) would be bypassed; this test ensures
# realpath-based check catches it.
if ! check_path "$MEMORY_DIR" "/../../.github/workflows/evil.yml"; then
  pass "deep ../../ traversal (simple-string-check bypass vector) is rejected"
else
  fail "deep ../../ traversal should be rejected"
fi

# Embedded traversal: /foo/../../.github/workflows/evil.yml
if ! check_path "$MEMORY_DIR" "/foo/../../.github/workflows/evil.yml"; then
  pass "embedded ../ traversal resolving outside MEMORY_DIR is rejected"
else
  fail "embedded ../ traversal resolving outside MEMORY_DIR should be rejected"
fi

# Traversal that stays within MEMORY_DIR depth but exits it
if ! check_path "$MEMORY_DIR" "/foo/../../../outside.md"; then
  pass "traversal exiting MEMORY_DIR via multiple levels is rejected"
else
  fail "traversal exiting MEMORY_DIR via multiple levels should be rejected"
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed." >&2
  exit 1
fi
