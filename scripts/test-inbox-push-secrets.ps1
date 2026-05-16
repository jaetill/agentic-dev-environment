# One-time: push Gmail OAuth creds to AWS Secrets Manager.
#
# Run this once after Step 2 of HANDOFF_email_testing_setup.md (after
# you have client_id + client_secret + refresh_token in hand).
#
# Usage:
#   .\scripts\test-inbox-push-secrets.ps1
#
# Or with all 3 inline:
#   .\scripts\test-inbox-push-secrets.ps1 `
#     -ClientId "..." -ClientSecret "..." -RefreshToken "..."
#
# Idempotent: tries `create-secret` first; if it exists, falls back to
# `put-secret-value` (updates the existing value).

[CmdletBinding()]
param(
  [string]$ClientId,
  [string]$ClientSecret,
  [string]$RefreshToken,
  [string]$SecretName = "platform/test-inbox/gmail-tester",
  [string]$Region = "us-east-2"
)

$ErrorActionPreference = 'Stop'

# Prompt for anything missing (secure entry for the secrets)
if (-not $ClientId) {
  $secure = Read-Host -AsSecureString -Prompt "Paste Gmail OAuth client_id"
  $ClientId = [System.Net.NetworkCredential]::new("", $secure).Password
}
if (-not $ClientSecret) {
  $secure = Read-Host -AsSecureString -Prompt "Paste Gmail OAuth client_secret"
  $ClientSecret = [System.Net.NetworkCredential]::new("", $secure).Password
}
if (-not $RefreshToken) {
  $secure = Read-Host -AsSecureString -Prompt "Paste Gmail OAuth refresh_token"
  $RefreshToken = [System.Net.NetworkCredential]::new("", $secure).Password
}

$secretJson = @{
  clientId     = $ClientId
  clientSecret = $ClientSecret
  refreshToken = $RefreshToken
} | ConvertTo-Json -Compress

# Write JSON to a temp file and pass via file:// to AWS CLI. This bypasses
# PowerShell's argument-quoting quirks that strip JSON quotes when passing
# directly via --secret-string.
$tmpFile = New-TemporaryFile
try {
  [System.IO.File]::WriteAllText($tmpFile.FullName, $secretJson)
  $secretArg = "file://$($tmpFile.FullName)"

  # Locally relax ErrorActionPreference around AWS calls: their CLI writes
  # to stderr for harmless info (version warnings, etc.) which PowerShell's
  # 'Stop' policy treats as terminating errors. We check $LASTEXITCODE.
  $savedEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'

  Write-Host ""
  Write-Host "Attempting create-secret in $Region..."
  $createOutput = aws secretsmanager create-secret `
    --name $SecretName `
    --region $Region `
    --secret-string $secretArg 2>&1 | Out-String
  $createRc = $LASTEXITCODE

  if ($createRc -eq 0) {
    Write-Host "[OK] Secret created."
  } else {
    if ($createOutput -match "ResourceExistsException|already exists") {
      Write-Host "  Secret exists; falling back to put-secret-value..."
      $updateOutput = aws secretsmanager put-secret-value `
        --secret-id $SecretName `
        --region $Region `
        --secret-string $secretArg 2>&1 | Out-String
      $updateRc = $LASTEXITCODE
      if ($updateRc -eq 0) {
        Write-Host "[OK] Secret updated."
      } else {
        $ErrorActionPreference = $savedEAP
        Write-Error "Failed to update secret: $updateOutput"
        exit 1
      }
    } else {
      $ErrorActionPreference = $savedEAP
      Write-Error "Failed to create secret: $createOutput"
      exit 1
    }
  }

  $ErrorActionPreference = $savedEAP
} finally {
  # Always wipe the temp file, even on failure
  if (Test-Path $tmpFile.FullName) {
    Remove-Item $tmpFile.FullName -Force
  }
}

Write-Host ""
Write-Host "Verifying..."
$savedEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$verifyRaw = aws secretsmanager get-secret-value `
  --secret-id $SecretName `
  --region $Region `
  --query SecretString --output text 2>&1 | Out-String
$ErrorActionPreference = $savedEAP
$verify = $verifyRaw.Trim() | ConvertFrom-Json

if ($verify.refreshToken) {
  Write-Host "[OK] Verified: secret contains clientId, clientSecret, refreshToken (lengths $($verify.clientId.Length), $($verify.clientSecret.Length), $($verify.refreshToken.Length))"
} else {
  Write-Error "Verification failed."
  exit 1
}

Write-Host ""
Write-Host "Done. Next: run scripts\test-inbox-run.ps1 to execute the test."
