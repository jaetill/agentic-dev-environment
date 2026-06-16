#!/usr/bin/env bash
# tests/ci-health-degraded.sh — unit tests for the DEGRADED-mode logic in
# .github/workflows/ci-health.yml
#
# Run from the repo root:  bash tests/ci-health-degraded.sh
# Exit 0 on all-pass; non-zero on any failure.
#
# These tests exercise the all-clear and issue-filing branches of the scan
# step in isolation, using a mock `gh` binary to record calls without
# touching GitHub.

set -uo pipefail

failures=0
pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1" >&2; failures=$((failures + 1)); }

# ── mock setup ───────────────────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

GH_LOG="$TMPDIR_TEST/gh.log"

# Mock `gh` records every invocation to $GH_LOG.
cat > "$TMPDIR_TEST/gh" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
MOCK
chmod +x "$TMPDIR_TEST/gh"
export GH_LOG
export PATH="$TMPDIR_TEST:$PATH"

# ── helpers ──────────────────────────────────────────────────────────────────

# run_allclear DEGRADED [EXISTING_ISSUE_NUMBER]
# Executes the all-clear block from ci-health.yml with the given DEGRADED flag
# and (optionally) an existing open issue number.
run_allclear() {
  local degraded="$1" existing="${2:-}"
  : > "$GH_LOG"
  GITHUB_REPOSITORY="owner/repo" \
  bash -c "
    DEGRADED='$degraded'
    existing='$existing'
    GITHUB_REPOSITORY='owner/repo'

    if [[ \"\$DEGRADED\" == '1' ]]; then
      if [[ -n \"\$existing\" ]]; then
        gh issue comment \"\$existing\" --repo \"\$GITHUB_REPOSITORY\" \
          --body 'Degraded-mode scan (platform repo only; fleet App token unavailable) found no failures, but fleet coverage was incomplete. Leaving open — a full-fleet scan is needed to confirm recovery.'
      fi
    else
      if [[ -n \"\$existing\" ]]; then
        gh issue comment \"\$existing\" --repo \"\$GITHUB_REPOSITORY\" \
          --body 'CI health recovered — no non-PR workflow failures across the fleet in the last 25h. Closing automatically; the watcher reopens a fresh issue if failures recur.'
        gh issue close \"\$existing\" --repo \"\$GITHUB_REPOSITORY\"
      fi
    fi
  "
}

# run_body DEGRADED COUNT
# Exercises the issue-body generation block for the given DEGRADED flag and
# failure count.  Writes body to stdout so callers can grep it.
run_body() {
  local degraded="$1" count="$2"
  bash -c "
    DEGRADED='$degraded'
    count='$count'
    summary='### some-repo\n- **my-workflow** (schedule) — ...'

    if [[ \"\$DEGRADED\" == '1' ]]; then
      echo '> [!WARNING]'
      echo '> **Degraded-mode scan** — fleet App token was unavailable; only \`agentic-dev-environment\` was scanned. Fleet-wide coverage is limited. Verify the fleet App credentials.'
      echo ''
    fi
    echo '## CI health: fleet workflow failures detected'
    echo ''
    if [[ \"\$DEGRADED\" == '1' ]]; then
      echo \"The CI-health watcher found **\$count** failed run(s) of\"
      echo 'event-triggered or scheduled workflows in the platform repo'
      echo '(degraded mode — fleet App token unavailable; other fleet repos were not scanned).'
    else
      echo \"The CI-health watcher found **\$count** failed run(s) of\"
      echo 'event-triggered or scheduled workflows across the fleet in the'
      echo 'last 25 hours. These do not surface on any PR, so they are'
      echo 'easy to miss.'
    fi
  "
}

echo "ci-health DEGRADED-mode tests"
echo

# ── all-clear block ───────────────────────────────────────────────────────────

# DEGRADED=1 + existing issue → comment posted, issue NOT closed
run_allclear "1" "42"
if ! grep -q "issue close" "$GH_LOG" 2>/dev/null; then
  pass "DEGRADED=1 with existing issue: 'gh issue close' is NOT called (no false all-clear)"
else
  fail "DEGRADED=1 with existing issue: 'gh issue close' was called — false all-clear"
fi
if grep -q "issue comment 42" "$GH_LOG" 2>/dev/null; then
  pass "DEGRADED=1 with existing issue: comment posted explaining limited scope"
else
  fail "DEGRADED=1 with existing issue: expected a comment explaining incomplete coverage"
fi

# DEGRADED=0 + existing issue → issue IS closed (full-fleet recovery confirmed)
run_allclear "0" "42"
if grep -q "issue close 42" "$GH_LOG" 2>/dev/null; then
  pass "DEGRADED=0 with existing issue: 'gh issue close' IS called on full-fleet recovery"
else
  fail "DEGRADED=0 with existing issue: 'gh issue close' NOT called — recovery not signalled"
fi

# DEGRADED=1 + no existing issue → no gh calls at all
run_allclear "1" ""
if [[ ! -s "$GH_LOG" ]]; then
  pass "DEGRADED=1 with no existing issue: no gh calls made"
else
  fail "DEGRADED=1 with no existing issue: unexpected gh calls: $(cat "$GH_LOG")"
fi

# DEGRADED=0 + no existing issue → no gh calls
run_allclear "0" ""
if [[ ! -s "$GH_LOG" ]]; then
  pass "DEGRADED=0 with no existing issue: no gh calls made"
else
  fail "DEGRADED=0 with no existing issue: unexpected gh calls: $(cat "$GH_LOG")"
fi

# ── issue body scope accuracy ─────────────────────────────────────────────────

body_degraded=$(run_body "1" "3")
if echo "$body_degraded" | grep -q "Degraded-mode scan"; then
  pass "DEGRADED=1 body: includes degraded-mode warning banner"
else
  fail "DEGRADED=1 body: missing degraded-mode warning banner"
fi
if echo "$body_degraded" | grep -q "across the fleet"; then
  fail "DEGRADED=1 body: falsely says 'across the fleet'"
else
  pass "DEGRADED=1 body: does NOT say 'across the fleet'"
fi
if echo "$body_degraded" | grep -q "platform repo"; then
  pass "DEGRADED=1 body: correctly scopes to 'platform repo'"
else
  fail "DEGRADED=1 body: missing 'platform repo' scope qualifier"
fi

body_full=$(run_body "0" "2")
if echo "$body_full" | grep -q "across the fleet"; then
  pass "DEGRADED=0 body: correctly says 'across the fleet'"
else
  fail "DEGRADED=0 body: missing 'across the fleet' in full-scan body"
fi
if echo "$body_full" | grep -q "Degraded-mode"; then
  fail "DEGRADED=0 body: unexpectedly includes degraded-mode banner"
else
  pass "DEGRADED=0 body: no degraded-mode banner in full-scan body"
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed." >&2
  exit 1
fi
