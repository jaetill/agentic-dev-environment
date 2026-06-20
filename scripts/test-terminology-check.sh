#!/usr/bin/env bash
# Unit tests for terminology-check.sh
# Usage: bash scripts/test-terminology-check.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/terminology-check.sh"
pass=0; fail=0

run() {
  local label="$1" expected_exit="$2"; shift 2
  local actual_exit=0
  eval "$@" > /dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" ]]; then
    echo "  PASS: $label"; pass=$((pass+1))
  else
    echo "  FAIL: $label — expected exit $expected_exit, got $actual_exit"; fail=$((fail+1))
  fi
}

# Temp workspace that mimics a repo root.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.github/workflows"
mkdir -p "$TMP/scripts"
mkdir -p "$TMP/plugins/ai-team/agents"
mkdir -p "$TMP/infra/ops-cockpit"
mkdir -p "$TMP/templates/_shared/terraform-modules/iam-github-oidc"
mkdir -p "$TMP/docs"

# The strings written to temp files contain a deprecated term intentionally —
# we are testing that the checker catches it in .tf files.
# terminology-check: deprecated-app-claude-ok-here
DEPRECATED_TERM='app/claude'

echo "== clean workspace =="
run "empty workspace exits 0" 0 "cd \"$TMP\" && bash \"$SCRIPT\""

echo "== deprecated term in infra tf =="
# terminology-check: deprecated-app-claude-ok-here
echo "# old auth via $DEPRECATED_TERM" > "$TMP/infra/ops-cockpit/main.tf"
run "deprecated term in infra/.tf exits 1" 1 "cd \"$TMP\" && bash \"$SCRIPT\""
rm "$TMP/infra/ops-cockpit/main.tf"

echo "== deprecated term in templates tf =="
# terminology-check: deprecated-app-claude-ok-here
echo "github_app = \"$DEPRECATED_TERM\"" > "$TMP/templates/_shared/terraform-modules/iam-github-oidc/main.tf"
run "deprecated term in templates/_shared/.tf exits 1" 1 "cd \"$TMP\" && bash \"$SCRIPT\""
rm "$TMP/templates/_shared/terraform-modules/iam-github-oidc/main.tf"

echo "== deprecated term only in non-operational file =="
# terminology-check: deprecated-app-claude-ok-here
echo "# history: used $DEPRECATED_TERM before ADR-0041" > "$TMP/docs/history.md"
run "deprecated term in non-operational doc exits 0" 0 "cd \"$TMP\" && bash \"$SCRIPT\""
rm "$TMP/docs/history.md"

echo "== inline exception suppresses violation =="
# terminology-check: deprecated-app-claude-ok-here
printf '# terminology-check: deprecated-app-claude-ok-here\ngithub_app = "%s"\n' "$DEPRECATED_TERM" \
  > "$TMP/infra/ops-cockpit/main.tf"
run "inline exception in tf exits 0" 0 "cd \"$TMP\" && bash \"$SCRIPT\""
rm "$TMP/infra/ops-cockpit/main.tf"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
