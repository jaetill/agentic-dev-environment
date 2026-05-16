# Creates a Sentry project via REST API and fetches its DSN.
#
# Reusable across projects. Composes with sentry-create-alert.ps1 — pass
# -CreateAlert to also create a "new error in production" rule in one go.
#
# Usage:
#   $env:SENTRY_AUTH_TOKEN = "<paste from 1Password>"
#   .\scripts\sentry-create-project.ps1 -Project ai-teacher -Platform javascript-nextjs
#
# Or with everything in one shot:
#   .\scripts\sentry-create-project.ps1 -Project ai-teacher -Platform javascript-nextjs -CreateAlert
#
# Idempotent: if a project with the same slug exists, skips creation and
# fetches the existing DSN.
#
# After running, prints the env vars and repo secrets you need to set
# manually (Vercel CLI / dashboard, gh secret set).

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Project,

  [string]$Org = "jaetill",

  # Common values: javascript-nextjs, javascript, javascript-react, node,
  # python, etc. Affects Sentry's onboarding hints; doesn't change runtime.
  [string]$Platform = "javascript-nextjs",

  # If omitted, picks the first team in the org. Most solo orgs have one.
  [string]$Team,

  # Also create the standard "new error in production" alert rule by
  # invoking sentry-create-alert.ps1.
  [switch]$CreateAlert,

  # Sentry environment for the alert. Default production.
  [string]$AlertEnvironment = "production"
)

$ErrorActionPreference = 'Stop'

if (-not $env:SENTRY_AUTH_TOKEN) {
  $secure = Read-Host -AsSecureString -Prompt "Paste your SENTRY_AUTH_TOKEN"
  $env:SENTRY_AUTH_TOKEN = [System.Net.NetworkCredential]::new("", $secure).Password
}

$headers = @{
  "Authorization" = "Bearer $env:SENTRY_AUTH_TOKEN"
  "Content-Type"  = "application/json"
}

# --- Pick a team ---
if (-not $Team) {
  Write-Host "Listing teams in org '$Org' to find one..."
  $teams = Invoke-RestMethod -Uri "https://sentry.io/api/0/organizations/$Org/teams/" -Headers $headers
  if ($teams.Count -eq 0) {
    throw "No teams found in org '$Org'. Create one in the Sentry UI first."
  }
  $Team = $teams[0].slug
  Write-Host "  using team: $Team"
  if ($teams.Count -gt 1) {
    Write-Host "  (org has $($teams.Count) teams; override with -Team <slug> if needed)"
  }
}

# --- Check if project already exists ---
Write-Host ""
Write-Host "Checking if project '$Project' already exists in $Org..."
$existing = $null
try {
  $existing = Invoke-RestMethod -Uri "https://sentry.io/api/0/projects/$Org/$Project/" -Headers $headers
} catch {
  if ($_.Exception.Response.StatusCode.Value__ -ne 404) {
    throw
  }
}

if ($existing) {
  Write-Host "[OK] Project '$Project' exists (id: $($existing.id), platform: $($existing.platform))"
  Write-Host "  skipping creation"
} else {
  Write-Host "Creating project '$Project' under team '$Team', platform '$Platform'..."
  $payload = @{
    name     = $Project
    slug     = $Project
    platform = $Platform
  } | ConvertTo-Json
  $created = Invoke-RestMethod `
    -Uri "https://sentry.io/api/0/teams/$Org/$Team/projects/" `
    -Method Post `
    -Headers $headers `
    -Body $payload
  Write-Host "[OK] Created project '$($created.slug)' (id: $($created.id))"
}

# --- Fetch the DSN ---
Write-Host ""
Write-Host "Fetching DSN..."
$keys = Invoke-RestMethod -Uri "https://sentry.io/api/0/projects/$Org/$Project/keys/" -Headers $headers
if ($keys.Count -eq 0) {
  throw "No client keys found on project. Create one in Sentry UI."
}
# Each key has dsn.public (the standard public DSN) and dsn.secret (legacy)
$dsn = $keys[0].dsn.public
$projectId = $keys[0].projectId

Write-Host "[OK] DSN retrieved"
Write-Host ""
Write-Host "=============================================="
Write-Host "  Project Sentry config for: $Project"
Write-Host "=============================================="
Write-Host ""
Write-Host "  Sentry org slug:     $Org"
Write-Host "  Sentry project slug: $Project"
Write-Host "  Sentry project id:   $projectId"
Write-Host "  DSN:                 $dsn"
Write-Host ""
Write-Host "  Sentry UI:           https://sentry.io/organizations/$Org/projects/$Project/"
Write-Host ""

# --- Optional: also create the alert rule ---
if ($CreateAlert) {
  Write-Host "Creating default alert rule via sentry-create-alert.ps1..."
  $scriptDir = Split-Path -Parent $PSCommandPath
  $alertScript = Join-Path $scriptDir "sentry-create-alert.ps1"
  if (Test-Path $alertScript) {
    & $alertScript -Project $Project -Org $Org -Environment $AlertEnvironment
  } else {
    Write-Host "  [WARN] $alertScript not found; skipping alert rule"
  }
}

# --- Print next steps ---
Write-Host ""
Write-Host "=============================================="
Write-Host "  Next steps - YOU need to do these"
Write-Host "=============================================="
Write-Host ""
Write-Host "  1. Save the DSN to 1Password as: 'Sentry DSN - $Project'"
Write-Host ""
Write-Host "  2. Set Vercel env vars (Production, Preview, Development):"
Write-Host ""
Write-Host "       cd <project-root>"
Write-Host "       vercel env add NEXT_PUBLIC_SENTRY_DSN production"
Write-Host "       vercel env add NEXT_PUBLIC_SENTRY_DSN preview"
Write-Host "       vercel env add NEXT_PUBLIC_SENTRY_DSN development"
Write-Host "       # paste DSN at each prompt"
Write-Host "       vercel env add SENTRY_AUTH_TOKEN  production"
Write-Host "       vercel env add SENTRY_ORG          production -b $Org"
Write-Host "       vercel env add SENTRY_PROJECT      production -b $Project"
Write-Host ""
Write-Host "     (For non-Next.js projects, use VITE_SENTRY_DSN instead.)"
Write-Host ""
Write-Host "  3. Set GitHub repo secrets (for CI source-map upload):"
Write-Host ""
Write-Host "       gh secret set NEXT_PUBLIC_SENTRY_DSN -R jaetill/$Project"
Write-Host "       gh secret set SENTRY_AUTH_TOKEN      -R jaetill/$Project"
Write-Host "       gh secret set SENTRY_ORG             -R jaetill/$Project -b $Org"
Write-Host "       gh secret set SENTRY_PROJECT         -R jaetill/$Project -b $Project"
Write-Host ""
Write-Host "  4. (Optional, recommended) Wire Sentry GitHub integration:"
Write-Host "       https://sentry.io/settings/$Org/integrations/github/"
Write-Host "       Adds commit-to-issue linking for releases."
Write-Host ""
