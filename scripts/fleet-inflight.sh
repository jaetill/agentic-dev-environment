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
#   FLEET_REPOS  space-separated repo names (default: the 8 fleet repos)
#   OWNER        org/user owner (default: jaetill)
# Output: the integer in-flight count on stdout (partial count on a read error).
# Exit:   0 = fully counted — stdout is authoritative.
#         3 = a repo read failed — caller MUST FAIL OPEN (never drop work on a
#             transient API error). stdout is the best-effort partial count.
set -uo pipefail
OWNER="${OWNER:-jaetill}"
FLEET_REPOS="${FLEET_REPOS:-game-night-pwa meal-planner ai-teacher jaetill-portal splendor draft carto agentic-dev-environment}"

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
