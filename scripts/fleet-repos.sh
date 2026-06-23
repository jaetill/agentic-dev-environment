#!/usr/bin/env bash
# fleet-repos.sh — THE single source of truth for "what is the fleet?".
#
# Prints the fleet repo NAMES (space-separated) on stdout, resolved from the
# COMMITTED MANIFEST at fleet/repos.txt in the platform repo. That manifest is
# the system of record for fleet membership (ADR-0051, #555): a repo is a fleet
# member IFF it is listed there. To add/remove a repo from the fleet, edit the
# manifest in a reviewed PR — git history is the admission log.
#
# Why the manifest and NOT the `fleet` repo topic (the old #139/#39 resolver,
# PR #554): membership is a CAPABILITY GRANT (FLEET_TOKEN scope, implementer
# dispatch, auto-merge). Deriving it from a repo topic moved the trust boundary
# to an unaudited repo-settings write — anyone with repo-admin on a repo could
# self-enroll by writing a topic (#555). Reading a reviewed committed file moves
# the boundary back to "merge a reviewed code change". The manifest is also more
# reliable than the topic query was: no API call, no auth, no search-index lag.
# The `fleet` topic is now a DERIVED, non-authoritative projection of this file
# (reconciled best-effort by scripts/fleet-topic-sync.sh) — never gate on it.
#
# FAIL CLOSED — this is GATE MACHINERY. If the manifest file is missing OR yields
# zero repos, this script prints NOTHING to stdout, emits a ::warning:: to
# stderr, and exits 3.
#
#   CALLERS MUST TREAT A NON-ZERO EXIT AS "DO NOTHING THIS CYCLE" — never as an
#   empty fleet. An empty roster fed to the dispatch throttle would count 0
#   in-flight runs across 0 repos and OVER-DISPATCH without bound. A roster we
#   cannot resolve is a roster we must not act on.
#
# Dependency-free: resolving the roster needs no jq/gh/python — just bash + grep.
#
# Env:
#   FLEET_MANIFEST  path to the manifest (default: fleet/repos.txt relative to
#                   this script's parent directory). Override only for testing.
# Output: space-separated fleet repo names on stdout (empty on failure).
# Exit:   0 = resolved — stdout is the authoritative roster (>=1 repo).
#         3 = could NOT resolve (manifest missing or empty) — fail closed.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_MANIFEST="${FLEET_MANIFEST:-${SCRIPT_DIR}/../fleet/repos.txt}"

# --- Read the manifest: strip comments + blank lines, normalize to one line ---
if [[ ! -f "$FLEET_MANIFEST" ]]; then
  echo "::warning::fleet-repos: could not resolve fleet manifest — fail closed" >&2
  exit 3
fi
repos="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$FLEET_MANIFEST" | tr -s '[:space:]' ' ')"
repos="${repos# }"; repos="${repos% }"
if [[ -z "$repos" ]]; then
  echo "::warning::fleet-repos: could not resolve fleet manifest — fail closed" >&2
  exit 3
fi

echo "$repos"
