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
      # Verification-pattern title detection: titles starting with "Verify ",
      # "Check ", "Confirm ", or "Audit " are investigation tasks (check that
      # X works as expected; either close it or file a follow-up defect).
      # This is a distinct work category from feature/defect/process-flaw.
      title=$(jq -r '.title // ""' <<<"$row")
      is_verification=0
      case "$title" in
        Verify\ *|Check\ *|Confirm\ *|Audit\ *) is_verification=1 ;;
      esac
      if ! grep -q '|type:feature\||type:defect\||type:process-flaw\||type:investigation|' <<<"|$labels|"; then
        if has "process-flaw"; then add+=("type:process-flaw")
        elif has "defect" || has "bug"; then add+=("type:defect")
        elif [[ "$is_verification" == "1" ]]; then add+=("type:investigation")
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

      # 4b. NARROW trust expansion: maintainer-filed verification tasks
      # auto-route to `approved`. The work category (verify/check/confirm/
      # audit) is a deterministic title-pattern match, not content judgment;
      # maintainer identity is platform-enforced, not spoofable. Filing a
      # verification task IS the implicit approval — there's nothing to
      # formulate (the title states what to check). If `needs-formulation`
      # was previously applied (either by an earlier steward sweep or by
      # the maintainer choosing it for lack of a better label), strip it.
      # Non-maintainer verification filings still need formulation (the
      # maintainer must decide whether the check is worth doing).
      if [[ "$is_verification" == "1" ]] && is_maintainer "$author"; then
        if ! has "approved" && ! has "ready-for-implementer" && ! has "parked"; then
          add+=("approved")
        fi
        if has "needs-formulation"; then
          rm_+=("needs-formulation")
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
          approved) ensure_label "$repo" "$l" "0E8A16" "Approved for promoter pickup (ADR-0036)";;
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
