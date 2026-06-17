#!/usr/bin/env bash
# dreams-curate.sh — Weekly memory curation via Anthropic Dreams API (dreaming-2026-04-21 beta).
# Mirrors memory/*.md into a temporary managed memory store, runs a Dreams job against
# recent Managed Agents sessions, and writes curated output back to memory/.
# Exit 0 on success or graceful skip; 1 on hard error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORY_DIR="${MEMORY_DIR:-$REPO_ROOT/memory}"
API="https://api.anthropic.com/v1"
MAX_SESSIONS=20
POLL_TIMEOUT=3600  # 60-minute wall-clock max; dreams typically run in minutes to tens of minutes
POLL_INTERVAL=30

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "::error::ANTHROPIC_API_KEY secret is not set."
  exit 1
fi

# ── access check ─────────────────────────────────────────────────────────────
http_code=$(curl -s -o /dev/null -w "%{http_code}" "$API/memory_stores?limit=1" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01")
if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
  echo "::warning::Managed Agents / Dreams API access not granted (HTTP $http_code)."
  echo "::warning::Request access at https://claude.com/form/claude-managed-agents"
  echo "::warning::Once approved, this workflow will run automatically on the next Sunday."
  exit 0
fi
if [[ "$http_code" != "200" ]]; then
  echo "::error::Unexpected HTTP $http_code from /memory_stores — check ANTHROPIC_API_KEY."
  exit 1
fi
echo "Managed Agents API access confirmed."

# ── collect memory files ──────────────────────────────────────────────────────
mapfile -t mem_files < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" | sort)
if [[ "${#mem_files[@]}" -eq 0 ]]; then
  echo "::notice::No .md files in memory/ — nothing to curate."
  exit 0
fi
echo "Found ${#mem_files[@]} memory file(s) to upload."

# ── create temporary input store ─────────────────────────────────────────────
run_label=$(date -u +%Y%m%d-%H%M)
store_resp=$(curl -sf -X POST "$API/memory_stores" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d "{\"name\": \"dreams-input-$run_label\", \"description\": \"Temporary Dreams input: agentic-dev-environment memory curation.\"}")
store_id=$(jq -r '.id' <<< "$store_resp")
echo "Created input store: $store_id"

cleanup() {
  if [[ -n "${store_id:-}" && "${store_id}" != "null" ]]; then
    curl -s -X POST "$API/memory_stores/$store_id/archive" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "anthropic-beta: managed-agents-2026-04-01" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ── upload memory files ───────────────────────────────────────────────────────
for fpath in "${mem_files[@]}"; do
  fname=$(basename "$fpath")
  payload=$(jq -n --arg path "/$fname" --rawfile content "$fpath" \
    '{"path": $path, "content": $content}')
  curl -sf -X POST "$API/memory_stores/$store_id/memories" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: managed-agents-2026-04-01" \
    -H "content-type: application/json" \
    -d "$payload" >/dev/null
  echo "  uploaded: $fname"
done

# ── list recent sessions ──────────────────────────────────────────────────────
sessions_resp=$(curl -sf "$API/sessions?limit=$MAX_SESSIONS" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01")
session_count=$(jq '.data | length' <<< "$sessions_resp")
echo "Found $session_count recent session(s)."

if [[ "$session_count" -eq 0 ]]; then
  echo "::warning::No Managed Agents sessions found; Dreams requires ≥ 1 session transcript."
  echo "::warning::Sessions accumulate as platform agent jobs run via the Managed Agents API. Re-run next week."
  exit 0
fi
session_ids=$(jq '[.data[].id]' <<< "$sessions_resp")

# ── create dream ──────────────────────────────────────────────────────────────
dream_body=$(jq -n \
  --arg store_id "$store_id" \
  --argjson session_ids "$session_ids" \
  '{
    inputs: [
      {type: "memory_store", memory_store_id: $store_id},
      {type: "sessions", session_ids: $session_ids}
    ],
    model: "claude-opus-4-8",
    instructions: "Focus on engineering patterns, project conventions, and cross-session insights. Merge duplicates; replace stale entries where more recent sessions contradict them. Preserve ADR references, decision rationales, and time-sensitive notes."
  }')
dream_resp=$(curl -sf -X POST "$API/dreams" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01,dreaming-2026-04-21" \
  -H "content-type: application/json" \
  -d "$dream_body")
dream_id=$(jq -r '.id' <<< "$dream_resp")
echo "Dream created: $dream_id"

# ── poll for completion ───────────────────────────────────────────────────────
elapsed=0
status=$(jq -r '.status' <<< "$dream_resp")
while [[ "$status" == "pending" || "$status" == "running" ]]; do
  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
  dream_resp=$(curl -sf "$API/dreams/$dream_id" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: managed-agents-2026-04-01,dreaming-2026-04-21")
  status=$(jq -r '.status' <<< "$dream_resp")
  input_tokens=$(jq '.usage.input_tokens' <<< "$dream_resp")
  echo "  status=$status input_tokens=$input_tokens elapsed=${elapsed}s"
  if [[ $elapsed -ge $POLL_TIMEOUT ]]; then
    echo "::warning::Dream $dream_id timed out after ${POLL_TIMEOUT}s. Will retry next week."
    exit 0
  fi
done

if [[ "$status" != "completed" ]]; then
  err_type=$(jq -r '.error.type // "unknown"' <<< "$dream_resp")
  echo "::error::Dream $dream_id ended with status=$status error=$err_type"
  exit 1
fi
echo "Dream completed successfully."

# ── export output memories to memory/ ────────────────────────────────────────
out_store=$(jq -r 'first(.outputs[] | select(.type == "memory_store")).memory_store_id' <<< "$dream_resp")
echo "Output store: $out_store"

# Remove previous .md files so renamed/merged memories replace them cleanly
for f in "${mem_files[@]}"; do rm -f "$f"; done

total_written=0
next_page=""
while :; do
  url="$API/memory_stores/$out_store/memories?limit=100"
  [[ -n "$next_page" ]] && url="$url&page=$next_page"
  page_resp=$(curl -sf "$url" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: managed-agents-2026-04-01")

  while IFS=$'\t' read -r mem_id mem_path; do
    mem_full=$(curl -sf "$API/memory_stores/$out_store/memories/$mem_id" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "anthropic-beta: managed-agents-2026-04-01")
    mem_content=$(jq -r '.content' <<< "$mem_full")
    out_path="$MEMORY_DIR/${mem_path#/}"
    real_out=$(realpath -m "$out_path")
    [[ "$real_out" == "$MEMORY_DIR/"* ]] || {
      echo "::error::Dream output contains unsafe path: $mem_path — aborting."
      exit 1
    }
    mkdir -p "$(dirname "$real_out")"
    printf '%s' "$mem_content" > "$real_out"
    echo "  wrote: ${mem_path#/}"
    total_written=$((total_written + 1))
  done < <(jq -r '.data[] | select(.type == "memory") | [.id, .path] | @tsv' <<< "$page_resp")

  next_page=$(jq -r '.next_page // empty' <<< "$page_resp")
  [[ -z "$next_page" ]] && break
done

echo "Exported $total_written curated memory file(s)."

# Preserve directory tracking if Dreams produced no output
[[ $total_written -eq 0 ]] && touch "$MEMORY_DIR/.gitkeep"
