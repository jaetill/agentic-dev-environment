#requires -Version 5.1
<#
  configure-branch-protection.ps1

  THE branch-protection script for the portfolio. Makes branch protection
  UNIFORM across the 7 ADR-0018 migrated project repos — "same team, same
  rigor": no project is exempt; the only thing that differs between projects
  is the stack knowledge their agents load, not the gates.

  For each repo:
    - If the branch is already protected -> UPDATE the required-status-check
      set to the canonical claude-pr-review set (preserving non-claude checks
      like gitleaks / npm-audit).
    - If the branch has NO protection -> CREATE protection matching the peer
      model (game-night-pwa): canonical checks + linear history, no force
      pushes, no deletions, PR required.

  Canonical required claude-pr-review checks (the hard gates):
    review / code-review
    review / security-review
    review / functional-test
    review / e2e-test
    review / destructive-change-check

  Advisory claude-pr-review jobs (test-writer, doc-keeper, ensure-labels,
  invoke-architect-if-gated) are intentionally NOT required.

  strict = false (do NOT "require branches up to date before merging"):
  ADR-0021's autonomous auto-merge squash-merges fix PRs without rebasing
  behind branches, so it can never satisfy strict mode — a behind PR's
  passing checks read back as "expected" and the merge is blocked (this was
  the cause of meal-planner #65 sticking). Both the CREATE and UPDATE paths
  set strict = false; UPDATE corrects pre-existing strict = true drift.

  NOT IN SCOPE (already done / separate):
    - "Require Code Owner review" on the platform repo — already enabled.

  CONSEQUENCE (intended, per the "flip all 5 on now" decision): if a project's
  functional-test or e2e-test cannot currently pass, its PRs block until the
  tests are fixed. The blocked PR is the forcing function to close the gap.

  USAGE
    Run as-is. $Apply = $true means it applies. It is idempotent — repos that
    are already uniform print "already uniform - no change" and are untouched.
    A CREATE only happens on a branch that currently has zero protection, so
    it cannot overwrite or weaken anything.

  Requires: gh CLI, authenticated.
#>

$Apply = $true   # idempotent; protected+uniform repos are no-ops, see header

# repo -> default branch (the 7 repos migrated under ADR-0018)
$repos = [ordered]@{
  'game-night-pwa' = 'master'
  'meal-planner'   = 'master'
  'carto'          = 'master'
  'draft'          = 'master'
  'ai-teacher'     = 'main'
  'jaetill-portal' = 'main'
  'splendor'       = 'main'
}

# The canonical required set every repo must have.
$canonical = @(
  'review / code-review'
  'review / security-review'
  'review / functional-test'
  'review / e2e-test'
  'review / destructive-change-check'
)

# Every claude-pr-review job name (bare) — used to strip ALL claude checks
# (prefixed or not) before re-adding the canonical set.
$claudeJobs = @(
  'code-review','functional-test','test-writer','e2e-test','doc-keeper',
  'security-review','destructive-change-check','ensure-labels','invoke-architect-if-gated'
)

function Test-IsClaudeCheck($ctx) {
  $bare = $ctx -replace '^review / ', ''
  return $claudeJobs -contains $bare
}

# Full-protection payload for the CREATE path — matches game-night-pwa's model.
function New-ProtectionBody {
  @{
    required_status_checks = @{
      strict = $false
      checks = @($canonical | ForEach-Object { @{ context = $_ } })
    }
    enforce_admins = $false
    required_pull_request_reviews = @{
      dismiss_stale_reviews          = $true
      require_code_owner_reviews     = $false
      required_approving_review_count = 0
    }
    restrictions                    = $null
    required_linear_history         = $true
    allow_force_pushes              = $false
    allow_deletions                 = $false
    required_conversation_resolution = $false
  }
}

function Invoke-GhJson($method, $url, $bodyObj) {
  $body = $bodyObj | ConvertTo-Json -Depth 8
  $tmp  = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmp.FullName, $body, (New-Object System.Text.UTF8Encoding($false)))
  gh api -X $method $url --input $tmp.FullName | Out-Null
  $exit = $LASTEXITCODE
  Remove-Item $tmp.FullName -Force
  return $exit
}

foreach ($repo in $repos.Keys) {
  $branch = $repos[$repo]
  Write-Host ""
  Write-Host "=== $repo ($branch) ===" -ForegroundColor Cyan

  # Reliable protected/unprotected detection via exit code (a 404 body can
  # look like data, so do not trust stdout emptiness).
  $protJson  = gh api "repos/jaetill/$repo/branches/$branch/protection" 2>$null
  $protected = ($LASTEXITCODE -eq 0)

  if (-not $protected) {
    # ---- CREATE path -----------------------------------------------------
    Write-Host "  no branch protection found - will CREATE (peer model)" -ForegroundColor Yellow
    foreach ($x in ($canonical | Sort-Object)) { Write-Host "  require: $x" }
    Write-Host "  + linear history, no force-push, no deletions, PR required"
    if (-not $Apply) { Write-Host "  [DRY RUN] not applied" -ForegroundColor DarkGray; continue }

    $exit = Invoke-GhJson 'PUT' "repos/jaetill/$repo/branches/$branch/protection" (New-ProtectionBody)
    if ($exit -eq 0) {
      Write-Host "  CREATED" -ForegroundColor Green
      $sigExit = Invoke-GhJson 'PUT' "repos/jaetill/$repo/branches/$branch/protection/required_signatures" @{}
      if ($sigExit -eq 0) { Write-Host "  required_signatures enabled" -ForegroundColor Green }
      else                { Write-Host "  required_signatures FAILED (gh api exit $sigExit)" -ForegroundColor Red }
    } else           { Write-Host "  FAILED (gh api exit $exit)" -ForegroundColor Red }
    continue
  }

  # ---- UPDATE path -------------------------------------------------------
  $prot = $protJson | ConvertFrom-Json
  $rsc  = $prot.required_status_checks
  if (-not $rsc) {
    Write-Host "  protected, but no required_status_checks block - skipping" -ForegroundColor Yellow
    Write-Host "  (add status-check protection in the UI, then re-run)" -ForegroundColor DarkGray
    continue
  }

  $preserved = @()
  foreach ($c in $rsc.checks) {
    if (-not (Test-IsClaudeCheck $c.context)) { $preserved += $c.context }
  }
  $final = @($canonical + $preserved | Select-Object -Unique)

  $current = @($rsc.checks.context)
  $added   = @($final   | Where-Object { $current -notcontains $_ })
  $removed = @($current | Where-Object { $final   -notcontains $_ })

  foreach ($x in ($final | Sort-Object)) { Write-Host "  require: $x" }
  if ($added)   { Write-Host "    + adding:   $($added -join ', ')"   -ForegroundColor Green }
  if ($removed) { Write-Host "    - removing: $($removed -join ', ')" -ForegroundColor Yellow }
  # Canonical strict is $false (ADR-0021). A repo with uniform contexts but
  # strict = true must still be PATCHed, so do not skip on contexts alone.
  $strictDrift = [bool]$rsc.strict
  if ($strictDrift) { Write-Host "    ~ strict: true -> false (ADR-0021)" -ForegroundColor Yellow }
  $sigJson = gh api "repos/jaetill/$repo/branches/$branch/protection/required_signatures" 2>$null
  $sigEnabled = $false
  if ($LASTEXITCODE -eq 0) {
    try { $sigEnabled = ($sigJson | ConvertFrom-Json).enabled } catch {}
  }
  $sigDrift = -not $sigEnabled
  if ($sigDrift) { Write-Host "    ~ required_signatures: not enabled -> enabled" -ForegroundColor Yellow }
  if (-not $added -and -not $removed -and -not $strictDrift -and -not $sigDrift) {
    Write-Host "  already uniform - no change" -ForegroundColor DarkGray
    continue
  }
  if (-not $Apply) { Write-Host "  [DRY RUN] not applied" -ForegroundColor DarkGray; continue }

  if ($added -or $removed -or $strictDrift) {
    # strict forced false (see header) — never preserve a drifted strict = true.
    $payload = @{ strict = $false; checks = @($final | ForEach-Object { @{ context = $_ } }) }
    $exit = Invoke-GhJson 'PATCH' "repos/jaetill/$repo/branches/$branch/protection/required_status_checks" $payload
    if ($exit -eq 0) { Write-Host "  APPLIED" -ForegroundColor Green }
    else             { Write-Host "  FAILED (gh api exit $exit)" -ForegroundColor Red }
  }
  if ($sigDrift) {
    $sigExit = Invoke-GhJson 'PUT' "repos/jaetill/$repo/branches/$branch/protection/required_signatures" @{}
    if ($sigExit -eq 0) { Write-Host "  required_signatures enabled" -ForegroundColor Green }
    else                { Write-Host "  required_signatures FAILED (gh api exit $sigExit)" -ForegroundColor Red }
  }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
