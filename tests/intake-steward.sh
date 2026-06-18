#!/usr/bin/env bash
# tests/intake-steward.sh — unit tests for scripts/intake-steward.sh
# Run from the repo root: bash tests/intake-steward.sh
# Exit 0 on all-pass; non-zero on any failure.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/intake-steward.sh"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

failures=0
pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1" >&2; failures=$((failures + 1)); }

echo "intake-steward.sh tests"
echo

CALL_LOG="$TMPDIR_TEST/calls.log"
MOCK_BIN="$TMPDIR_TEST/gh"

# setup_mock_gh <issue_json> <after_labels>
# Writes a fake 'gh' binary that:
#   - returns a single fake repo
#   - returns <issue_json> for page=1 of the issues API, [] for subsequent pages
#   - returns <after_labels> for the per-issue verify read
#   - records 'gh issue edit ...' calls to CALL_LOG
setup_mock_gh() {
  local data_dir="$TMPDIR_TEST"
  printf '%s' "$1" >"$data_dir/issue.json"
  printf '%s' "$2" >"$data_dir/after_labels.txt"
  cat >"$MOCK_BIN" <<MOCK
#!/usr/bin/env bash
case "\$1" in
  repo)
    echo "fakerepo"
    ;;
  api)
    case "\$2" in
      repos/testowner/fakerepo/issues/1)
        cat "${data_dir}/after_labels.txt"; echo ;;
      repos/testowner/fakerepo/issues\?*)
        if [[ "\$2" == *"&page=1"* ]]; then
          cat "${data_dir}/issue.json"; echo
        else
          echo "[]"
        fi ;;
      *)
        echo "MOCK unhandled api \$2" >&2; exit 1 ;;
    esac ;;
  label) exit 0 ;;
  issue) echo "\$*" >>"${CALL_LOG}" ;;
  *) echo "MOCK unhandled: \$1" >&2; exit 1 ;;
esac
MOCK
  chmod +x "$MOCK_BIN"
}

run_steward() {
  MODE=full OWNER=testowner MAINTAINERS=maintaineruser \
    PATH="$TMPDIR_TEST:$PATH" \
    bash "$SCRIPT" 2>/dev/null
}

# ── Test 1: maintainer-filed verification issue, no prior labels ─────────────
echo "── maintainer verification filing, no existing labels ──"
> "$CALL_LOG"
setup_mock_gh \
  '[{"number":1,"user":{"login":"maintaineruser","type":"User"},"labels":[],"title":"Verify the auth flow"}]' \
  'approved|type:investigation|origin:human'

output=$(run_steward)

edit_call=$(grep "^issue edit" "$CALL_LOG" 2>/dev/null || true)
if [[ -z "$edit_call" ]]; then
  fail "no gh issue edit call recorded"
else
  if [[ "$edit_call" == *"--add-label approved"* ]]; then
    pass "approved label added"
  else
    fail "expected --add-label approved; got: $edit_call"
  fi
  if [[ "$edit_call" != *"--add-label needs-formulation"* ]]; then
    pass "needs-formulation NOT added"
  else
    fail "needs-formulation must not be added alongside approved; got: $edit_call"
  fi
fi
# surfaced counter must not be incremented for auto-approved issues
if [[ "$output" == *"surfaced=0"* ]]; then
  pass "surfaced counter not incremented"
else
  fail "expected surfaced=0; got: $output"
fi

echo

# ── Test 2: maintainer-filed NON-verification issue, no prior labels ─────────
# Regression: the label-bare-maintainer path must still add needs-formulation
# for issues that are not verification tasks.
echo "── maintainer non-verification filing, no existing labels ──"
> "$CALL_LOG"
setup_mock_gh \
  '[{"number":1,"user":{"login":"maintaineruser","type":"User"},"labels":[],"title":"Fix the login page"}]' \
  'needs-formulation|origin:human'

run_steward >/dev/null

edit_call=$(grep "^issue edit" "$CALL_LOG" 2>/dev/null || true)
if [[ "$edit_call" == *"--add-label needs-formulation"* ]]; then
  pass "needs-formulation still added for non-verification maintainer issue"
else
  fail "expected --add-label needs-formulation for non-verification maintainer filing; got: $edit_call"
fi

echo

# ── Test 3: non-maintainer verification filing ───────────────────────────────
# Non-maintainer verification issues still need human formulation.
echo "── non-maintainer verification filing ──"
> "$CALL_LOG"
setup_mock_gh \
  '[{"number":1,"user":{"login":"outsider","type":"User"},"labels":[],"title":"Verify the payment flow"}]' \
  'needs-formulation|type:investigation|origin:human'

run_steward >/dev/null

edit_call=$(grep "^issue edit" "$CALL_LOG" 2>/dev/null || true)
if [[ "$edit_call" == *"--add-label needs-formulation"* ]]; then
  pass "needs-formulation added for non-maintainer verification filing"
else
  fail "expected --add-label needs-formulation for non-maintainer; got: $edit_call"
fi
if [[ "$edit_call" != *"--add-label approved"* ]]; then
  pass "approved NOT added for non-maintainer verification filing"
else
  fail "approved must not be added for non-maintainer filing; got: $edit_call"
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed." >&2
  exit 1
fi
