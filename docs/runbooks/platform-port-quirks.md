# Platform Port Quirks

A living catalog of project-specific adaptations that came up while applying the platform's inlined CI workflows + quality gates to existing projects. Each entry names the symptom, the cause, the fix, and where it first appeared. Read this before starting a new platform port; add to it after.

**Why this exists.** The platform's `.github/workflows/*.yml` and quality-gate configs were authored against game-night-pwa and copy-inlined into sibling projects. They bake in assumptions (stack versions, directory layout) that don't always hold. Until those workflows graduate to reusable `workflow_call` or composite actions (see [TODO_apply_platform_to_itself.md](../../TODO_apply_platform_to_itself.md)), each port has to scan for and apply these adaptations manually.

**How to use this.** When porting a new project:

1. Read each entry. For each, check whether your project hits the trigger condition (described under **When it bites**).
2. Apply the fix before pushing the Phase 3 or Phase 4 PR — saves a fix-up commit cycle.
3. When CI surfaces something new, add an entry here.

**Format per entry.**

- **Symptom** — what the failing CI / lint / commit looks like.
- **Cause** — why it happened.
- **Fix** — exact change to make.
- **When it bites** — heuristic to predict whether a project will hit this.
- **First seen** — project + PR + date.

---

## 0. First graduation: the `install-node-deps` composite action

Quirks #1 and #2 below have been folded into a workspace composite action so projects subscribing to the platform don't have to know about them.

**Action location:** `actions/install-node-deps/` in the workspace, referenced as:

```yaml
- uses: jaetill/agentic-dev-environment/actions/install-node-deps@main
```

**What it does:** sets up Node.js, runs `npm ci --legacy-peer-deps` for root, and conditionally runs the same for `lambda/` IF `lambda/package.json` exists. Replaces a 4-step inlined block per use site.

**Important: requires the workspace to be public** (or you to use a PAT for auth). The first attempt at this action with a private workspace failed with "Unable to resolve action `jaetill/agentic-dev-environment`" because GitHub Actions' built-in `GITHUB_TOKEN` can't read other private repos owned by the same user, even with `actions/permissions/access` set to `user`. Documented behavior; not a bug. Same-org-and-Team-plan unlocks this for private cross-repo but $48/yr per seat. Public workspace was the cheaper path.

**When to use it.** Any new platform-port project. The previous inlined pattern (a 4-step install-with-conditional-lambda block) is now redundant; reference the composite action instead.

**First seen.** Workspace `a6ac53f` (action authored) + portal PR #5 (first consumer), 2026-05-16.

---

## 1. `npm ci` fails with peer-dep mismatch on Vite 8 projects

**Symptom.**

```
npm error code EUSAGE
npm error `npm ci` can only install packages when your package.json and
package-lock.json or npm-shrinkwrap.json are in sync.
npm error Missing: typescript@6.0.3 from lock file
npm error Invalid: lock file's esbuild@0.21.5 does not satisfy esbuild@0.28.0
```

Or, on `npm install` without `--legacy-peer-deps`:

```
npm error ERESOLVE could not resolve
npm error While resolving: @tailwindcss/vite@4.2.x
npm error Found: vite@8.0.x
npm error Could not resolve dependency:
npm error peerOptional vite@"^5.0.0" from @tailwindcss/vite
```

**Cause.** `@tailwindcss/vite` (Tailwind 4's Vite plugin) declares Vite 5 as its peer range. Vite 8 is widely working but the package hasn't bumped its peer range. Strict `npm ci` rejects the resolution.

**Fix.** Patch every `npm ci` call in workflows to `npm ci --legacy-peer-deps`. Same for any local install instructions in README. The `--legacy-peer-deps` flag tells npm to install with npm 6's permissive peer-resolution semantics.

In workflows to patch (anywhere `npm ci` appears):

- `.github/workflows/claude-pr-review.yml` (typically 5+ occurrences)
- `.github/workflows/claude-implementer.yml` (typically 6+ occurrences)
- `.github/workflows/deploy.yml` (the deploy job's install step)

PowerShell one-liner to apply across all workflows in the project:

```powershell
Get-ChildItem .github\workflows\*.yml | ForEach-Object {
  $c = [System.IO.File]::ReadAllText($_.FullName, [System.Text.UTF8Encoding]::new($false))
  $c = $c -replace 'npm ci(?=[\s\r\n]|$)', 'npm ci --legacy-peer-deps'
  [System.IO.File]::WriteAllText($_.FullName, $c, [System.Text.UTF8Encoding]::new($false))
}
```

**When it bites.** Projects using Vite 8+ and `@tailwindcss/vite`. Check `package.json` devDependencies.

**First seen.** jaetill-portal Phase 4 (PR #4 fix-up commit `a4a5bc1`, 2026-05-16).

---

## 2. Lambda npm install fails when project has no `lambda/package.json`

**Symptom.**

```
npm error code ENOLOCK
npm error audit This command requires an existing lockfile.
npm error audit Try creating one first with: npm i --package-lock-only
```

Or:

```
npm ci --prefix lambda
npm error path /path/to/lambda
npm error errno -2
npm error syscall open
npm error enoent ENOENT: no such file or directory, open 'lambda/package.json'
```

**Cause.** game-night-pwa's workflows assume `lambda/package.json` exists (it has Sentry, octokit, and other Lambda-side deps). When a project's Lambda has no third-party deps and uses only the AWS SDK provided at runtime, no `lambda/package.json` exists.

**Fix in workflows.** Wrap lambda install calls in a file-existence guard:

```yaml
- run: |
    npm ci --legacy-peer-deps
    [ -f lambda/package.json ] && npm ci --legacy-peer-deps --prefix lambda || echo "no lambda/package.json, skipping"
```

**Fix in `security-scan.yml`.** Drop the "Audit lambda deps" step entirely. When the project later grows a `lambda/package.json`, add the step back guarded the same way.

**When it bites.** Projects whose Lambdas use only AWS SDK (zero npm deps). Check whether `lambda/package.json` exists.

**First seen.** jaetill-portal Phase 4 (PR #4 fix-up commit `a4a5bc1`, 2026-05-16).

---

## 3. Branch convention: `master` vs `main`

**Symptom.** Workflows reference `branches: [master]` but the project's default branch is `main` (or vice versa). The workflow never triggers, or triggers on a non-existent branch.

**Cause.** game-night-pwa and meal-planner are on `master` (legacy). Newer projects (ai-teacher, jaetill-portal, workspace) are on `main`. The platform's inlined workflow templates default to `master`.

**Fix.** Find-replace across all workflow files:

```powershell
Get-ChildItem .github\workflows\*.yml | ForEach-Object {
  $c = [System.IO.File]::ReadAllText($_.FullName, [System.Text.UTF8Encoding]::new($false))
  $c = $c.Replace('branches: [master]', 'branches: [main]')
  [System.IO.File]::WriteAllText($_.FullName, $c, [System.Text.UTF8Encoding]::new($false))
}
```

`claude-implementer.yml` also has a hardcoded PR URL check that needs project-name replacement:

```
startsWith(github.event.issue.pull_request.html_url, 'https://github.com/jaetill/<source-project>/pull/')
```

Replace `<source-project>` with the new project's name.

**When it bites.** Every new port that branches off `main`.

**First seen.** ai-teacher migration (2026-05-16), again on jaetill-portal Phase 4 (2026-05-16).

---

## 4. `.claude/settings.local.json` accidentally committed

**Symptom.** First Phase 1+2 commit includes `.claude/settings.local.json` with personal allowlist entries (Bash patterns, PowerShell command grants).

**Cause.** `.claude/settings.local.json` is created by Claude Code when the user accepts a non-default permission grant. It's per-user, per-machine state. Sibling projects gitignore it, but the platform's `.gitignore` template doesn't include it by default — and a fresh `git add -A` will pick it up.

**Fix in the Phase 1+2 PR.** Before the initial `git add`:

```powershell
# Append to .gitignore before staging
@'

# Personal Claude Code permission grants — per-user, per-machine
.claude/settings.local.json
'@ | Out-File -Append -Encoding utf8 .gitignore
```

If already committed in a previous commit on the branch, add a fix-up:

```sh
git rm --cached .claude/settings.local.json
echo '.claude/settings.local.json' >> .gitignore
git add .gitignore
git commit -m "chore: untrack .claude/settings.local.json (personal local settings)"
```

If it shipped to a public branch and you want it scrubbed from history: see "Scrubbing personal allowlist entries from git history" below.

**When it bites.** Every new project port where the local working tree has been touched by Claude Code with custom permission grants.

**First seen.** jaetill-portal PR #2 (2026-05-16) — required a fix-up commit, then a history rewrite to scrub the contents.

---

## 5. `vitest.config.js` references critical-path coverage files that don't exist

**Symptom.** `vitest run --coverage` fails with "file not found" against paths like `lambda/nudge.js` that don't exist in the target project.

**Cause.** Copy-inlined vitest config from game-night-pwa includes per-file coverage thresholds (e.g., `lambda/nudge.js: { lines: 85, branches: 75 }`) that name specific source files. Those files don't exist in other projects.

**Fix.** When copying `vitest.config.js`, strip the per-file thresholds. Keep only the global threshold structure. Add per-file thresholds back when the target project grows the corresponding files with tests.

For a brand-new project with no tests yet, omit thresholds entirely and rely on `--passWithNoTests`. Document this in the project's ADR-0001.

**When it bites.** Any project whose source layout doesn't match the source-of-template project.

**First seen.** jaetill-portal Phase 3 (PR #3, 2026-05-16) — caught in pre-port survey.

---

## 6. Husky hooks fail commitlint on long lines in commit body

**Symptom.**

```
✖   body's lines must not be longer than 100 characters [body-max-line-length]
✖   footer's lines must not be longer than 100 characters [footer-max-line-length]
husky - commit-msg script failed (code 1)
```

**Cause.** commitlint config enforces 100-char limits on body lines (warn) and footer lines (error). PowerShell here-strings produce long single-line paragraphs when commit messages are passed as `-m "long single line"`.

**Fix.** Pass commit messages via `-F <file>` from a UTF-8 (no BOM) file with hard wraps at 80–100 cols. Avoid `git commit -m "long..."` for any body content.

```powershell
$msg = "type(scope): subject`n`nBody paragraph 1, wrapped to 80 cols.`nMore body lines.`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("$env:TEMP\msg.txt", $msg, $utf8)
git commit -F "$env:TEMP\msg.txt"
```

`Out-File -Encoding utf8` adds a BOM that breaks commitlint's header parse ("header must not start with whitespace"). Always use `[System.IO.File]::WriteAllText` with the explicit no-BOM encoder.

**When it bites.** Any commit authored from PowerShell with substantial body content.

**First seen.** jaetill-portal Phase 4 fix-up (2026-05-16).

---

## 7. PowerShell here-string mojibake for em-dashes (and other non-ASCII)

**Symptom.** File content shows `â€"` where you expected `—` (em-dash). Same pattern for other UTF-8 chars (`'` → `â€™`, `"` → `â€œ`).

**Cause.** PowerShell here-strings (`@'...'@`) sometimes interpret content as cp1252 before re-encoding. When `[System.IO.File]::WriteAllText(..., $utf8)` then writes those bytes, they end up double-encoded.

**Fix.** When writing files via PowerShell, prefer plain ASCII characters in commit messages, JSON comments, and any content that will pass through a PowerShell here-string. Use `-` for em-dash, `'` for curly apostrophe, `"` for curly quotes. The file content stays semantically equivalent and round-trips cleanly through any tool.

If you really need a UTF-8 char, build the string in code:

```powershell
$emDash = [char]0x2014
$content = "Sentence" + $emDash + "with em-dash."
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
```

**When it bites.** Any file written via PowerShell with non-ASCII content.

**First seen.** workspace `.claude/settings.json` write (2026-05-16), meal-planner CLAUDE.md edit (2026-05-16) — both required redo.

---

## 8. `anthropics/claude-code-action` refuses to validate workflow changes in a PR

**Symptom.**

```
##[error]Action failed with error: Workflow validation failed. The workflow file
must exist and have identical content to the version on the repository's default
branch. If you're seeing this on a PR when you first add a code review workflow
file to your repository, this is normal and you should ignore this error.
```

Fires when any of the `claude-pr-review.yml` job steps fail in jobs like `code-review`, `security-review`, `doc-keeper`, `test-writer`, `functional-test`, `e2e-test`.

**Cause.** Security feature of the `anthropics/claude-code-action`. It refuses to run when the workflow file in the PR's HEAD differs from the version on the default branch. Prevents a PR from rewriting the action to do malicious things and self-approving.

**Fix.** Admin-merge the workflow change to `main` once, then any subsequent PRs work cleanly. This is the documented bypass — the error message itself says "this is normal" for first-add scenarios.

**When it bites.** Any PR that modifies a workflow file consumed by `anthropics/claude-code-action`.

**First seen.** Portal PR #5 (composite action introduction) and earlier on PR #2 (the initial Phase 1+2 install), 2026-05-16.

---

## 9. Finding-lifecycle policy is now in effect (calibration + deferral + Sentry pickup)

**Effective:** workspace commit landing ADR-0016 (2026-05-16 and later).

**What changes for consumers:**

- Reviewer-style agents (`code-reviewer`, `security-reviewer`, `triage-bot`, `doc-keeper`) will surface fewer Critical findings and more Low / Nit findings. The Criticals you DO see should be more reliable signal.
- Reviewer agents will file low-severity findings as GitHub issues at **low/nit severity (`severity:low,severity:nit`)** — the nit tier IS the deferred tier; no separate label (ADR-0037). These accumulate in your issue backlog but **do not trigger the implementer**. Medium and above never defer (ADR-0037).
- Implementer will scan adjacent deferred issues and bundle up to **2 per feature PR** into a "While here" section. Expect feature PRs to occasionally touch additional small files - this is intentional.
- Issues labeled `source:sentry` (auto-applied by Sentry's GitHub integration when its alert rules create issues) or `severity:critical` will trigger the implementer immediately, even without `ready-for-implementer`. Sentry-reported bugs no longer need manual triage to start being fixed.

**Consumer-side workflow change required:**

Each consuming project's `.github/workflows/claude-implementer.yml` needs its trigger updated to fire on the additional labels. Look for the `on: issues:` block and adjust:

```yaml
on:
  issues:
    types: [labeled]
# Existing pattern triggers on `ready-for-implementer` label.
# Add Sentry + critical-severity labels as alternative triggers.
```

The implementer's prompt already understands these labels (per the updated `implementer.md`); only the workflow trigger needs to be widened. A follow-up commit on each consuming project will handle this; the implementer will be Sentry-aware after that ships.

**Issue label setup required (per project):**

Each consuming project should have these labels available (creates idempotently — no-op if already present):

```sh
gh label create severity:critical --description "Critical-severity finding; triggers immediate implementer pickup" --color "b60205" --force
gh label create severity:high --description "High-severity finding" --color "d93f0b" --force
gh label create severity:medium --description "Medium-severity finding" --color "fbca04" --force
gh label create severity:low --description "Low-severity finding; deferred (nit tier is the deferred tier, ADR-0037)" --color "0e8a16" --force
gh label create severity:nit --description "Nit-severity finding; deferred (nit tier is the deferred tier, ADR-0037)" --color "0e8a16" --force
```

**Note:** the `source:sentry` label is applied by Sentry's own GitHub integration (configured in Sentry's alert rules) — no separate platform-side label create or auto-labeler workflow is needed. If a consuming project's Sentry integration isn't applying `source:sentry` automatically, configure it in Sentry's UI: Settings → Integrations → GitHub → alert rule → "Add labels to created issue: `source:sentry`".

**Expected backlog growth.** With low/nit findings now being filed instead of inlined into PR comments, the open issue count will rise. This is expected. The quarterly sweep is the escape valve; the 180-day re-triage limit is the hard floor.

**First seen.** Platform workspace, post-ADR-0016 ship (2026-05-16).

---

## Scrubbing personal allowlist entries from git history

If `.claude/settings.local.json` made it into git history (see entry #4), and you want the contents removed from `refs/heads/main`:

```powershell
cd <project-repo>
git checkout main
git pull --ff-only

# Save current HEAD for rollback
$beforeSha = git rev-parse HEAD

# Disable branch protection (will re-enable)
gh api -X DELETE "repos/<owner>/<repo>/branches/main/protection"

# Rewrite history to remove the file from all commits
$env:FILTER_BRANCH_SQUELCH_WARNING = '1'
git filter-branch --force --index-filter `
  "git rm --cached --ignore-unmatch .claude/settings.local.json" `
  --prune-empty -- --all

# Force-push the rewritten main
git push --force origin main

# Force-push any open feature/release branches the rewrite touched
git for-each-ref refs/remotes/origin/ --format='%(refname:short)' | ForEach-Object {
  $br = $_ -replace 'origin/', ''
  if ($br -ne 'HEAD' -and $br -ne 'main') {
    git push --force origin "refs/remotes/origin/$br`:refs/heads/$br"
  }
}

# Re-enable branch protection with the same required checks as before
gh api -X PUT "repos/<owner>/<repo>/branches/main/protection" `
  -F required_status_checks[strict]=true `
  -F "required_status_checks[contexts][]=code-review" `
  -F "required_status_checks[contexts][]=security-review" `
  -F "required_status_checks[contexts][]=destructive-change-check" `
  -F "required_status_checks[contexts][]=gitleaks" `
  -F "required_status_checks[contexts][]=npm-audit" `
  -F enforce_admins=false -F required_pull_request_reviews=null `
  -F restrictions=null -F required_linear_history=false `
  -F allow_force_pushes=false -F allow_deletions=false

# Local cleanup
git update-ref -d refs/original/refs/heads/main
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

**Important caveat.** filter-branch removes the file from every branch tip but the **old commit SHAs remain in GitHub's object store** as "unreachable" objects, accessible by direct URL until GitHub GC's them (no published schedule). For full purge, options are:

1. Accept the partial scrub (fine for personal allowlist entries on a private repo with vetted collaborators).
2. Delete + recreate the repo from the rewritten state.
3. Contact GitHub Support to request expedited GC of unreachable objects in the private repo.

---

## Future graduation path

When a pattern shows up across multiple projects, extract it into a workspace composite action at `actions/<name>/action.yml` and reference it from per-project workflows. This converts entries here into infrastructure code.

**First graduation:** `install-node-deps` (entries #1 and #2 above). The workspace had to go public for cross-repo composite action consumption to work from same-user private projects. If you'd kept it private, the alternative was a Team-plan org transfer ($48/yr/seat).

When a whole workflow stabilizes across projects, consider converting it to `workflow_call` so projects reference the workspace's version instead of inlining. Same cross-repo auth caveat applies.

This catalog should shrink over time as patterns graduate.
