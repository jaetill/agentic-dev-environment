#!/usr/bin/env bash
# Unit tests for fleet-repos.sh manifest cross-validation (#555).
# Tests the manifest-gating logic without making live GitHub API calls.
# Usage: bash scripts/test-fleet-repos.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/fleet-repos.sh"
pass=0; fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Stub gh to return a controlled topic list, bypassing the real GitHub API.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
# Stub: emit newline-separated repo names that "have" the fleet topic.
# GH_STUB_REPOS env var controls the output (space-separated → one per line).
echo "${GH_STUB_REPOS:-}" | tr ' ' '\n' | grep -v '^$' || true
EOF
chmod +x "$TMP/bin/gh"

run() {
  local label="$1" expected_exit="$2"; shift 2
  local actual_exit=0
  PATH="$TMP/bin:$PATH" eval "$@" > /dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" ]]; then
    echo "  PASS: $label"; pass=$((pass+1))
  else
    echo "  FAIL: $label — expected exit $expected_exit, got $actual_exit"; fail=$((fail+1))
  fi
}

run_stdout() {
  local label="$1" expected="$2"; shift 2
  local got
  got=$(PATH="$TMP/bin:$PATH" eval "$@" 2>/dev/null || true)
  if [[ "$got" == "$expected" ]]; then
    echo "  PASS: $label"; pass=$((pass+1))
  else
    echo "  FAIL: $label — expected '$expected', got '$got'"; fail=$((fail+1))
  fi
}

# Write a manifest with two authorized repos.
MANIFEST="$TMP/manifest.json"
cat > "$MANIFEST" << 'EOF'
{"repos": ["repo-a", "repo-b"]}
EOF

echo "== manifest missing → exit 3 =="
run "no manifest file" 3 "FLEET_MANIFEST=/nonexistent/path.json bash \"$SCRIPT\""

echo "== manifest unparseable → exit 3 =="
echo "not json" > "$TMP/bad.json"
run "bad JSON" 3 "FLEET_MANIFEST=\"$TMP/bad.json\" bash \"$SCRIPT\""

echo "== manifest empty repos list → exit 3 =="
echo '{"repos":[]}' > "$TMP/empty.json"
run "empty repos array" 3 "FLEET_MANIFEST=\"$TMP/empty.json\" bash \"$SCRIPT\""

echo "== topic query returns nothing → exit 3 =="
run "no topic repos" 3 "GH_STUB_REPOS='' FLEET_MANIFEST=\"$MANIFEST\" bash \"$SCRIPT\""

echo "== topic repos not in manifest → exit 3 =="
run "zero intersection" 3 "GH_STUB_REPOS='repo-x repo-y' FLEET_MANIFEST=\"$MANIFEST\" bash \"$SCRIPT\""

echo "== partial intersection → only manifest-authorized repos emitted =="
run_stdout "only authorized subset" "repo-a" \
  "GH_STUB_REPOS='repo-a repo-z' FLEET_MANIFEST=\"$MANIFEST\" bash \"$SCRIPT\""

echo "== full intersection → all authorized repos emitted =="
run_stdout "full authorized set" "repo-a repo-b" \
  "GH_STUB_REPOS='repo-a repo-b' FLEET_MANIFEST=\"$MANIFEST\" bash \"$SCRIPT\""

echo "== topic superset of manifest → only manifest-approved pass =="
run_stdout "manifest caps the roster" "repo-a repo-b" \
  "GH_STUB_REPOS='repo-a repo-b repo-unauthorized' FLEET_MANIFEST=\"$MANIFEST\" bash \"$SCRIPT\""

echo ""
echo "Results: $pass passed, $fail failed."
[[ $fail -eq 0 ]]
