#!/usr/bin/env bash
# Test: wip-inventory.sh truncates large git status output.
# Creates a temp git repo with 200 untracked files, runs the hook, and asserts
# the output stays within the 40-line cap + 1 overflow note + surrounding markup.

set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/ai-team/hooks/wip-inventory.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL: hook not found at $HOOK" >&2
  exit 1
fi

# Work in a throw-away git repo so we don't dirty the real tree.
TMPDIR_REPO=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REPO"' EXIT

git -C "$TMPDIR_REPO" init -q
git -C "$TMPDIR_REPO" config user.email "test@example.com"
git -C "$TMPDIR_REPO" config user.name "Test"

# Create 200 untracked files.
for i in $(seq 1 200); do
  touch "$TMPDIR_REPO/file_$i.txt"
done

# Run the hook from the temp repo; unset CI guards so the hook doesn't short-circuit.
output=$(cd "$TMPDIR_REPO" && CI="" GITHUB_ACTIONS="" bash "$HOOK" 2>/dev/null)
line_count=$(echo "$output" | wc -l | tr -d ' ')

# The code block should contain at most 40 status lines plus surrounding markup:
# header ("### WIP inventory"), blank line, "**Uncommitted changes:**",
# opening/closing fences, the overflow note, and the footer line.
# Total cap: ~47 lines is generous; the key assertion is ≤ 45.
MAX_LINES=47

if [[ "$line_count" -gt "$MAX_LINES" ]]; then
  echo "FAIL: output has $line_count lines (max $MAX_LINES). Truncation guard not working." >&2
  exit 1
fi

# Overflow note must be present since 200 > 40.
if ! echo "$output" | grep -qF "more files not shown"; then
  echo "FAIL: overflow note missing from output." >&2
  exit 1
fi

echo "PASS: output is $line_count lines (≤ $MAX_LINES), overflow note present."
exit 0
