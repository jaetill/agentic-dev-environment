# configure-deploy-protection.ps1 — ADR-0043 phase 1
#
# Creates/updates GitHub Environments with a required-reviewer protection rule
# so every prod deploy waits for the maintainer's approval. Idempotent: PUT
# replaces the environment's protection settings; re-running converges.
#
# Per ADR-0043:
#   - game-night-pwa, splendor  -> protect the existing `github-pages` env
#     (deploy.yml already targets it; docs.yml is build-only and unaffected).
#   - meal-planner, jaetill-portal, draft, carto -> create/protect `production`
#     (each repo's deploy.yml gains `environment: production` in a paired PR).
#   - ai-teacher -> deferred to phase 2 (Vercel auto-deploy bypasses GitHub;
#     converts directly to Actions-driven deploy behind the protected env).
#
# Usage: pwsh scripts/configure-deploy-protection.ps1   (requires gh auth as the maintainer)

$ErrorActionPreference = 'Stop'

$reviewerId = (gh api user --jq '.id')
if (-not $reviewerId) { throw "Could not resolve the authenticated user's id via 'gh api user'." }
Write-Host "Required reviewer: user id $reviewerId"

$targets = @(
    @{ repo = 'game-night-pwa'; env = 'github-pages' },
    @{ repo = 'splendor';       env = 'github-pages' },
    @{ repo = 'meal-planner';   env = 'production' },
    @{ repo = 'jaetill-portal'; env = 'production' },
    @{ repo = 'draft';          env = 'production' },
    @{ repo = 'carto';          env = 'production' }
    # ai-teacher: phase 2 (ADR-0043) — Vercel conversion issue tracks it.
)

foreach ($t in $targets) {
    $body = @{ reviewers = @(@{ type = 'User'; id = [int]$reviewerId }) } | ConvertTo-Json -Depth 4
    $tmp = New-TemporaryFile
    [System.IO.File]::WriteAllText($tmp.FullName, $body, (New-Object System.Text.UTF8Encoding($false)))
    gh api -X PUT "repos/jaetill/$($t.repo)/environments/$($t.env)" --input $tmp.FullName | Out-Null
    Remove-Item $tmp.FullName
    # Verify
    $check = gh api "repos/jaetill/$($t.repo)/environments/$($t.env)" | ConvertFrom-Json
    $hasReviewer = ($check.protection_rules | Where-Object { $_.type -eq 'required_reviewers' }) -ne $null
    Write-Host ("{0}/{1}: required_reviewers={2}" -f $t.repo, $t.env, $hasReviewer)
    if (-not $hasReviewer) { throw "Protection rule missing on $($t.repo)/$($t.env)" }
}
Write-Host "Deploy protection converged across the fleet (ADR-0043 phase 1)."
