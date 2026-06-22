#!/usr/bin/env bash
# fleet-inflight.sh — single source of truth for the ADR-0030 fleet-wide dispatch
# throttle. Prints the number of ACTIVELY RUNNING implementer dispatches
# (in_progress + queued claude-implementer.yml runs) across the whole fleet.
# All three dispatch paths (windowed promoter, event-dispatch, urgent-poll) call
# this so they share ONE budget against FLEET_MAX_DISPATCH — closing the loophole
# where the windowed promoter used a per-run batch cap and ignored in-flight work.
#
# Counting in-flight RUNS (not open PRs) is deliberate: an open PR is
# done-and-awaiting-merge and must not consume a dispatch slot (ADR-0030).
#
# Env:
#   FLEET_REPOS  space-separated repo names. Default: resolved from the
#                committed manifest (fleet/repos.txt) via scripts/fleet-repos.sh
#                (ADR-0051) — no hardcoded list. Override only for testing.
#   OWNER        org/user owner (default: jaetill)
# Output: the integer in-flight count on stdout (partial count on a read error).
# Exit:   0 = fully counted — stdout is authoritative.
#         3 = a repo read failed — caller MUST FAIL OPEN (never drop work on a
#             transient API error). stdout is the best-effort partial count.
set -uo pipefail
OWNER="${OWNER:-jaetill}"
FLEET_REPOS="${FLEET_REPOS:-$(OWNER="$OWNER" bash "$(dirname "$0")/fleet-repos.sh")}"

# FAIL CLOSED on an UNRESOLVABLE roster. If fleet-repos.sh could not resolve the
# fleet (it printed nothing / exited non-zero), FLEET_REPOS is EMPTY here. This
# is the THROTTLE: an empty roster would count 0 in-flight runs and let callers
# OVER-DISPATCH without bound. So emit a sentinel that exceeds ANY cap and exit
# 0 — callers read in-flight=99999 >= cap and dispatch NOTHING this cycle.
# (Distinct from the per-repo read-error path below, which legitimately fails
# OPEN with a partial count on a transient single-repo API blip.)
if [[ -z "${FLEET_REPOS// }" ]]; then
  echo "::warning::fleet-inflight: empty fleet roster (manifest unresolved) — emitting over-cap sentinel to fail closed (no dispatch)" >&2
  echo 99999
  exit 0
fi

inflight=0
for r in $FLEET_REPOS; do
  n=$(gh run list --repo "${OWNER}/${r}" --workflow=claude-implementer.yml --limit 50 \
        --json status \
        --jq '[.[] | select(.status == "in_progress" or .status == "queued")] | length' 2>/dev/null) \
    || { echo "$inflight"; exit 3; }
  # Guard against non-numeric output — treat anything unexpected as 0.
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  inflight=$((inflight + n))
done
echo "$inflight"
