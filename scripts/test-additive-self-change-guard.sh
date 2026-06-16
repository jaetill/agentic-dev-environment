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

g() { CHANGED_FILES="$1" DIFF="${2:-}" bash "$GUARD"; }

echo "== (1) gate / governance machinery HOLDS =="
run "auto-merger workflow → HOLD" "HOLD: gate/governance" \
  "g '.github/workflows/triage-scan.yml' '+  echo changed'"
run "ADR doc → HOLD" "HOLD: gate/governance" \
  "g 'docs/adr/0021-autonomous-merge.md' '+text'"
run "standards doc → HOLD" "HOLD: gate/governance" \
  "g 'docs/standards/10-ai-workflows.md' '+text'"
run "the guard script itself → HOLD" "HOLD: gate/governance" \
  "g 'scripts/additive-self-change-guard.sh' '+text'"
run "intake-steward → HOLD" "HOLD: gate/governance" \
  "g 'scripts/intake-steward.sh' '+text'"
run "rail-enforcer agent (architect) → HOLD" "HOLD: gate/governance" \
  "g 'plugins/ai-team/agents/architect.md' '+text'"
run "CODEOWNERS → HOLD" "HOLD: gate/governance" \
  "g 'CODEOWNERS' '+* @jaetill'"
run "mixed: app source + one ADR → HOLD" "HOLD: gate/governance" \
  "g \$'src/index.ts\ndocs/adr/0003-ci-cd.md' '+text'"

echo "== (2) control-weakening vocabulary HOLDS =="
run "non-rail agent + auto-merge vocab → HOLD" "HOLD: guardrail vocabulary" \
  "g 'plugins/ai-team/agents/doc-keeper.md' '+auto-merge eligibility loosened'"
run "disabling a check (continue-on-error) → HOLD" "HOLD: guardrail vocabulary" \
  "g 'app/foo.ts' '+    continue-on-error: true'"
# IAM/IaC risk is owned by the ADR-0035 iac-additive-guard, not this guard:
# an additive IAM change passes here (IN_LANE) and is judged by the IaC gate.
run "additive IAM (tighten) is not held here → IN_LANE" "IN_LANE" \
  "g 'infra/iam.tf' '+  Action = \"s3:GetObject\"'"

echo "== (3) destructive migration HOLDS =="
run "DROP COLUMN → HOLD" "HOLD: destructive" \
  "g 'migrations/003.sql' '+ALTER TABLE courses DROP COLUMN owner_email;'"
run "DROP TABLE → HOLD" "HOLD: destructive" \
  "g 'migrations/004.sql' '+DROP TABLE sessions;'"

echo "== (3b) net-new external action HOLDS =="
run "added new third-party action → HOLD" "HOLD: net-new external action" \
  "g '.github/workflows/docs.yml' '+      - uses: some/new-action@abc123'"

echo "== pin carve-out IN_LANE =="
run "re-pin token-named action (same identity) → IN_LANE" "IN_LANE: pure action re-pin" \
  "g '.github/workflows/iac-drift-detect.yml' \$'-      - uses: actions/create-github-app-token@v1\n+      - uses: actions/create-github-app-token@abc1234'"

echo "== capability-neutral changes IN_LANE =="
run "ordinary app source → IN_LANE" "IN_LANE" \
  "g 'src/handler.ts' '+  return ok();'"
run "additive ownership column + WHERE scope → IN_LANE" "IN_LANE" \
  "g \$'app/api/courses/route.ts\nmigrations/005.sql' \$'+ALTER TABLE courses ADD COLUMN owner_email text;\n+  .where(eq(courses.ownerEmail, session.email))'"
run "non-rail agent small additive (no vocab) → IN_LANE" "IN_LANE" \
  "g 'plugins/ai-team/agents/doc-keeper.md' '+Always include a one-line summary.'"
run "cosmetic README → IN_LANE" "IN_LANE" \
  "g 'README.md' '+typo fix'"

echo "== blast-radius backstop =="
big=$(printf '+line\n%.0s' {1..405})
run "oversized diff → HOLD (size)" "HOLD: size" \
  "SIZE_CAP=400 CHANGED_FILES='app/big.ts' DIFF=\"\$big\" bash \"\$GUARD\""

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
