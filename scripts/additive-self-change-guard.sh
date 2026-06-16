#!/usr/bin/env bash
# additive-self-change-guard.sh — deterministic CAPABILITY-DELTA classifier for
# the merge-time firewall (ADR-0047, generalizing ADR-0032). Decides whether a
# green, reviewed implementer PR may AUTO-merge (no human) or must be HELD for
# human ratification. Consumed by the auto-merge gate in triage-scan.yml
# (ADR-0021/0023/0039); never relies on an agent's self-assessment or an
# LLM-applied `compositional-self-change` label.
#
# Principle (ADR-0047): a human ratifies CAPABILITY EXPANSION and CONTROL
# WEAKENING, not change structure. A change HOLDS iff it (1) touches the
# gate/governance machinery, (2) carries guardrail vocabulary on an added or
# removed line (control weakening / self-mod), (3) is a destructive/irreversible
# data migration, or (4) exceeds the blast-radius backstop cap. Everything else
# — additive guards, additive columns, SHA-pins, cosmetic/doc/agent-logic
# changes — is IN_LANE and ships when green.
#
# Inputs (env):
#   CHANGED_FILES  newline-separated list of files changed by the PR
#   DIFF           unified diff (git diff) of the PR — added/removed lines
#   SIZE_CAP       max changed (added+removed) content lines (default 400)
#
# Output: one verdict line. Exit 0 = IN_LANE (does NOT block auto-merge);
#         exit 1 = HOLD (route to human via hold:compositional).
#
# FAIL CLOSED: any ambiguity holds. A missed denylist term is the dangerous
# failure, so the path list and vocabulary denylist are deliberately broad;
# the pin carve-out is the one narrow positive exception (re-pinning an existing
# action is safe even when its name contains a denylisted token like "token").
set -uo pipefail
cap="${SIZE_CAP:-400}"

# (1) Gate / governance machinery — the firewall's own surfaces. Any changed
# file here is a compositional self-change requiring human ratification. These
# paths exist in the platform repo; app-repo PRs do not match them and sail
# through on the additive lane.
GATE_MACHINERY='^\.github/workflows/(triage-scan|claude-implementer.*|urgent-poll|pr-review|claude-pr-review|iac-guard|intake-steward|deploy-prod|emergency-deploy|validate-platform|security-scan)\.yml$|^scripts/.*guard.*\.sh$|^scripts/intake-steward\.sh$|^scripts/fleet-inflight\.sh$|^scripts/configure-.*protection.*|^(\.github/)?CODEOWNERS$|^docs/adr/|^docs/standards/|^plugins/ai-team/agents/(triage-bot|architect|security-reviewer)\.md$'

# (2) Guardrail vocabulary — control-weakening / self-modification surface
# (ADR-0032 denylist, extended with check-disabling terms). IAM/IaC risk is NOT
# judged here — it is owned by the ADR-0035 iac-additive-guard (tofu-plan based),
# which runs as its own gate; grepping HCL here would wrongly hold additive IAM
# tightenings.
DENY='FLEET_MAX|scope[ _-]?cap|scope:iac|severity calibrat|severity:|auto[ -]?merge|compositional|self-change|competence|ratif|human[ -]?(origin|merge|ratif)|author_association|\bOWNER\b|origin:|permission|secret|token|bypassPermission|force-?merge|admin-?merge|plan-approved|ready-for-implementer|claude-(sonnet|opus|haiku)|model tier|FLEET_TOKEN|--add-label|continue-on-error|if: ?false'

added_lines()   { printf '%s\n' "$DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+'; }
removed_lines() { printf '%s\n' "$DIFF" | grep -E '^-'  | grep -Ev '^---'; }
changed_content() { printf '%s\n' "$DIFF" | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' | grep -Ev '^[+-][[:space:]]*$'; }

# --- (1) gate / governance machinery -----------------------------------------
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if printf '%s' "$f" | grep -Eq "$GATE_MACHINERY"; then
    echo "HOLD: gate/governance machinery ($f) — capability/control surface (ADR-0047)"; exit 1
  fi
done <<< "$CHANGED_FILES"

# --- (4) destructive / irreversible data migration ----------------------------
if added_lines | grep -Eiq '\bDROP[[:space:]]+(TABLE|COLUMN)\b|ALTER[[:space:]]+TABLE.*DROP|\bTRUNCATE\b|DELETE[[:space:]]+FROM[[:space:]]+[^;]+;[[:space:]]*$'; then
  echo "HOLD: destructive/irreversible data migration (ADR-0003/0047)"; exit 1
fi

# --- pure re-pin carve-out ----------------------------------------------------
# If every changed CONTENT line is a `uses: …@ref` action reference, a comment,
# or whitespace, AND no net-new action identity is introduced (every added
# action owner/repo also appears removed — a ref change, not a new dependency),
# the change is a safe SHA-pin. Skip the vocabulary denylist (action names like
# create-github-app-token would otherwise false-hold on "token").
is_pure_repin() {
  local nonpin
  nonpin=$(changed_content | grep -Ev '^[+-][[:space:]]*(#|(- )?uses:[[:space:]]*[^[:space:]]+@[^[:space:]]+[[:space:]]*$)' | grep -c . || true)
  [[ "$nonpin" -ne 0 ]] && return 1
  # net-new action identity check (strip @ref, compare added vs removed sets)
  local added_act removed_act newact
  added_act=$(added_lines   | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u)
  removed_act=$(removed_lines | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u)
  newact=$(comm -23 <(printf '%s\n' "$added_act") <(printf '%s\n' "$removed_act") | grep -c . || true)
  [[ "$newact" -eq 0 ]]
}

# --- (2) guardrail vocabulary (skipped only for a pure re-pin) ----------------
if is_pure_repin; then
  echo "IN_LANE: pure action re-pin (no net-new dependency)"; exit 0
fi

# (3b) net-new external action = new dependency/egress (ADR-0003 new-external-dep).
net_new_action=$(comm -23 \
  <(added_lines   | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u) \
  <(removed_lines | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u) \
  | grep -c . || true)
if [[ "$net_new_action" -gt 0 ]]; then
  echo "HOLD: net-new external action — new dependency/egress (ADR-0003/0047)"; exit 1
fi

# (M1) Any non-pin change to a workflow file holds. GATE_MACHINERY above is a
# positive enumeration; an unlisted or future workflow (ci-health.yml,
# release.yml, …) could otherwise auto-merge and, e.g., suppress fleet-health
# signal. Pure re-pins already returned IN_LANE above; every other change that
# touches .github/workflows/ holds for a human.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" =~ ^\.github/workflows/.*\.ya?ml$ ]]; then
    echo "HOLD: workflow edit ($f) — non-pin CI/automation change (ADR-0047)"; exit 1
  fi
done <<< "$CHANGED_FILES"

# (M2) Removal of a safety control-flow/pragma is a control weakening the
# vocabulary denylist would miss (a deleted `set -e`/`set -o errexit`, an
# `exit 1`, or a removed guard). Hold on removal; additive hardening is fine.
if removed_lines | grep -Eq 'set[[:space:]]+-e([[:space:]]|$)|set[[:space:]]+-o[[:space:]]+errexit|\berrexit\b|\bexit[[:space:]]+[1-9]'; then
  echo "HOLD: removes a safety pragma/guard (set -e / exit) — control weakening (ADR-0047)"; exit 1
fi

hits=$(changed_content | grep -Eic "$DENY" || true)
if [[ "$hits" -gt 0 ]]; then
  echo "HOLD: guardrail vocabulary on a changed line — control/capability delta (ADR-0047)"; exit 1
fi

# --- (3) blast-radius backstop cap -------------------------------------------
changed=$(changed_content | grep -c . || true)
if [[ "$changed" -gt "$cap" ]]; then
  echo "HOLD: size — $changed changed lines > backstop cap $cap (human glance)"; exit 1
fi

echo "IN_LANE: capability-neutral change ($changed changed lines)"; exit 0
