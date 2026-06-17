#!/usr/bin/env bash
# Unit tests for additive-self-change-guard.sh (capability-delta guard, ADR-0047)
# Usage: bash scripts/test-additive-self-change-guard.sh
set -uo pipefail
GUARD="$(dirname "$0")/additive-self-change-guard.sh"
pass=0; fail=0

run() {
  local label="$1" expected="$2"; shift 2
  local got; got=$(eval "$@" 2>&1 || true)
  if [[ "$got" == *"$expected"* ]]; then
    echo "  PASS: $label"; pass=$((pass+1))
  else
    echo "  FAIL: $label — expected '$expected', got '$got'"; fail=$((fail+1))
  fi
}

# platform-repo context (default); gapp = app-repo context
g()    { CHANGED_FILES="$1" DIFF="${2:-x}" IS_PLATFORM="true"  bash "$GUARD"; }
gapp() { CHANGED_FILES="$1" DIFF="${2:-x}" IS_PLATFORM="false" bash "$GUARD"; }

echo "== gate / governance machinery (platform) HOLDS =="
run "auto-merger workflow → HOLD" "HOLD: gate/governance" "g '.github/workflows/triage-scan.yml' '+  echo x'"
run "ADR doc → HOLD" "HOLD: gate/governance" "g 'docs/adr/0021-autonomous-merge.md' '+t'"
run "standards doc → HOLD" "HOLD: gate/governance" "g 'docs/standards/10-ai-workflows.md' '+t'"
run "a guard script → HOLD" "HOLD: gate/governance" "g 'scripts/additive-self-change-guard.sh' '+t'"
run "validate-platform.sh (M3) → HOLD" "HOLD: gate/governance" "g 'scripts/validate-platform.sh' '+t'"
run "require-platform-review-gates.ps1 (M1) → HOLD" "HOLD: gate/governance" "g 'scripts/require-platform-review-gates.ps1' '+t'"
run "configure-branch-protection.ps1 → HOLD" "HOLD: gate/governance" "g 'scripts/configure-branch-protection.ps1' '+t'"
run "plugins hooks (H2) → HOLD" "HOLD: gate/governance" "g 'plugins/ai-team/hooks/block-destructive-bash.sh' '+t'"
run "plugins skills standard → HOLD" "HOLD: gate/governance" "g 'plugins/ai-team/skills/standards-ai-workflows/standard.md' '+t'"
run "rail-enforcer agent → HOLD" "HOLD: gate/governance" "g 'plugins/ai-team/agents/architect.md' '+t'"
run "code-reviewer agent → HOLD" "HOLD: gate/governance" "g 'plugins/ai-team/agents/code-reviewer.md' '+t'"
run "CODEOWNERS → HOLD" "HOLD: gate/governance" "g 'CODEOWNERS' '+* @x'"

echo "== control-weakening / destructive / net-new HOLDS =="
run "non-rail agent + auto-merge vocab → HOLD" "HOLD: guardrail vocabulary" "g 'plugins/ai-team/agents/doc-keeper.md' '+auto-merge eligibility loosened'"
run "continue-on-error → HOLD" "HOLD: guardrail vocabulary" "g 'app/foo.ts' '+    continue-on-error: true'"
run "DROP COLUMN (platform) → HOLD" "HOLD: destructive" "g 'migrations/003.sql' '+ALTER TABLE c DROP COLUMN x;'"
run "added new third-party action → HOLD" "HOLD: net-new external action" "g '.github/workflows/docs.yml' '+      - uses: some/new-action@abc123'"
run "non-pin workflow edit (M1) → HOLD" "HOLD: workflow edit" "g '.github/workflows/ci-health.yml' '+      run: echo suppress'"
run "removed set -e (M2) → HOLD" "HOLD: removes a safety pragma" "g 'scripts/dreams-curate.sh' '-set -e'"

echo "== H1 / H3 fail-closed HOLDS =="
run "empty diff + changed files (H1) → HOLD" "HOLD: diff unavailable" "CHANGED_FILES='src/foo.ts' DIFF='' IS_PLATFORM=true bash \"\$GUARD\""
big=$(for i in $(seq 1 105); do echo "src/f$i.ts"; done)
run "≥100 changed files (H3) → HOLD" "HOLD:" "CHANGED_FILES=\"\$big\" DIFF='+x' IS_PLATFORM=true bash \"\$GUARD\""

echo "== pin carve-out =="
run "re-pin token-named action → IN_LANE" "IN_LANE: pure action re-pin" "g '.github/workflows/iac-drift-detect.yml' \$'-      - uses: actions/create-github-app-token@v1\n+      - uses: actions/create-github-app-token@abc1234'"
run "re-pin WITH trailing version comment → IN_LANE" "IN_LANE: pure action re-pin" "g '.github/workflows/iac-drift-detect.yml' \$'-      - uses: anthropics/claude-code-action@v1\n+      - uses: anthropics/claude-code-action@deadbee # v1'"
run "pure pin inside a gate workflow → IN_LANE (capability-neutral)" "IN_LANE: pure action re-pin" "g '.github/workflows/triage-scan.yml' \$'-      - uses: x/y@v1\n+      - uses: x/y@abc1234'"
run "NON-pin edit to a gate workflow → HOLD" "HOLD: gate/governance" "g '.github/workflows/triage-scan.yml' '+        run: echo logic change'"

echo "== app-repo: compositional firewall does NOT apply =="
run "app workflow edit → IN_LANE" "app-repo change" "gapp '.github/workflows/deploy.yml' '+      run: echo deploy'"
run "app scripts/ change → IN_LANE" "app-repo change" "gapp 'scripts/backfill-owner-email.ts' '+await db.update()'"
run "app additive ownership column → IN_LANE" "app-repo change" "gapp \$'app/api/courses/route.ts\nmigrations/005.sql' '+ALTER TABLE courses ADD COLUMN owner_email text;'"
run "app DESTRUCTIVE migration still → HOLD (universal)" "HOLD: destructive" "gapp 'migrations/006.sql' '+DROP TABLE sessions;'"

echo "== capability-neutral (platform) IN_LANE =="
run "ordinary platform doc → IN_LANE" "IN_LANE" "g 'README.md' '+typo'"
run "non-rail agent small additive → IN_LANE" "IN_LANE" "g 'plugins/ai-team/agents/doc-keeper.md' '+Always include a one-line summary.'"
run "operational script hardening (adds set -e) → IN_LANE" "IN_LANE" "g 'scripts/dreams-curate.sh' '+set -e'"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
