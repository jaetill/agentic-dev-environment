# Creates a "new error in production" Sentry Issue Alert via the Sentry REST API.
#
# Per platform Standard 06 / ADR-0009. The Metric Alert framework can't be IaC'd
# via the jianyuan Terraform provider (see memory: reference_sentry_iac_dead_ends),
# but Issue Alerts via /api/0/projects/{org}/{project}/rules/ are fully API-supported.
#
# Usage:
#   $env:SENTRY_AUTH_TOKEN = "<paste from 1Password>"
#   .\scripts\sentry-create-alert.ps1 -Project meal-planner
#
# Or with all defaults overridden:
#   .\scripts\sentry-create-alert.ps1 -Org jaetill -Project meal-planner `
#       -Environment production -AlertName "meal-planner - new error in prod"
#
# The script is idempotent-ish: it checks for an existing rule with the same name
# in the same project and skips creation if found. Re-run safely.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Project,

  [string]$Org = "jaetill",

  [string]$Environment = "production",

  [string]$AlertName,

  [ValidateSet("Member", "Team", "IssueOwners")]
  [string]$TargetType = "IssueOwners",

  # If TargetType is Member or Team, identifier (user ID for Member, team slug
  # for Team). IssueOwners requires no identifier - Sentry falls back to all
  # team members when no code-ownership rules match. If you pick Member and
  # leave this blank, the script tries to look up your user via /users/me/
  # which requires 'user:read' on the token.
  [string]$TargetIdentifier,

  # Sentry level numeric: 10=debug, 20=info, 30=warning, 40=error, 50=fatal
  [int]$MinLevel = 40,

  # Notify at most once per this many minutes per issue
  [int]$RateLimitMinutes = 5
)

$ErrorActionPreference = 'Stop'

if (-not $env:SENTRY_AUTH_TOKEN) {
  $secure = Read-Host -AsSecureString -Prompt "Paste your SENTRY_AUTH_TOKEN"
  $env:SENTRY_AUTH_TOKEN = [System.Net.NetworkCredential]::new("", $secure).Password
}

if (-not $AlertName) {
  $AlertName = "$Project - new error in $Environment"
}

$headers = @{
  "Authorization" = "Bearer $env:SENTRY_AUTH_TOKEN"
  "Content-Type"  = "application/json"
}

# --- Look up current user if we need them as the notification target ---
if ($TargetType -eq "Member" -and -not $TargetIdentifier) {
  Write-Host "Looking up your Sentry user ID (requires user:read scope on token)..."
  try {
    $me = Invoke-RestMethod -Uri "https://sentry.io/api/0/users/me/" -Headers $headers
    $TargetIdentifier = $me.id
    Write-Host "  username: $($me.username)"
    Write-Host "  id:       $TargetIdentifier"
  } catch {
    Write-Host "  FAILED. Your token doesn't have 'user:read' scope."
    Write-Host "  Falling back to TargetType=IssueOwners (no identifier needed)."
    $TargetType = "IssueOwners"
    $TargetIdentifier = $null
  }
}

# --- Idempotency: skip if a rule with this name already exists ---
Write-Host ""
Write-Host "Checking for an existing rule named '$AlertName'..."
$existing = Invoke-RestMethod -Uri "https://sentry.io/api/0/projects/$Org/$Project/rules/" -Headers $headers
$match = $existing | Where-Object { $_.name -eq $AlertName }
if ($match) {
  Write-Host "[OK] Rule already exists (id: $($match.id)). Skipping creation."
  Write-Host "  View: https://sentry.io/organizations/$Org/alerts/rules/$Project/$($match.id)/"
  return
}

# --- Build payload ---
$payload = @{
  name        = $AlertName
  actionMatch = "any"
  filterMatch = "all"
  frequency   = $RateLimitMinutes
  environment = $Environment
  conditions  = @(
    @{ id = "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition" }
    @{ id = "sentry.rules.conditions.regression_event.RegressionEventCondition" }
  )
  filters     = @(
    @{ id = "sentry.rules.filters.level.LevelFilter"; match = "gte"; level = "$MinLevel" }
  )
  actions     = @(
    if ($TargetType -eq "IssueOwners") {
      @{
        id         = "sentry.mail.actions.NotifyEmailAction"
        targetType = "IssueOwners"
      }
    } else {
      @{
        id               = "sentry.mail.actions.NotifyEmailAction"
        targetType       = $TargetType
        targetIdentifier = $TargetIdentifier
      }
    }
  )
} | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "Creating rule '$AlertName' in $Org/$Project..."
$response = Invoke-RestMethod `
  -Uri "https://sentry.io/api/0/projects/$Org/$Project/rules/" `
  -Method Post `
  -Headers $headers `
  -Body $payload

Write-Host ""
Write-Host "[OK] Created alert rule: $($response.name)"
Write-Host "  id:   $($response.id)"
Write-Host "  view: https://sentry.io/organizations/$Org/alerts/rules/$Project/$($response.id)/"
Write-Host ""
Write-Host "Trigger conditions:"
Write-Host "  - A new issue is first seen in '$Environment'"
Write-Host "  - An issue regresses from resolved -> unresolved"
Write-Host "Filters:"
Write-Host "  - Event level >= $MinLevel ($(switch ($MinLevel) { 40 {'error'} 30 {'warning'} 50 {'fatal'} default {'level '+$MinLevel} }))"
Write-Host "Action:"
if ($TargetType -eq "IssueOwners") {
  Write-Host "  - Email IssueOwners (falls back to all team members if no owners assigned)"
} else {
  Write-Host "  - Email $TargetType : $TargetIdentifier"
}
Write-Host "Rate limit: once per $RateLimitMinutes minutes per issue"
