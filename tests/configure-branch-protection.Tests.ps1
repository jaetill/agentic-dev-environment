#requires -Version 5.1
#requires -Module Pester

BeforeAll {
  # Dot-source only the function under test; suppress the top-level loop.
  $script = Get-Content "$PSScriptRoot/../scripts/configure-branch-protection.ps1" -Raw

  # Strip the foreach loop at the bottom so importing the file doesn't invoke gh.
  $stubbed = $script -replace '(?s)foreach \(\$repo in \$repos\.Keys\).*', ''
  Invoke-Expression $stubbed
}

Describe 'New-ProtectionBody' {
  It 'sets enforce_admins to $true so admins cannot bypass branch protection' {
    $body = New-ProtectionBody
    $body.enforce_admins | Should -Be $true
  }

  It 'sets allow_force_pushes to $false' {
    $body = New-ProtectionBody
    $body.allow_force_pushes | Should -Be $false
  }

  It 'sets allow_deletions to $false' {
    $body = New-ProtectionBody
    $body.allow_deletions | Should -Be $false
  }

  It 'requires linear history' {
    $body = New-ProtectionBody
    $body.required_linear_history | Should -Be $true
  }

  It 'sets strict = $false on required_status_checks (ADR-0021)' {
    $body = New-ProtectionBody
    $body.required_status_checks.strict | Should -Be $false
  }

  It 'includes all 5 canonical required status checks' {
    $body = New-ProtectionBody
    $contexts = $body.required_status_checks.checks | ForEach-Object { $_.context }
    $contexts | Should -Contain 'review / code-review'
    $contexts | Should -Contain 'review / security-review'
    $contexts | Should -Contain 'review / functional-test'
    $contexts | Should -Contain 'review / e2e-test'
    $contexts | Should -Contain 'review / destructive-change-check'
  }
}
