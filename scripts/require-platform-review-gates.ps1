#requires -Version 5.1
<#
  require-platform-review-gates.ps1

  Adds the claude-pr-review check set to the PLATFORM repo's branch
  protection, so self-modification PRs are gated by code-review and
  security-review (ADR-0019 sub-decision 4). The platform repo thereby
  joins the same uniform-rigor model as the seven project repos
  (see configure-branch-protection.ps1).

  *** RUN ORDER MATTERS — READ THIS ***
  Run this ONLY AFTER both of the following are true:
    1. the PR that adds .github/workflows/pr-review.yml has merged, AND
    2. at least one PR has since run pr-review.yml, so the `review / *`
       check contexts have reported at least once.
  GitHub lets you mark a never-seen check "required" — but then EVERY PR
  blocks forever, waiting for a status that never arrives. Running this
  too early deadlocks the repo. The dry run below is safe at any time.

  Canonical required checks added (existing format/lint checks such as
  validate / link-check / adr-format-check are preserved):
    review / code-review
    review / security-review
    review / functional-test          (skips on this repo — skip = satisfied)
    review / e2e-test                 (skips on this repo — skip = satisfied)
    review / destructive-change-check

  USAGE
    Dry run (default, safe): run as-is — prints what it WOULD do.
    To apply: set $Apply = $true, then run.
    Idempotent — re-running when already uniform prints "no change".

  Requires: gh CLI, authenticated.
#>

$Apply = $true   # applied — re-read the RUN ORDER warning above before re-running

$repo   = 'jaetill/agentic-dev-environment'
$branch = 'main'

# The canonical claude-pr-review check set — matches configure-branch-protection.ps1.
$canonical = @(
  'review / code-review'
  'review / security-review'
  'review / functional-test'
  'review / e2e-test'
  'review / destructive-change-check'
)

Write-Host ""
Write-Host "=== $repo ($branch) ===" -ForegroundColor Cyan

$protJson = gh api "repos/$repo/branches/$branch/protection" 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "  branch is not protected - aborting (set up base protection first)" -ForegroundColor Red
  exit 1
}
$prot = $protJson | ConvertFrom-Json
$rsc  = $prot.required_status_checks
if (-not $rsc) {
  Write-Host "  protected, but no required_status_checks block." -ForegroundColor Yellow
  Write-Host "  Add status-check protection in the UI once, then re-run." -ForegroundColor DarkGray
  exit 1
}

$current = @($rsc.checks.context)
$final   = @($current + $canonical | Select-Object -Unique)
$added   = @($final | Where-Object { $current -notcontains $_ })

foreach ($x in ($final | Sort-Object)) { Write-Host "  require: $x" }
if ($added) {
  Write-Host "    + adding: $($added -join ', ')" -ForegroundColor Green
} else {
  Write-Host "  already uniform - no change" -ForegroundColor DarkGray
  exit 0
}

if (-not $Apply) {
  Write-Host "  [DRY RUN] not applied - set `$Apply = `$true to apply" -ForegroundColor DarkGray
  exit 0
}

$payload = @{ strict = $rsc.strict; checks = @($final | ForEach-Object { @{ context = $_ } }) }
$body = $payload | ConvertTo-Json -Depth 8
$tmp  = New-TemporaryFile
[System.IO.File]::WriteAllText($tmp.FullName, $body, (New-Object System.Text.UTF8Encoding($false)))
gh api -X PATCH "repos/$repo/branches/$branch/protection/required_status_checks" --input $tmp.FullName | Out-Null
$exit = $LASTEXITCODE
Remove-Item $tmp.FullName -Force
if ($exit -eq 0) { Write-Host "  APPLIED" -ForegroundColor Green }
else             { Write-Host "  FAILED (gh api exit $exit)" -ForegroundColor Red }
