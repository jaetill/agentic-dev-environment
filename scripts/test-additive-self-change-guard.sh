#!/usr/bin/env bash
# Unit tests for additive-self-change-guard.sh
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

g() { CHANGED_FILES="$1" DIFF="${2:-}" HAS_AGENT_QUALITY="${3:-false}" bash "$GUARD"; }

echo "== ADR-0023 compositional-path guard =="
run "standards doc → OUT_OF_LANE" "OUT_OF_LANE: compositional-path" \
  "g 'docs/standards/10-ai-workflows.md'"
run "ADR doc → OUT_OF_LANE" "OUT_OF_LANE: compositional-path" \
  "g 'docs/adr/0021-autonomous-merge.md'"
run "workflow file → OUT_OF_LANE" "OUT_OF_LANE: compositional-path" \
  "g '.github/workflows/triage-scan.yml'"
run "non-agent ai-team file → OUT_OF_LANE" "OUT_OF_LANE: compositional-path" \
  "g 'plugins/ai-team/hooks/inject-context.sh'"
run "scripts guard file → OUT_OF_LANE" "OUT_OF_LANE: compositional-path" \
  "g 'scripts/additive-self-change-guard.sh'"
run "mixed: source + standards doc → OUT_OF_LANE" "OUT_OF_LANE: compositional-path" \
  "g $'src/index.ts\ndocs/standards/01-source-control.md'"
run "ordinary source file → NOT_SELF_CHANGE" "NOT_SELF_CHANGE" \
  "g 'src/handler.ts'"
run "agent file alone passes to ADR-0032 (no agent-quality) → origin error" "OUT_OF_LANE: origin" \
  "g 'plugins/ai-team/agents/doc-keeper.md' '' false"

echo "== ADR-0032 additive self-change lane =="
run "agent file + agent-quality + small diff → IN_LANE" "IN_LANE:" \
  "g 'plugins/ai-team/agents/doc-keeper.md' '+add required summary field' true"
run "rail-enforcer agent → OUT_OF_LANE" "OUT_OF_LANE: rail-enforcer" \
  "g 'plugins/ai-team/agents/triage-bot.md' '+add required field' true"
run "agent + guardrail denylist hit → OUT_OF_LANE" "OUT_OF_LANE: guardrail" \
  "g 'plugins/ai-team/agents/doc-keeper.md' '+auto-merge eligibility check' true"
run "agent + two files → OUT_OF_LANE: scope" "OUT_OF_LANE: scope" \
  "g $'plugins/ai-team/agents/doc-keeper.md\nplugins/ai-team/agents/code-reviewer.md' '+add field' true"

echo "== bash safety pragma removal guard (issue #415) =="
run "script .sh removes set -e → OUT_OF_LANE" "OUT_OF_LANE: bash safety pragma" \
  "g 'bin/deploy.sh' $'-set -euo pipefail'"
run "script .sh removes set -eu → OUT_OF_LANE" "OUT_OF_LANE: bash safety pragma" \
  "g 'tools/run.sh' $'-set -eu'"
run "script .sh removes errexit → OUT_OF_LANE" "OUT_OF_LANE: bash safety pragma" \
  "g 'bin/check.sh' $'-set -o errexit'"
run "script .sh removes exit 1 → OUT_OF_LANE" "OUT_OF_LANE: bash safety pragma" \
  "g 'bin/check.sh' $'-  exit 1'"
run "script .ps1 removes exit 1 → OUT_OF_LANE" "OUT_OF_LANE: bash safety pragma" \
  "g 'tools/config.ps1' $'-  exit 1'"
run "script .sh only adds set -e (not removal) → NOT_SELF_CHANGE" "NOT_SELF_CHANGE" \
  "g 'bin/deploy.sh' $'+set -euo pipefail'"
run "non-script source file with exit(1) removal → NOT_SELF_CHANGE" "NOT_SELF_CHANGE" \
  "g 'src/handler.ts' $'-  exit(1)'"
run "agent file with set -e removal still reaches denylist path" "OUT_OF_LANE: origin" \
  "g 'plugins/ai-team/agents/doc-keeper.md' $'-set -e' false"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
