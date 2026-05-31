#!/usr/bin/env bash
# additive-self-change-guard.sh — deterministic classifier for the ADR-0032
# additive self-change auto-lane. Decides whether an implementer PR that
# touches the loop's own agent definitions may AUTO-merge (no human), or must
# be held for human ratification. Consumed by the auto-merge gate in
# triage-scan.yml (ADR-0021/0023); never relies on an agent's self-assessment.
#
# Inputs (env):
#   CHANGED_FILES     newline-separated list of files changed by the PR
#   DIFF              unified diff (git diff) of the PR — added/removed lines
#   HAS_AGENT_QUALITY "true" if the PR's linked issue carries `agent-quality`
#   SIZE_CAP          max changed lines (default 8)
#
# Output: prints one classification line; exit 0 = does NOT block auto-merge
# (NOT_SELF_CHANGE or IN_LANE); exit 1 = OUT_OF_LANE → hold for human.
#
# The denylist below is the calibration surface (ADR-0032): conservative by
# design — over-blocking routes to a human (safe); a missed guardrail term is
# the dangerous failure, so keep it broad. Structural limits (one non-rail
# agent file, size cap, agent-quality origin) bound the blast radius even if
# the denylist is imperfect.
set -uo pipefail
cap="${SIZE_CAP:-8}"
RAIL_ENFORCERS='triage-bot architect'
DENY='FLEET_MAX|scope[ _-]?cap|scope:iac|severity calibrat|severity:|auto[ -]?merge|compositional|self-change|competence|ratif|human[ -]?(origin|merge|ratif)|author_association|\bOWNER\b|origin:|permission|secret|token|bypassPermission|force-?merge|admin-?merge|plan-approved|ready-for-implementer|claude-(sonnet|opus|haiku)|model tier|FLEET_TOKEN|--add-label'

agent_files=()
other=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" =~ ^plugins/ai-team/agents/[^/]+\.md$ ]]; then agent_files+=("$f"); else other=1; fi
done <<< "$CHANGED_FILES"

# Not a self-change at all → guard does not apply.
if [[ ${#agent_files[@]} -eq 0 ]]; then echo "NOT_SELF_CHANGE"; exit 0; fi

# Rule 1: exactly one agent file, nothing else.
if [[ ${#agent_files[@]} -ne 1 || $other -ne 0 ]]; then
  echo "OUT_OF_LANE: scope — must touch exactly one agent file and nothing else"; exit 1; fi

af="${agent_files[0]}"
base="$(basename "$af" .md)"
# Rule 1b: not a rail-enforcer (promoter / architect).
for r in $RAIL_ENFORCERS; do
  if [[ "$base" == "$r" ]]; then echo "OUT_OF_LANE: rail-enforcer ($base) — always human-ratified"; exit 1; fi
done

# Rule 4: agent-quality origin.
if [[ "${HAS_AGENT_QUALITY:-false}" != "true" ]]; then
  echo "OUT_OF_LANE: origin — PR does not close an agent-quality issue"; exit 1; fi

# Rule 2: size cap over changed (added+removed) content lines.
changed=$(printf '%s\n' "$DIFF" | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' | grep -Evc '^[+-][[:space:]]*$')
if [[ "$changed" -gt "$cap" ]]; then
  echo "OUT_OF_LANE: size — $changed changed lines > cap $cap"; exit 1; fi

# Rule 3: guardrail denylist over added AND removed content lines (content,
# not presence — a modification is a delete + an add in git).
hits=$(printf '%s\n' "$DIFF" | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' | grep -Eic "$DENY" || true)
if [[ "$hits" -gt 0 ]]; then
  echo "OUT_OF_LANE: guardrail vocabulary in a changed line"; exit 1; fi

echo "IN_LANE: $af ($changed changed lines)"; exit 0
