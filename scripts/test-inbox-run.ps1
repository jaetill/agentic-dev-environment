# Pulls Gmail tester creds from AWS Secrets Manager, prompts for the
# per-run inputs (Cognito host token + test night id), sets env vars,
# and runs the admin-invite-flow Playwright test against game-night-pwa.
#
# First run pattern - DRY (verify safety guard fires):
#   .\scripts\test-inbox-run.ps1
#
# After verifying the guard works and manually deleting the created user:
#   .\scripts\test-inbox-run.ps1 -AllowCleanup
#
# The -AllowCleanup switch sets PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true
# inline for THIS RUN ONLY. Per ADR-0014, never set it in your shell
# profile - the alias-prefix guard is the only thing standing between a
# typo and real-user deletion.

[CmdletBinding()]
param(
  [switch]$AllowCleanup,

  [string]$HostToken,
  [string]$NightId,

  [string]$ApiBase    = "https://pufsqfvq8g.execute-api.us-east-2.amazonaws.com/prod",
  [string]$TesterEmail = "jaetill@gmail.com",
  [string]$SecretName  = "platform/test-inbox/gmail-tester",
  [string]$Region      = "us-east-2",

  [string]$GameNightPwaPath = "E:\Users\tille\Documents\Source Code\game-night-pwa"
)

$ErrorActionPreference = 'Stop'

# 1. Pull Gmail tester creds from Secrets Manager
Write-Host "Pulling Gmail tester creds from $SecretName..."
$secretJson = aws secretsmanager get-secret-value `
  --secret-id $SecretName `
  --region $Region `
  --query SecretString --output text 2>$null

if (-not $secretJson) {
  Write-Error "Could not fetch $SecretName from Secrets Manager. Did you run test-inbox-push-secrets.ps1 first?"
  exit 1
}
$secret = $secretJson | ConvertFrom-Json
Write-Host "[OK] retrieved (clientId len $($secret.clientId.Length), refreshToken len $($secret.refreshToken.Length))"

# 2. Prompt for per-run inputs
if (-not $HostToken) {
  Write-Host ""
  Write-Host "Capture Cognito host ID token:"
  Write-Host "  1. Sign in to https://gamenights.jaetill.com as the test host"
  Write-Host "  2. DevTools -> Application -> Local Storage -> the .idToken key"
  Write-Host "  3. Copy the full JWT (three dot-separated parts)"
  Write-Host ""
  $secure = Read-Host -AsSecureString -Prompt "Paste Cognito ID token"
  $HostToken = [System.Net.NetworkCredential]::new("", $secure).Password
}

if (-not $NightId) {
  Write-Host ""
  Write-Host "Identify the test game night:"
  Write-Host "  Inspect available game nights:"
  Write-Host "    aws s3 cp s3://jaetill-game-nights/gameNights.json - | ConvertFrom-Json | Select-Object id, hostUserId, date, location"
  Write-Host "  Pick one where hostUserId matches the captured token's user."
  Write-Host ""
  $NightId = Read-Host -Prompt "Paste game night id"
}

# 3. Set env vars (LOCAL to this script's session only)
$env:GMAIL_TESTER_EMAIL          = $TesterEmail
$env:GMAIL_TESTER_CLIENT_ID      = $secret.clientId
$env:GMAIL_TESTER_CLIENT_SECRET  = $secret.clientSecret
$env:GMAIL_TESTER_REFRESH_TOKEN  = $secret.refreshToken
$env:GAME_NIGHT_API_BASE         = $ApiBase
$env:GAME_NIGHT_HOST_AUTH_TOKEN  = $HostToken
$env:GAME_NIGHT_TEST_NIGHT_ID    = $NightId

if ($AllowCleanup) {
  $env:PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP = "true"
  Write-Host ""
  Write-Host "  [!] PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP=true (cleanup ENABLED)"
} else {
  # Belt-and-braces: make sure it's NOT set, even if the user accidentally
  # exported it globally.
  Remove-Item Env:\PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP -ErrorAction SilentlyContinue
  Write-Host ""
  Write-Host "  DRY RUN - cleanup guard will fire after assertions complete."
  Write-Host "  If everything passes, manually delete the created user via:"
  Write-Host "    AWS Console -> Cognito -> us-east-2_xneeJzaDJ -> users -> search 'jaetill+gn-'"
}

# 4. Run the test
Write-Host ""
Write-Host "Running admin-invite-flow test..."
Push-Location $GameNightPwaPath
try {
  npx playwright test admin-invite-flow
  $rc = $LASTEXITCODE
} finally {
  Pop-Location

  # Always strip per-run sensitive env after the test, even on failure
  Remove-Item Env:\GMAIL_TESTER_CLIENT_SECRET -ErrorAction SilentlyContinue
  Remove-Item Env:\GMAIL_TESTER_REFRESH_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:\GAME_NIGHT_HOST_AUTH_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:\PLATFORM_TEST_INBOX_ALLOW_PROD_CLEANUP -ErrorAction SilentlyContinue
}

Write-Host ""
if ($rc -eq 0) {
  Write-Host "[OK] Test passed."
} else {
  Write-Host "[!] Test exited with code $rc - see Playwright output above."
}
exit $rc
