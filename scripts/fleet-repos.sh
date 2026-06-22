#!/usr/bin/env bash
# fleet-repos.sh — THE single source of truth for "what is the fleet?".
#
# Prints the fleet repo NAMES (space-separated) on stdout, resolved IN REAL TIME
# from the GitHub repo topic `fleet`: every non-list-hardcoded repo under $OWNER
# that carries the `fleet` topic is a fleet member. To add/remove a repo from the
# fleet, add/remove its `fleet` topic — do NOT edit a list anywhere (#139, #39).
#
# Why the topic and not `gh search repos --topic`: the search index lags MINUTES
# behind a topic change. `gh repo list --json repositoryTopics` is the live REST
# view, so a freshly-tagged repo is fleet-resolved on the very next cycle.
#
# FAIL CLOSED — this is GATE MACHINERY. If the query errors OR returns ZERO repos
# (a transient API blip, an auth failure, an empty filter), this script prints
# NOTHING to stdout, emits a ::warning:: to stderr, and exits 3.
#
#   CALLERS MUST TREAT A NON-ZERO EXIT AS "DO NOTHING THIS CYCLE" — never as an
#   empty fleet. An empty roster fed to the dispatch throttle would count 0
#   in-flight runs across 0 repos and OVER-DISPATCH without bound. A roster we
#   cannot resolve is a roster we must not act on.
#
# Env:
#   OWNER  org/user owner (default: jaetill)
# Output: space-separated fleet repo names on stdout (empty on failure).
# Exit:   0 = resolved — stdout is the authoritative roster (>=1 repo).
#         3 = could NOT resolve (query error or zero repos) — fail closed.
set -uo pipefail
OWNER="${OWNER:-jaetill}"

repos="$(
  gh repo list "$OWNER" --limit 100 --json name,repositoryTopics \
    --jq '.[] | select((.repositoryTopics // []) | map(.name) | index("fleet")) | .name' \
    2>/dev/null
)" || {
  echo "::warning::fleet-repos: could not resolve topic:fleet roster — fail closed" >&2
  exit 3
}

# Normalize newline-separated names to a single space-separated line.
roster="$(echo "$repos" | tr '\n' ' ' | xargs || true)"

if [[ -z "$roster" ]]; then
  echo "::warning::fleet-repos: could not resolve topic:fleet roster — fail closed" >&2
  exit 3
fi

echo "$roster"
