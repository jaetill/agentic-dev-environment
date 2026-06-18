#!/usr/bin/env bash
# tests/dreams-curate.sh — unit tests for scripts/dreams-curate.sh
#
# Run from the repo root:  bash tests/dreams-curate.sh
# Exit 0 on all-pass; non-zero on any failure.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/dreams-curate.sh"
failures=0

pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1" >&2; failures=$((failures + 1)); }

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
MOCK_BIN="$WORK_DIR/bin"
MOCK_MEM="$WORK_DIR/memory"
mkdir -p "$MOCK_BIN" "$MOCK_MEM"
echo "# test memory entry" > "$MOCK_MEM/test.md"

echo "dreams-curate.sh tests"
echo

# ── exits non-zero when memory-store creation returns HTTP error ─────────────
# Mirrors what happens when the POST /memory_stores endpoint returns 5xx:
# curl -f exits 22, and with set -e the script must exit before the upload loop.

cat > "$MOCK_BIN/curl" << 'CURLEOF'
#!/usr/bin/env bash
# Mock curl: access-check GET returns 200; any POST exits 22 (curl -f on 5xx).
args=" $* "
if [[ "$args" == *" -o /dev/null "* ]]; then
  echo "200"
  exit 0
fi
if [[ "$args" == *" -X POST "* ]]; then
  exit 22
fi
echo "{}"
exit 0
CURLEOF
chmod +x "$MOCK_BIN/curl"

output=$(PATH="$MOCK_BIN:$PATH" ANTHROPIC_API_KEY=test MEMORY_DIR="$MOCK_MEM" bash "$SCRIPT" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "script exits non-zero when memory-store POST fails (set -e catches curl exit 22)"
else
  fail "expected non-zero exit when memory-store POST fails, got 0; output: $output"
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed." >&2
  exit 1
fi
