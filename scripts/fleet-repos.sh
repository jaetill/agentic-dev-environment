#!/usr/bin/env bash
# fleet-repos.sh — THE single source of truth for "what is the fleet?".
#
# Prints the fleet repo NAMES (space-separated) on stdout, resolved IN REAL TIME
# from the GitHub repo topic `fleet`: every non-list-hardcoded repo under $OWNER
# that carries the `fleet` topic is a fleet member. To add/remove a repo from the
# fleet, add/remove its `fleet` topic — do NOT edit a list anywhere (#139, #39).
#
# AUTHZ GATE — fleet membership requires BOTH conditions (#555):
#   1. Live `fleet` topic on the repo (controls timing — resolves to latest state).
#   2. Entry in scripts/fleet-manifest.json committed to the platform repo
#      (controls authorization — gated by CODEOWNERS + branch-protection review).
# A repo owner with write access to a non-fleet repo cannot self-enroll by setting
# the topic alone; the manifest requires a reviewed platform PR. To add a repo to
# the fleet: add the topic AND add the repo name to fleet-manifest.json in a PR.
#
# Why the topic and not `gh search repos --topic`: the search index lags MINUTES
# behind a topic change. `gh repo list --json repositoryTopics` is the live REST
# view, so a freshly-tagged repo is fleet-resolved on the very next cycle.
#
# FAIL CLOSED — this is GATE MACHINERY. If the topic query errors, returns ZERO
# repos, the manifest is missing/unreadable/empty, or the authorized intersection
# is empty, this script prints NOTHING to stdout, emits a ::warning:: to stderr,
# and exits 3.
#
#   CALLERS MUST TREAT A NON-ZERO EXIT AS "DO NOTHING THIS CYCLE" — never as an
#   empty fleet. An empty roster fed to the dispatch throttle would count 0
#   in-flight runs across 0 repos and OVER-DISPATCH without bound. A roster we
#   cannot resolve is a roster we must not act on.
#
# Env:
#   OWNER           org/user owner (default: jaetill)
#   FLEET_MANIFEST  path to the JSON allowlist (default: fleet-manifest.json
#                   in the same directory as this script)
# Output: space-separated fleet repo names on stdout (empty on failure).
# Exit:   0 = resolved — stdout is the authoritative roster (>=1 repo).
#         3 = could NOT resolve (query error, zero repos, unreadable/empty
#             manifest, or empty authorized intersection) — fail closed.
set -uo pipefail
OWNER="${OWNER:-jaetill}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_MANIFEST="${FLEET_MANIFEST:-${SCRIPT_DIR}/fleet-manifest.json}"

# --- 1. Load the allowlist from the committed manifest ---
if [[ ! -f "$FLEET_MANIFEST" ]]; then
  echo "::warning::fleet-repos: fleet-manifest.json not found at $FLEET_MANIFEST — fail closed" >&2
  exit 3
fi
manifest_repos="$(jq -r '.repos[]' "$FLEET_MANIFEST" 2>/dev/null)" || {
  echo "::warning::fleet-repos: could not parse fleet-manifest.json — fail closed" >&2
  exit 3
}
if [[ -z "$manifest_repos" ]]; then
  echo "::warning::fleet-repos: fleet-manifest.json repos list is empty — fail closed" >&2
  exit 3
fi

# --- 2. Live topic query ---
topic_repos="$(
  gh repo list "$OWNER" --limit 100 --json name,repositoryTopics \
    --jq '.[] | select((.repositoryTopics // []) | map(.name) | index("fleet")) | .name' \
    2>/dev/null
)" || {
  echo "::warning::fleet-repos: could not resolve topic:fleet roster — fail closed" >&2
  exit 3
}
if [[ -z "$topic_repos" ]]; then
  echo "::warning::fleet-repos: topic:fleet query returned zero repos — fail closed" >&2
  exit 3
fi

# --- 3. Cross-validate: keep only repos present in BOTH the topic query AND the manifest ---
intersection=""
while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  if echo "$manifest_repos" | grep -qx "$repo"; then
    intersection="${intersection:+$intersection }$repo"
  fi
done <<< "$topic_repos"

if [[ -z "$intersection" ]]; then
  echo "::warning::fleet-repos: no repos authorized by both topic:fleet and fleet-manifest.json — fail closed" >&2
  exit 3
fi

echo "$intersection"
