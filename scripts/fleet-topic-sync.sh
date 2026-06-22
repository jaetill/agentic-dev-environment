#!/usr/bin/env bash
# fleet-topic-sync.sh — best-effort reconciler for the DERIVED `fleet` topic.
#
# The `fleet` GitHub topic is a non-authoritative PROJECTION of the system of
# record, fleet/repos.txt (ADR-0051, #555). The manifest grants capability; the
# topic is cosmetic — it only feeds dashboards / `gh search`. This script
# reconciles the topic to match the manifest:
#   - every repo IN the manifest gets the `fleet` topic added (if missing);
#   - every owner repo that CARRIES the `fleet` topic but is NOT in the manifest
#     gets it removed.
#
# BEST-EFFORT — never a gate. Writing a repo topic requires repo-admin. If a
# topic write fails (insufficient permission, transient error, etc.) this script
# emits a ::warning:: and CONTINUES; it does NOT exit non-zero on a topic-write
# failure. A stale topic is harmless (cosmetic) and must never break the loop.
# The only authoritative reader is fleet-repos.sh, which reads the manifest, not
# the topic.
#
# Requires: gh (authenticated; repo-admin on the owner's repos for writes to
# succeed). Reads the manifest via scripts/fleet-repos.sh.
#
# Env:
#   OWNER  org/user owner (default: jaetill)
# Exit:   0 always, UNLESS the manifest itself is unresolvable (then non-zero
#         from fleet-repos.sh — there is nothing to reconcile against).
set -uo pipefail
OWNER="${OWNER:-jaetill}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the authoritative roster. If this fails (fail-closed exit 3) there is
# no manifest to reconcile against — propagate the failure.
manifest_repos="$(bash "$SCRIPT_DIR/fleet-repos.sh")" || {
  echo "::warning::fleet-topic-sync: could not resolve fleet manifest — nothing to sync" >&2
  exit 3
}

# --- 1. Ensure every manifest repo carries the `fleet` topic ---
for r in $manifest_repos; do
  if gh repo edit "$OWNER/$r" --add-topic fleet >/dev/null 2>&1; then
    echo "::notice::fleet-topic-sync: ensured topic on $OWNER/$r"
  else
    echo "::warning::fleet-topic-sync: could not add topic to $OWNER/$r (needs repo-admin?) — continuing"
  fi
done

# --- 2. Remove the `fleet` topic from any owner repo NOT in the manifest ---
# Enumerate owner repos that currently carry the topic; subtract the manifest.
topic_repos="$(
  gh repo list "$OWNER" --limit 200 --json name,repositoryTopics \
    --jq '.[] | select((.repositoryTopics // []) | map(.name) | index("fleet")) | .name' \
    2>/dev/null
)" || {
  echo "::warning::fleet-topic-sync: could not list owner repos to prune stale topics — skipping prune" >&2
  topic_repos=""
}

for r in $topic_repos; do
  in_manifest=false
  for m in $manifest_repos; do
    [[ "$r" == "$m" ]] && { in_manifest=true; break; }
  done
  if [[ "$in_manifest" == false ]]; then
    if gh repo edit "$OWNER/$r" --remove-topic fleet >/dev/null 2>&1; then
      echo "::notice::fleet-topic-sync: removed stale topic from $OWNER/$r (not in manifest)"
    else
      echo "::warning::fleet-topic-sync: could not remove stale topic from $OWNER/$r (needs repo-admin?) — continuing"
    fi
  fi
done

echo "fleet-topic-sync: reconciliation complete (best-effort)."
exit 0
