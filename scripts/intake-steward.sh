#!/usr/bin/env bash
# intake-steward.sh — deterministic admission pass over the fleet's open issues (ADR-0044).
# Modes: MODE=recent (default; issues updated in the last WINDOW_MIN minutes) | MODE=full (all open).
# Requires: GH_TOKEN with issues:write on all owner repos (fleet App token).
set -uo pipefail

OWNER="${OWNER:-jaetill}"
MODE="${MODE:-recent}"
WINDOW_MIN="${WINDOW_MIN:-40}"
MAINTAINERS="${MAINTAINERS:-jaetill}"

# Labels the steward may create on demand: name|color|description
ensure_label() { # repo name color desc
  gh label create "$2" --repo "$OWNER/$1" --color "$3" --description "$4" >/dev/null 2>&1 || true
}

is_maintainer() { case " $MAINTAINERS " in *" $1 "*) return 0;; *) return 1;; esac; }

changed=0; surfaced=0; failures=0; scanned=0

repos=$(gh repo list "$OWNER" --limit 100 --json name,isArchived -q '.[] | select(.isArchived|not) | .name')
# App installation tokens can't always enumerate repos — fall back to the known fleet.
[[ -z "$repos" ]] && repos="agentic-dev-environment game-night-pwa meal-planner ai-teacher jaetill-portal splendor draft carto genealogy"

since_filter=""
if [[ "$MODE" == "recent" ]]; then
  since=$(date -u -d "$WINDOW_MIN minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v -"${WINDOW_MIN}"M +%Y-%m-%dT%H:%M:%SZ)
  since_filter="&since=$since"
fi

for repo in $repos; do
  page=1
  while :; do
    batch=$(gh api "repos/$OWNER/$repo/issues?state=open&per_page=100&page=$page$since_filter" 2>/dev/null) || break
    count=$(jq 'length' <<<"$batch"); [[ "$count" == "0" || -z "$count" ]] && break
    while IFS= read -r row; do
      num=$(jq -r '.number' <<<"$row")
      ispr=$(jq -r 'has("pull_request")' <<<"$row")
      [[ "$ispr" == "true" ]] && continue
      scanned=$((scanned+1))
      author=$(jq -r '.user.login' <<<"$row")
      authortype=$(jq -r '.user.type' <<<"$row")
      labels=$(jq -r '[.labels[].name] | join("|")' <<<"$row")
      has() { case "|$labels|" in *"|$1|"*) return 0;; *) return 1;; esac; }
      add=(); rm_=()

      # 1. origin (deterministic from author; never overwrite)
      if ! grep -q '|origin:human\||origin:internal-review\||origin:sentry\||origin:cloudwatch|' <<<"|$labels|"; then
        case "$author" in
          sentry-io*|*sentry*\[bot\]) o="origin:sentry";;
          *\[bot\])                    o="origin:internal-review";;
          *) if [[ "$authortype" == "Bot" ]]; then o="origin:internal-review"; else o="origin:human"; fi;;
        esac
        add+=("$o")
      fi

      # 2. type (deterministic only)
      if ! grep -q '|type:feature\||type:defect\||type:process-flaw|' <<<"|$labels|"; then
        if has "process-flaw"; then add+=("type:process-flaw")
        elif has "defect" || has "bug"; then add+=("type:defect")
        elif has "feature-request" || has "approved"; then add+=("type:feature")
        elif [[ "$authortype" == "Bot" || "$author" == *"[bot]"* ]]; then add+=("type:defect")
        fi
      fi

      # 3. dialect migration + dead labels
      has "component:iac" && { has "scope:iac" || add+=("scope:iac"); rm_+=("component:iac"); }
      has "component:ci"  && { has "scope:ci"  || add+=("scope:ci");  rm_+=("component:ci"); }
      for dead in awaiting-dispatch type:chore deferred-until-adjacent origin:external-request; do
        has "$dead" && rm_+=("$dead")
      done

      # 4. routing: surface non-maintainer + label-bare maintainer filings
      if ! has "needs-formulation" && ! has "approved" && ! has "ready-for-implementer" && ! has "parked"; then
        if [[ "$authortype" != "Bot" && "$author" != *"[bot]"* ]]; then
          if ! is_maintainer "$author" || [[ -z "$labels" ]]; then
            add+=("needs-formulation")
            surfaced=$((surfaced+1))
          fi
        fi
      fi

      [[ ${#add[@]} -eq 0 && ${#rm_[@]} -eq 0 ]] && continue

      # ensure labels exist, then apply
      for l in "${add[@]:-}"; do
        [[ -z "$l" ]] && continue
        case "$l" in
          origin:*) ensure_label "$repo" "$l" "1D76DB" "Work origin, derived from author identity (ADR-0044)";;
          type:*)   ensure_label "$repo" "$l" "0052CC" "Work type axis (ADR-0044)";;
          scope:*)  ensure_label "$repo" "$l" "5319E7" "Specialist scope axis (ADR-0044)";;
          needs-formulation) ensure_label "$repo" "$l" "FBCA04" "Awaiting human formulation (ADR-0036)";;
        esac
      done
      args=()
      for l in "${add[@]:-}"; do [[ -n "$l" ]] && args+=(--add-label "$l"); done
      for l in "${rm_[@]:-}"; do [[ -n "$l" ]] && args+=(--remove-label "$l"); done
      gh issue edit "$num" --repo "$OWNER/$repo" "${args[@]}" >/dev/null 2>&1

      # 5. verified write
      after=$(gh api "repos/$OWNER/$repo/issues/$num" -q '[.labels[].name] | join("|")' 2>/dev/null)
      ok=1
      for l in "${add[@]:-}"; do [[ -n "$l" ]] && [[ "|$after|" != *"|$l|"* ]] && ok=0; done
      for l in "${rm_[@]:-}"; do [[ -n "$l" ]] && [[ "|$after|" == *"|$l|"* ]] && ok=0; done
      if [[ $ok -eq 1 ]]; then
        changed=$((changed+1))
        echo "stewarded $repo#$num: +[${add[*]:-}] -[${rm_[*]:-}]"
      else
        failures=$((failures+1))
        echo "::warning::VERIFY FAILED $repo#$num: wanted +[${add[*]:-}] -[${rm_[*]:-}], got [$after]"
      fi
    done < <(jq -c '.[]' <<<"$batch")
    page=$((page+1))
  done
done

echo "intake-steward: scanned=$scanned changed=$changed surfaced=$surfaced verify-failures=$failures"
[[ $failures -gt 0 ]] && exit 1
exit 0
