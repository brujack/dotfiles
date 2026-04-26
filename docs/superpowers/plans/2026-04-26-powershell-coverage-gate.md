# PowerShell Coverage Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `powershell/setup_windows.ps1` to ≥90% line coverage and enforce the floor locally and in CI.

**Architecture:** Pester 5's built-in `-CodeCoverage` measures per-file line coverage and emits a JaCoCo XML report. The gate is a `Write-Error; exit 1` block in `run-tests.ps1` keyed off `$result.CodeCoverage.CoveragePercent`. CI gains a new `powershell` job (ubuntu-latest, installs pwsh + Pester + PSScriptAnalyzer) that runs `make test` and is added to `auto-merge` dependencies.

**Tech Stack:** Pester ≥5.0, PSScriptAnalyzer, pwsh (PowerShell Core), GitHub Actions, BATS-adjacent (no BATS changes here).

**Spec:** `docs/superpowers/specs/2026-04-26-powershell-coverage-gate-design.md`

**Branch:** continue on `spec/powershell-coverage-gate` (already pushed by brainstorming step). All commits land on this branch; merge to master via PR with CI auto-merge.

---

## Pre-Flight

### Task 0: Verify environment

**Files:** none

- [ ] **Step 1: Confirm Pester ≥ 5.0 is installed**

Run:

```bash
pwsh -Command "Get-Module -ListAvailable Pester | Select-Object Version"
```

Expected: at least one row showing `Version 5.x.y`. If not, install:

```bash
pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
```

- [ ] **Step 2: Confirm PSScriptAnalyzer is installed**

Run:

```bash
pwsh -Command "Get-Module -ListAvailable PSScriptAnalyzer | Select-Object Version"
```

Expected: at least one row. If not:

```bash
pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"
```

- [ ] **Step 3: Confirm baseline test suite is green**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

Expected: PSScriptAnalyzer prints nothing; Pester reports `Tests Passed: 22, Failed: 0, Skipped: 0`. If this fails, stop and fix before proceeding — no point measuring coverage of a broken suite.

- [ ] **Step 4: Confirm we're on the spec branch**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles && git status -sb
```

Expected: `## spec/powershell-coverage-gate` on the first line. If on `master`, run `git checkout spec/powershell-coverage-gate`.

---

## Phase 1 — Wire coverage measurement (no gate yet)

### Task 1: Add coverage instrumentation to run-tests.ps1

**Files:**

- Modify: `powershell/run-tests.ps1` (the Pester block at lines 17-22)

- [ ] **Step 1: Replace the Pester block with coverage-enabled config (no gate)**

Open `powershell/run-tests.ps1` and replace lines 17-22 (`Import-Module Pester` through `Invoke-Pester -Configuration $config`) with:

```powershell
Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = 'tests/'
$config.Run.Exit = $true
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './setup_windows.ps1'
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = './coverage.xml'
$result = Invoke-Pester -Configuration $config

if ($null -eq $result.CodeCoverage) {
    Write-Error "Pester returned no CodeCoverage result - verify Pester >= 5.0"
    exit 1
}
Write-Host ""
Write-Host "Coverage: $($result.CodeCoverage.CoveragePercent)%"
```

Note: gate intentionally not added yet. We measure baseline first.

- [ ] **Step 2: Run the suite and capture the baseline percentage**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

Expected: 22 tests pass; final line prints `Coverage: <N>%` and `coverage.xml` is written. Record `<N>` — you will need it in Phase 2 and again in Task 6.

- [ ] **Step 3: Verify coverage.xml was written**

Run:

```bash
ls -la /Users/bruce/git-repos/personal/dotfiles/powershell/coverage.xml
```

Expected: file exists, non-empty.

- [ ] **Step 4: Commit instrumentation**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git add powershell/run-tests.ps1
git commit -m "$(cat <<'EOF'
test(powershell): enable Pester code coverage measurement

Adds -CodeCoverage instrumentation to run-tests.ps1 with JaCoCo output.
No gate yet - baseline measurement first, gate enabled in a later commit
once we are at >=90%.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 2: Git-ignore coverage report

**Files:**

- Modify: `.gitignore`

- [ ] **Step 1: Append the ignore entry**

Add to the end of `.gitignore`:

```
# Pester coverage output
powershell/coverage.xml
```

- [ ] **Step 2: Verify the file is now ignored**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles && git check-ignore powershell/coverage.xml && echo "ignored"
```

Expected: prints `powershell/coverage.xml` then `ignored`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
chore: ignore powershell/coverage.xml

Pester writes the JaCoCo report to ./coverage.xml on each run; it is a
build artifact, not source.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Identify gaps and add tests

### Task 3: Read the JaCoCo report and triage gaps

**Files:** none (analysis only)

- [ ] **Step 1: Re-run tests to ensure coverage.xml is fresh**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

- [ ] **Step 2: Extract per-method missed/covered counts**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && \
  pwsh -NoProfile -Command "
    [xml]\$x = Get-Content ./coverage.xml
    \$x.report.package.class.method | ForEach-Object {
      \$line = \$_.counter | Where-Object { \$_.type -eq 'LINE' }
      [PSCustomObject]@{
        Name    = \$_.name
        Missed  = [int]\$line.missed
        Covered = [int]\$line.covered
      }
    } | Sort-Object Missed -Descending | Format-Table -AutoSize
  "
```

Expected: a table sorted by missed lines, e.g.:

```
Name                                Missed Covered
----                                ------ -------
Install-ChocolateyPackage                X       Y
Install-WindowsUpdate                    X       Y
...
```

- [ ] **Step 3: Read the source-level coverage details**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && \
  pwsh -NoProfile -Command "
    [xml]\$x = Get-Content ./coverage.xml
    \$x.report.package.sourcefile.line | Where-Object { [int]\$_.mi -gt 0 } |
      Select-Object @{n='Line';e={\$_.nr}}, @{n='Missed';e={\$_.mi}}, @{n='Covered';e={\$_.ci}} |
      Format-Table -AutoSize
  "
```

Expected: a list of line numbers in `setup_windows.ps1` with missed instructions. Cross-reference each against the source file to identify the uncovered branches.

- [ ] **Step 4: Decide on triage**

Based on the output, identify which functions need new tests. The likely list (subject to actual measurement):

| Function                                | Probable gap                                                                                                         |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Top-level `if ($IsWindows)` block       | The `$setup.IsPresent` and `$update.IsPresent` branches — no Describe block currently exercises them.                |
| `Install-WindowsUpdate`                 | The early-return branches when `$SearchResult` is empty for downloader and installer — partially covered, but check. |
| `Copy-GitConfig`                        | The `catch` block (Copy-Item failure).                                                                               |
| `New-DirectoryStructure`                | The `catch` block (New-Item failure).                                                                                |
| `Enable-RequiredWindowsOptionalFeature` | Multiple-feature branch (one disabled, multiple enabled).                                                            |
| `Install-WSL`                           | No `catch` exists — coverage for the existing two paths is likely already complete.                                  |

If the actual table differs, follow the data, not this list.

- [ ] **Step 5: No commit (analysis only)**

The coverage.xml is git-ignored. Move on to Task 4.

### Task 4: Extract dispatcher bodies into testable functions

**Files:**

- Modify: `powershell/setup_windows.ps1`
- Modify: `powershell/tests/setup_windows.Tests.ps1`

**Why this differs from earlier draft:** The first attempt tried to override `$global:IsWindows = $true` from a Pester `BeforeAll`. PowerShell rejects that — `$IsWindows` is a runtime-set automatic read-only variable. We pivot to a small refactor: pull the bodies of the `if ($setup.IsPresent)` and `if ($update.IsPresent)` blocks into named functions, then test those functions directly using the same Pester mocking pattern as the existing 22 tests.

The top-level `if ($IsWindows) { if ($setup.IsPresent) { Invoke-DotfilesSetup } if ($update.IsPresent) { Invoke-DotfilesUpdate } }` block remains as cross-platform-untestable glue — per tdd.md ("entry-point glue that purely calls already-tested functions") this is an allowed exclusion, documented in CLAUDE.md alongside the runner-script exclusion (Task 9).

- [ ] **Step 1: Refactor setup_windows.ps1 — extract dispatcher bodies into functions**

Open `powershell/setup_windows.ps1`. Replace the bottom block (currently lines 197-226 — the `if ($IsWindows) { if ($setup.IsPresent) { ... } if ($update.IsPresent) { ... } }` structure) with two new functions plus a slimmed dispatcher:

```powershell
function Invoke-DotfilesSetup {
  Set-WindowsOption
  Install-ChocolateyPackage
  Enable-RequiredWindowsOptionalFeature
  Install-WSL
  Set-ExecutionPolicy Unrestricted -Scope CurrentUser
  New-DirectoryStructure
  Copy-GitConfig
}

function Invoke-DotfilesUpdate {
  Write-Output "Updating chocolatey packages"
  choco upgrade all -y

  if (Test-Path -Path ./update_powershell_modules.ps1 -PathType Leaf) {
    try {
      Write-Output "Updating powershell modules"
      ./update_powershell_modules.ps1
    }
    catch {
      throw $_.Exception.Message
    }
  }

  Write-Output "Installing Windows Updates"
  Install-WindowsUpdate
}

if ($IsWindows) {
  if ($setup.IsPresent)  { Invoke-DotfilesSetup }
  if ($update.IsPresent) { Invoke-DotfilesUpdate }
}
```

PSScriptAnalyzer must remain clean — verb-noun naming (`Invoke-` is an approved verb) and singular nouns are preserved.

- [ ] **Step 2: Verify lint passes**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make lint
```

Expected: no PSScriptAnalyzer findings.

- [ ] **Step 3: Verify existing tests still pass after the refactor**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

Expected: 22/22 still pass. Coverage may change slightly (the function definitions add covered lines once `BeforeAll` dot-sources the script). If any existing test fails, the refactor is wrong — investigate before adding new tests.

- [ ] **Step 4: Add Pester tests for the new functions**

Append to `powershell/tests/setup_windows.Tests.ps1`:

```powershell
Describe "Invoke-DotfilesSetup" {
  BeforeEach {
    Mock Set-WindowsOption                     { }
    Mock Install-ChocolateyPackage             { }
    Mock Enable-RequiredWindowsOptionalFeature { }
    Mock Install-WSL                           { }
    Mock Set-ExecutionPolicy                   { }
    Mock New-DirectoryStructure                { }
    Mock Copy-GitConfig                        { }
  }

  It "calls Set-WindowsOption" {
    Invoke-DotfilesSetup
    Should -Invoke Set-WindowsOption -Times 1 -Exactly
  }
  It "calls Install-ChocolateyPackage" {
    Invoke-DotfilesSetup
    Should -Invoke Install-ChocolateyPackage -Times 1 -Exactly
  }
  It "calls Enable-RequiredWindowsOptionalFeature" {
    Invoke-DotfilesSetup
    Should -Invoke Enable-RequiredWindowsOptionalFeature -Times 1 -Exactly
  }
  It "calls Install-WSL" {
    Invoke-DotfilesSetup
    Should -Invoke Install-WSL -Times 1 -Exactly
  }
  It "calls Set-ExecutionPolicy with Unrestricted CurrentUser" {
    Invoke-DotfilesSetup
    Should -Invoke Set-ExecutionPolicy -ParameterFilter {
      $ExecutionPolicy -eq 'Unrestricted' -and $Scope -eq 'CurrentUser'
    } -Times 1 -Exactly
  }
  It "calls New-DirectoryStructure" {
    Invoke-DotfilesSetup
    Should -Invoke New-DirectoryStructure -Times 1 -Exactly
  }
  It "calls Copy-GitConfig" {
    Invoke-DotfilesSetup
    Should -Invoke Copy-GitConfig -Times 1 -Exactly
  }
}

Describe "Invoke-DotfilesUpdate" {
  BeforeEach {
    Mock choco                 { }
    Mock Install-WindowsUpdate { }
    Mock Test-Path             { $false }
    Mock Write-Output          { }
  }

  It "runs choco upgrade all -y" {
    Invoke-DotfilesUpdate
    Should -Invoke choco -ParameterFilter { $args -contains 'upgrade' -and $args -contains 'all' } -Times 1
  }
  It "calls Install-WindowsUpdate" {
    Invoke-DotfilesUpdate
    Should -Invoke Install-WindowsUpdate -Times 1 -Exactly
  }
  It "skips update_powershell_modules.ps1 when not present" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*update_powershell_modules.ps1' }
    { Invoke-DotfilesUpdate } | Should -Not -Throw
  }
}
```

- [ ] **Step 5: Run tests and verify they pass**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

Expected: 22 prior tests pass + 11 new tests pass = 33 tests. Coverage rises substantially from 75% baseline (toward ~92%). Note the new percentage.

- [ ] **Step 6: Commit**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "$(cat <<'EOF'
refactor(powershell): extract dispatcher into Invoke-DotfilesSetup/Update

Pulls the bodies of the if (\$setup.IsPresent) and if (\$update.IsPresent)
blocks into named functions so they can be tested directly with Pester
mocks. The top-level if (\$IsWindows) glue remains as untestable
cross-platform shim - excluded per tdd.md "entry-point glue" rule.

Necessary because \$IsWindows is a runtime read-only automatic variable
and cannot be overridden from BeforeAll, so the dispatcher could not
otherwise be exercised on macOS/Linux test runners.

Adds 11 Pester tests covering both new functions.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 5: Add error-path tests for filesystem functions

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1`

Per tdd.md mandatory categories, every function must have an error-path test. `Copy-GitConfig` and `New-DirectoryStructure` both have `try/catch` blocks that the existing tests don't exercise.

- [ ] **Step 1: Write the failing tests**

Inside the existing `Describe "Copy-GitConfig"` block, add a new `It` after the "skips copy when source does not exist" test:

```powershell
  It "rethrows when Copy-Item fails" {
    Mock Test-Path { $true }
    Mock Copy-Item { throw "disk full" }
    { Copy-GitConfig } | Should -Throw "disk full"
  }
```

Inside the existing `Describe "New-DirectoryStructure"` block, add a new `It` after the "skips both directories when they already exist" test:

```powershell
  It "rethrows when New-Item fails" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/.config' }
    Mock New-Item { throw "permission denied" }
    { New-DirectoryStructure } | Should -Throw "permission denied"
  }
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

Expected: every test passes; coverage percentage rises again.

- [ ] **Step 3: Commit**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git add powershell/tests/setup_windows.Tests.ps1
git commit -m "$(cat <<'EOF'
test(powershell): cover error paths in Copy-GitConfig and New-DirectoryStructure

Both functions wrap their core operation in try/catch and rethrow with
\$_.Exception.Message. The existing tests never made the inner cmdlet
fail, so the catch blocks were uncovered.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 6: Iterate until coverage ≥ 90%

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1` (further iterations)

- [ ] **Step 1: Re-measure**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test
```

Read the printed coverage percentage.

- [ ] **Step 2: Decide whether to continue**

| Outcome         | Action                                                                                                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Coverage ≥ 90%  | Skip to Task 7.                                                                                                                                                                    |
| Coverage 60–89% | Continue Step 3 below — find next gap.                                                                                                                                             |
| Coverage < 60%  | STOP. Escalate to user. The contingency in the spec ("Filling the coverage gap" section) applies: we may need to switch to baseline-then-ratchet. Do not invent your own fallback. |

- [ ] **Step 3: Re-run the JaCoCo extraction**

Use the same command from Task 3 Step 2 to find the next-largest miss:

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && \
  pwsh -NoProfile -Command "
    [xml]\$x = Get-Content ./coverage.xml
    \$x.report.package.class.method | ForEach-Object {
      \$line = \$_.counter | Where-Object { \$_.type -eq 'LINE' }
      [PSCustomObject]@{
        Name    = \$_.name
        Missed  = [int]\$line.missed
        Covered = [int]\$line.covered
      }
    } | Sort-Object Missed -Descending | Format-Table -AutoSize
  "
```

- [ ] **Step 4: Add a test for the largest miss**

For each uncovered region, follow the same pattern as Task 4/5: locate the branch in `setup_windows.ps1`, write a Pester `It` with mocks that force that branch to execute, run `make test`, confirm coverage rises. Mandatory categories per tdd.md — for each new function under test, ensure at least one of: boundary, error path, state transition. Do not write tests that just call the function and assert nothing — coverage % is a floor, not a ceiling.

- [ ] **Step 5: Commit each round**

After each round of new tests that lands the percentage at a new high:

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git add powershell/tests/setup_windows.Tests.ps1
git commit -m "$(cat <<'EOF'
test(powershell): cover <function>.<branch> [coverage now <N>%]

<one-sentence why>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Loop**

Repeat Step 1 until Step 2 routes you to Task 7.

---

## Phase 3 — Enable the gate

### Task 7: Flip run-tests.ps1 to fail below 90%

**Files:**

- Modify: `powershell/run-tests.ps1`

- [ ] **Step 1: Add the gate**

Open `powershell/run-tests.ps1`. After the `Write-Host "Coverage: ..."` line at the bottom, add:

```powershell
if ($result.CodeCoverage.CoveragePercent -lt 90) {
    Write-Error "Coverage $($result.CodeCoverage.CoveragePercent)% is below 90% floor"
    exit 1
}
```

Final file shape (Pester block onward) should be:

```powershell
Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = 'tests/'
$config.Run.Exit = $true
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './setup_windows.ps1'
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = './coverage.xml'
$result = Invoke-Pester -Configuration $config

if ($null -eq $result.CodeCoverage) {
    Write-Error "Pester returned no CodeCoverage result - verify Pester >= 5.0"
    exit 1
}
Write-Host ""
Write-Host "Coverage: $($result.CodeCoverage.CoveragePercent)%"

if ($result.CodeCoverage.CoveragePercent -lt 90) {
    Write-Error "Coverage $($result.CodeCoverage.CoveragePercent)% is below 90% floor"
    exit 1
}
```

- [ ] **Step 2: Run the gated suite**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test ; echo "exit=$?"
```

Expected: tests pass, coverage prints ≥ 90%, `exit=0`.

- [ ] **Step 3: Verify the gate actually fails on a drop (negative test)**

Temporarily lower the threshold in your local copy to `-lt 200` (impossible to satisfy):

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && \
  sed -i.bak 's/-lt 90$/-lt 200/' run-tests.ps1 && \
  make test ; echo "exit=$?" ; \
  mv run-tests.ps1.bak run-tests.ps1
```

Expected: `exit=1` and the error message includes `is below 200% floor`. Then `mv` restores the original file. Verify with:

```bash
grep -n "lt 90" powershell/run-tests.ps1
```

Expected: shows the original threshold restored.

- [ ] **Step 4: Commit**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git add powershell/run-tests.ps1
git commit -m "$(cat <<'EOF'
ci(powershell): enforce 90% coverage floor in run-tests.ps1

Fails make test (and therefore the pre-push hook and CI) when measured
coverage of setup_windows.ps1 drops below 90%. Now that the suite is
above the floor, the gate is safe to enable.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — CI integration

### Task 8: Add powershell job to ci.yml

**Files:**

- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Insert the new job**

In `.github/workflows/ci.yml`, insert the following job between `lint-macos` (ends line 44) and `secret-scan` (starts line 46), keeping the `jobs:` indentation consistent (2 spaces under `jobs:`):

```yaml
powershell:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v5

    - name: Install PowerShell
      run: |
        sudo apt-get update
        sudo apt-get install -y wget apt-transport-https software-properties-common
        source /etc/os-release
        wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
        sudo dpkg -i packages-microsoft-prod.deb
        sudo apt-get update
        sudo apt-get install -y powershell

    - name: Install Pester + PSScriptAnalyzer
      run: |
        pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
        pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"

    - name: Run tests with coverage gate
      working-directory: powershell
      run: make test
```

- [ ] **Step 2: Add to auto-merge dependencies**

In the same file, change:

```yaml
auto-merge:
  needs: [test, lint-macos, secret-scan]
```

to:

```yaml
auto-merge:
  needs: [test, lint-macos, powershell, secret-scan]
```

- [ ] **Step 3: Validate yaml syntax**

Run:

```bash
cd /Users/bruce/git-repos/personal/dotfiles && \
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && \
  echo "yaml ok"
```

Expected: `yaml ok` printed.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci: add powershell job and gate auto-merge on it

Installs pwsh + Pester + PSScriptAnalyzer on ubuntu-latest and runs
\`cd powershell && make test\`, which enforces the 90% coverage floor.
Added to auto-merge needs so a regression cannot land on master.

Closes the gap where PowerShell changes shipped with only local
pre-push hook verification.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — Documentation

### Task 9: Update CLAUDE.md with the recorded coverage figure

**Files:**

- Modify: `CLAUDE.md` (the PowerShell Testing section, around line 259)

- [ ] **Step 1: Re-measure to get the canonical figure**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && make test 2>&1 | grep '^Coverage:'
```

Expected: a single line `Coverage: <N>%`. Use this exact `<N>` in the next step (round to one decimal place if needed).

- [ ] **Step 2: Insert the Coverage subsection**

In `CLAUDE.md`, after the "Prerequisites (one-time):" code block (ends around line 275, just before the `### Test Seams` heading), insert:

```markdown
### Coverage

- **`setup_windows.ps1`: <N>%** (line coverage, measured by Pester `-CodeCoverage`)
- Floor: 90%. CI fails on any drop below the floor.
- Scope: `setup_windows.ps1` only. `run-tests.ps1` and `run-lint.ps1` are excluded as test/lint glue (per tdd.md "entry-point glue that purely calls already-tested functions").
- Re-measure: `cd powershell && make test` prints the percentage and writes `coverage.xml`.
- Update this figure whenever tests are added or removed.
```

Replace `<N>` with the actual percentage from Step 1.

- [ ] **Step 3: Verify**

```bash
grep -n "setup_windows.ps1: " /Users/bruce/git-repos/personal/dotfiles/CLAUDE.md
```

Expected: shows the new line with the actual percentage (no `<N>` placeholder remaining).

- [ ] **Step 4: Commit**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude): record powershell coverage figure and gate scope

Adds Coverage subsection to PowerShell Testing recording the current
setup_windows.ps1 percentage, the 90% floor, the scope (excludes
run-tests.ps1 and run-lint.ps1 as glue), and the re-measure command.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 — Final verification and PR

### Task 10: End-to-end verification

**Files:** none

- [ ] **Step 1: Clean run from scratch**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/powershell && \
  rm -f coverage.xml && \
  make test ; echo "exit=$?"
```

Expected: PSScriptAnalyzer clean, all Pester tests pass, coverage ≥ 90%, `exit=0`. `coverage.xml` is regenerated.

- [ ] **Step 2: Confirm bash test suite still green**

```bash
cd /Users/bruce/git-repos/personal/dotfiles && make test ; echo "exit=$?"
```

Expected: `exit=0`. The PowerShell changes must not break the bash side.

- [ ] **Step 3: Confirm pre-push hook will gate correctly**

```bash
cd /Users/bruce/git-repos/personal/dotfiles && cat .git/hooks/pre-push 2>/dev/null | head -5
```

Expected: an executable hook script that runs `make test`. If absent, run `make install-hooks` from the repo root and re-check.

- [ ] **Step 4: Review the diff**

```bash
cd /Users/bruce/git-repos/personal/dotfiles && git log master..HEAD --oneline
```

Expected: a sequence of commits matching the tasks above. Spot-check that no commit message has placeholder text.

### Task 11: Open the PR

**Files:** none

- [ ] **Step 1: Push the branch**

```bash
cd /Users/bruce/git-repos/personal/dotfiles && git push -u origin spec/powershell-coverage-gate
```

Expected: pre-push hook runs `make test` (lint + bats + powershell coverage), all green, push succeeds.

- [ ] **Step 2: Create the PR**

```bash
gh pr create --title "feat: PowerShell coverage gate (>=90% line coverage)" --body "$(cat <<'EOF'
## Summary

- Pester `-CodeCoverage` measures `setup_windows.ps1` line coverage on every `make test`.
- `run-tests.ps1` fails with `exit 1` if coverage drops below 90%.
- New `powershell` CI job runs the gated suite on every PR; auto-merge depends on it passing.
- Added tests bringing `setup_windows.ps1` to >=90% coverage (figure recorded in `CLAUDE.md`).

Closes the gap where PowerShell changes shipped without CI verification, and brings this surface into compliance with the project's >=90% coverage standard.

## Spec
`docs/superpowers/specs/2026-04-26-powershell-coverage-gate-design.md`

## Test plan

- [ ] CI `powershell` job passes on this PR
- [ ] CI `auto-merge` waits for `powershell` (visible in needs list)
- [ ] `make test` fails locally if a test is removed (drop coverage below 90%)
- [ ] PSScriptAnalyzer remains clean
- [ ] Existing bash test suite still green

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: prints the PR URL.

- [ ] **Step 3: Watch CI**

```bash
gh pr checks --watch
```

Expected: all four jobs (`test`, `lint-macos`, `powershell`, `secret-scan`) green; `auto-merge` then runs and merges to master.

- [ ] **Step 4: After merge, switch to master and pull**

```bash
cd /Users/bruce/git-repos/personal/dotfiles && \
  git checkout master && git pull && \
  git branch -d spec/powershell-coverage-gate
```

Expected: branch deleted locally; master now contains the coverage gate.

---

## Self-Review Checklist (for the implementer to run before opening PR)

- [ ] `make test` from `powershell/` exits 0 with coverage ≥ 90%.
- [ ] Removing a passing test causes the suite to fail with the coverage floor message (not a test failure).
- [ ] `.github/workflows/ci.yml` is valid yaml; `auto-merge.needs` includes `powershell`.
- [ ] `CLAUDE.md` shows a real percentage, no `<N>` placeholder.
- [ ] `coverage.xml` is git-ignored (does not appear in `git status` after a fresh `make test`).
- [ ] Bash test suite (`make test` from repo root) still exits 0.
- [ ] No commit message contains "TODO", "TBD", or placeholder text.
- [ ] All new tests assert behaviour, not just exercise the code (no shallow assertions for coverage padding).

---

## Out of scope reminders

Do NOT, in this plan:

- Add `kcov`/`bashcov` for the bash side (separate plan).
- Touch `tests/setup_env/`, `lib/*.sh`, or `setup_env.sh`.
- Add Codecov/Coveralls integration.
- Cache PowerShell modules in CI.
- Refactor `setup_windows.ps1` beyond what is necessary to make a test feasible — and even then, only with explicit user approval.
