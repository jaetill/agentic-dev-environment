#!/usr/bin/env bash
# additive-self-change-guard.sh — deterministic CAPABILITY-DELTA classifier for
# the merge-time firewall (ADR-0047, generalizing ADR-0032). Decides whether a
# green, reviewed implementer PR may AUTO-merge (no human) or must be HELD for
# human ratification. Consumed by the auto-merge gate in triage-scan.yml
# (ADR-0021/0023/0039); never relies on an agent's self-assessment or an
# LLM-applied `compositional-self-change` label.
#
# Principle (ADR-0047 / ADR-0019): the compositional firewall applies ONLY to
# the platform repo — the team's "self". App-repo changes are never self-changes
# (their risks are handled by requires-adr, the ADR-0035 IaC guard, and the
# review battery). Within the platform repo, a human ratifies CAPABILITY
# EXPANSION and CONTROL WEAKENING, not change structure.
#
# Inputs (env):
#   CHANGED_FILES  newline-separated list of files changed by the PR
#   DIFF           unified diff (git diff) of the PR — added/removed lines
#   IS_PLATFORM    "true" if the PR is in the platform (loop-self) repo.
#                  Default "true" = fail-closed (treat unknown as platform).
#   SIZE_CAP       max changed (added+removed) content lines (default 400)
#
# Output: one verdict line. Exit 0 = IN_LANE (does NOT block auto-merge);
#         exit 1 = HOLD (route to human via hold:compositional).
#
# FAIL CLOSED: any ambiguity holds — an unavailable diff (H1), a possibly
# truncated file list (H3), or unknown repo context all HOLD.
set -uo pipefail
cap="${SIZE_CAP:-400}"
is_platform="${IS_PLATFORM:-true}"

# Gate / governance machinery (platform repo only) — matched by SENSITIVITY
# PATTERN, not exact filename, so a newly-added enforcement script/workflow is
# caught without an enumeration update. Operational scripts (dreams-curate,
# backfills) and non-rail agent definitions deliberately fall outside.
GATE_MACHINERY='^\.github/workflows/(triage-scan|claude-implementer.*|urgent-poll|pr-review|claude-pr-review|iac-guard|intake-steward|deploy-prod|emergency-deploy|validate-platform|security-scan)\.yml$|^scripts/.*(guard|protection|review-gate|validate-platform|intake-steward|fleet-inflight|configure).*|^(\.github/)?CODEOWNERS$|^docs/adr/|^docs/standards/|^plugins/ai-team/(hooks|skills|commands)/|^plugins/ai-team/agents/(triage-bot|architect|security-reviewer|implementer)\.md$'

# Guardrail vocabulary — control-weakening / self-modification surface (ADR-0032
# denylist + check-disabling terms). IAM/IaC risk is owned by the ADR-0035 gate.
DENY='FLEET_MAX|scope[ _-]?cap|scope:iac|severity calibrat|severity:|auto[ -]?merge|compositional|self-change|competence|ratif|human[ -]?(origin|merge|ratif)|author_association|\bOWNER\b|origin:|permission|secret|token|bypassPermission|force-?merge|admin-?merge|plan-approved|ready-for-implementer|claude-(sonnet|opus|haiku)|model tier|FLEET_TOKEN|--add-label|continue-on-error|if: ?false'

added_lines()   { printf '%s\n' "$DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+'; }
removed_lines() { printf '%s\n' "$DIFF" | grep -E '^-'  | grep -Ev '^---'; }
changed_content() { printf '%s\n' "$DIFF" | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' | grep -Ev '^[+-][[:space:]]*$'; }

# Pure re-pin: every changed CONTENT line is a `uses: …@ref [# comment]` action
# pin or a comment, AND no net-new action identity is introduced (a ref change,
# not a new dependency). A pure pin is capability-neutral EVERYWHERE — it changes
# no logic — so it is allowed even inside gate-machinery files; this is why the
# check runs before the path gate. Safe even when an action name contains "token".
is_pure_repin() {
  local nonpin
  nonpin=$(changed_content | grep -Ev '^[+-][[:space:]]*(#|(- )?uses:[[:space:]]*[^[:space:]]+@[^[:space:]]+([[:space:]]+#.*)?[[:space:]]*$)' | grep -c . || true)
  [[ "$nonpin" -ne 0 ]] && return 1
  local added_act removed_act newact
  added_act=$(added_lines   | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u)
  removed_act=$(removed_lines | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u)
  newact=$(comm -23 <(printf '%s\n' "$added_act") <(printf '%s\n' "$removed_act") | grep -c . || true)
  [[ "$newact" -eq 0 ]]
}

# (H1) Fail closed when the diff could not be fetched but files did change —
# otherwise the empty-diff path would make is_pure_repin trivially true.
if [[ -z "${DIFF:-}" && -n "${CHANGED_FILES:-}" ]]; then
  echo "HOLD: diff unavailable — fail closed (ADR-0047)"; exit 1
fi

# --- Universal check (all repos): destructive / irreversible data migration ---
if added_lines | grep -Eiq '\bDROP[[:space:]]+(TABLE|COLUMN)\b|ALTER[[:space:]]+TABLE.*DROP|\bTRUNCATE\b|DELETE[[:space:]]+FROM[[:space:]]+[^;]+;[[:space:]]*$'; then
  echo "HOLD: destructive/irreversible data migration (ADR-0003/0047)"; exit 1
fi

# App-repo changes are never compositional self-changes (ADR-0019) — the
# firewall below is platform-only. App risks are covered by the other gates.
if [[ "$is_platform" != "true" ]]; then
  echo "IN_LANE: app-repo change (compositional firewall is platform-only)"; exit 0
fi

# (H3) Fail closed if the changed-file list may be truncated (gh caps at 100):
# a gated file beyond position 100 would be invisible to the path checks below.
nfiles=$(printf '%s\n' "$CHANGED_FILES" | grep -c . || true)
if [[ "$nfiles" -ge 100 ]]; then
  echo "HOLD: $nfiles changed files — list may be truncated, fail closed (ADR-0047)"; exit 1
fi

# Pure re-pin -> IN_LANE (capability-neutral, allowed even in gate files).
if is_pure_repin; then
  echo "IN_LANE: pure action re-pin (no net-new dependency)"; exit 0
fi

# (1) gate / governance machinery -> HOLD
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if printf '%s' "$f" | grep -Eq "$GATE_MACHINERY"; then
    echo "HOLD: gate/governance machinery ($f) — capability/control surface (ADR-0047)"; exit 1
  fi
done <<< "$CHANGED_FILES"

# (3b) net-new external action = new dependency/egress (ADR-0003).
net_new_action=$(comm -23 \
  <(added_lines   | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u) \
  <(removed_lines | grep -Eo 'uses:[[:space:]]*[^[:space:]@]+' | sed -E 's/uses:[[:space:]]*//' | sort -u) \
  | grep -c . || true)
if [[ "$net_new_action" -gt 0 ]]; then
  echo "HOLD: net-new external action — new dependency/egress (ADR-0003/0047)"; exit 1
fi

# (M1) Any non-pin workflow edit holds — GATE_MACHINERY is a positive list; an
# unlisted/new workflow could otherwise auto-merge (e.g., suppress ci-health).
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" =~ ^\.github/workflows/.*\.ya?ml$ ]]; then
    echo "HOLD: workflow edit ($f) — non-pin CI/automation change (ADR-0047)"; exit 1
  fi
done <<< "$CHANGED_FILES"

# (M2) Removal of a structural safety pragma (set -e / errexit) is a control
# weakening the vocabulary denylist would miss. Individual `exit N` removals are
# NOT flagged here — they are normal error-handling idioms whose removal has no
# structural effect on the script's failure behaviour outside that branch.
if removed_lines | grep -Eq 'set[[:space:]]+-e([[:space:]]|$)|set[[:space:]]+-o[[:space:]]+errexit|\berrexit\b'; then
  echo "HOLD: removes a safety pragma/guard (set -e / errexit) — control weakening (ADR-0047)"; exit 1
fi

# (2) guardrail vocabulary on any changed line -> HOLD
hits=$(changed_content | grep -Eic "$DENY" || true)
if [[ "$hits" -gt 0 ]]; then
  echo "HOLD: guardrail vocabulary on a changed line — control/capability delta (ADR-0047)"; exit 1
fi

# (4) blast-radius backstop cap -> HOLD
changed=$(changed_content | grep -c . || true)
if [[ "$changed" -gt "$cap" ]]; then
  echo "HOLD: size — $changed changed lines > backstop cap $cap (human glance)"; exit 1
fi

echo "IN_LANE: capability-neutral change ($changed changed lines)"; exit 0
