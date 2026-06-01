#!/usr/bin/env bash
# iac-auto-merge-guard.sh — deterministic classifier for the ADR-0035 safe-additive
# IaC auto-merge lane. Decides whether a machine-origin `scope:iac` implementer PR
# may AUTO-merge (and thus auto-apply on dev via the push:[main] deploy cascade),
# or must be HELD for a human. Run as the `iac-additive-guard` PR check; the central
# auto-merge gate (triage-scan.yml) requires this check green for scope:iac PRs.
#
# It classifies the `tofu show -json <plan>` OUTPUT — machine-emitted, not the
# agent's prose. The agent cannot fake a plan JSON without actually planning, and
# the guard runs as an independent CI step, preserving writer != approver.
#
# Input:  $1 = path to plan JSON (tofu show -json tfplan), or PLAN_JSON env path.
# Output: prints one classification line.
#         exit 0 = IN_LANE  (safe to auto-merge)
#         exit 1 = HOLD     (route to a human)
#
# Predicates (ALL must hold for IN_LANE):
#   1. No destroys/replaces — every action is a subset of {create,update,no-op,read}.
#      Any `delete` (standalone or as part of a replace) -> HOLD.
#   2. Within cap — at most 5 *substantive* resource changes (no-op/read excluded),
#      matching the iac-implementer's own scope cap.
#   3. No exposure — no planned resource opens a public/blast-radius hole:
#      SG ingress 0.0.0.0/0 or ::/0, S3 public ACL / disabled public-access-block,
#      IAM Allow Action:* on Resource:*, or a plaintext secret-ish value.
#
# Conservative by design: any ambiguity, parse error, or missing plan -> HOLD
# (a human is the safe fallback). The destructive-change-detector categories
# (security-relevant/schema/new-external-dep) are enforced upstream as labels in
# the gate and the agent's own ADR-pairing rule; this script enforces the
# plan-shape half (predicates 1-3).
set -uo pipefail

plan="${1:-${PLAN_JSON:-}}"
if [[ -z "$plan" || ! -f "$plan" ]]; then
  echo "HOLD: no plan JSON found (expected \$1 or PLAN_JSON path)"; exit 1
fi
if ! jq -e . "$plan" >/dev/null 2>&1; then
  echo "HOLD: plan JSON is not valid JSON"; exit 1
fi

CAP="${IAC_RESOURCE_CAP:-5}"

# -- Predicate 1: no destroys / replaces -------------------------------------
if jq -e '[.resource_changes[]?.change.actions[]?] | any(. == "delete")' "$plan" >/dev/null 2>&1; then
  echo "HOLD: plan contains a delete/replace — destroys and replacements are human-only"; exit 1
fi

# -- Predicate 2: substantive-change cap -------------------------------------
substantive=$(jq '[.resource_changes[]? | select((.change.actions != ["no-op"]) and (.change.actions != ["read"]))] | length' "$plan")
if [[ "$substantive" -gt "$CAP" ]]; then
  echo "HOLD: $substantive substantive resource changes > cap $CAP"; exit 1
fi

# -- Predicate 3: exposure scan over the planned `after` of every change ------
# Security groups: any ingress (inline block or rule resource) open to the world.
sg_open=$(jq '
  [ .resource_changes[]?
    | select(.type | test("security_group"))
    | (.change.after // {})
    | (.ingress // []) + ([.])
    | .. | strings
  ] | any(. == "0.0.0.0/0" or . == "::/0")
' "$plan" 2>/dev/null || echo "true")
if [[ "$sg_open" == "true" ]]; then
  echo "HOLD: a security group ingress opens to 0.0.0.0/0 or ::/0"; exit 1
fi

# S3 public access: public ACL, or a public-access-block that disables a guard.
s3_public=$(jq '
  [ .resource_changes[]? | (.change.after // {}) |
    ( (.acl // "") | test("public-read"; "i") ),
    ( .block_public_acls == false ),
    ( .block_public_policy == false ),
    ( .ignore_public_acls == false ),
    ( .restrict_public_buckets == false )
  ] | any(. == true)
' "$plan" 2>/dev/null || echo "true")
if [[ "$s3_public" == "true" ]]; then
  echo "HOLD: an S3 resource is made public (public ACL or disabled public-access-block)"; exit 1
fi

# IAM wildcard: an Allow statement granting Action:* on Resource:*.
iam_star=$(jq '
  def stmts: ( (.. | objects | select(has("Statement")) | .Statement) // empty );
  def norm($v): ($v | if type=="array" then . else [.] end);
  [ .resource_changes[]? | (.change.after // {})
    | ( .policy // .assume_role_policy // .inline_policy // empty )
    | ( if type=="string" then (try fromjson catch {}) else . end )
    | stmts | (if type=="array" then .[] else . end)
    | select((.Effect // "") == "Allow")
    | (norm(.Action // []) | any(. == "*")) and (norm(.Resource // []) | any(. == "*"))
  ] | any(. == true)
' "$plan" 2>/dev/null || echo "true")
if [[ "$iam_star" == "true" ]]; then
  echo "HOLD: an IAM policy grants Action:* on Resource:* (Allow)"; exit 1
fi

# Plaintext secret-ish: a non-sensitive string value under a secret-y key that is
# not an interpolation/reference (those resolve to refs, not literals, in plan).
secret_plain=$(jq '
  [ .resource_changes[]? | (.change.after // {}) | to_entries[]?
    | select(.key | test("password|secret|private_key|access_key|token"; "i"))
    | select(.value | type == "string")
    | select(.value | length > 0)
    | select(.value | test("\\$\\{|^var\\.|^data\\.|^aws_") | not)
  ] | length > 0
' "$plan" 2>/dev/null || echo "true")
if [[ "$secret_plain" == "true" ]]; then
  echo "HOLD: a secret-like attribute carries a plaintext value"; exit 1
fi

echo "IN_LANE: $substantive substantive change(s), additive-only, no exposure"; exit 0
