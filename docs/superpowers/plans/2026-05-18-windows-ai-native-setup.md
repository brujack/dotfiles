# Windows AI-Native Dev Environment Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ai-config Claude/Cursor symlink setup and npm globals to `setup_windows.ps1` so native Windows has a fully configured AI dev environment matching macOS/Linux.

**Architecture:** Five new PowerShell functions (`New-SafeLink`, `Install-AiConfig`, `Set-ClaudeConfig`, `Set-CursorConfig`, `Set-NpmGlobalPackages`) follow the existing idempotent-install pattern. `New-SafeLink` is the shared primitive; config functions call it. All five are wired into `Invoke-DotfilesSetup`; `Install-AiConfig` and `Set-NpmGlobalPackages` also wire into `Invoke-DotfilesUpdate`. TDD throughout: Pester tests first, minimal implementation second.

**Tech Stack:** PowerShell 7+, Pester v5, existing `make test` / `make lint` in `powershell/`

---

### Task 1: Create feature branch (worktree)

- [ ] **Create worktree and branch**

```bash
git worktree add ~/git-repos/personal/dotfiles-windows-ai-native feature/windows-ai-native-setup
cd ~/git-repos/personal/dotfiles-windows-ai-native
```

- [ ] **Verify working tree is clean and on correct branch**

```bash
git status
git branch --show-current
```

Expected: branch `feature/windows-ai-native-setup`, clean working tree.

---

### Task 2: Add `nodejs` to Chocolatey list and update test

**Files:**

- Modify: `powershell/setup_windows.ps1` — add `nodejs` to package list (alphabetical, between `neovim` and `postman`)
- Modify: `powershell/tests/setup_windows.Tests.ps1:69-145` — add `nodejs 1.0` to mock list

- [ ] **Add `nodejs` to `$ChocoPackagesToBeInstalled` in `setup_windows.ps1`**

In `powershell/setup_windows.ps1`, the package list (line ~25-91), insert after `"neovim"`:

```powershell
    "nodejs",
```

- [ ] **Update the "skips choco install" test to include `nodejs 1.0` in the mock list**

In `powershell/tests/setup_windows.Tests.ps1`, in the `It "skips choco install for packages already in the installed list"` block, add to the mock return array (after `"neovim 1.0"`):

```powershell
        "nodejs 1.0",
```

- [ ] **Run tests to confirm existing tests still pass**

```bash
cd powershell && make test
```

Expected: all tests pass (same count as before this task).

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): add nodejs to chocolatey package list"
```

---

### Task 3: Add `npm` stub to `BeforeAll`

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1:1-28` — add `npm` stub alongside existing stubs

- [ ] **Add `npm` stub to the `BeforeAll` block (before the dot-source line)**

In `powershell/tests/setup_windows.Tests.ps1`, in the `BeforeAll` block, after the `wsl` stub and before `. "$PSScriptRoot/../setup_windows.ps1"`:

```powershell
  if (-Not (Get-Command npm -ErrorAction SilentlyContinue)) {
    function global:npm { }
  }
```

- [ ] **Run tests to confirm still passing**

```bash
cd powershell && make test
```

- [ ] **Commit**

```bash
git add powershell/tests/setup_windows.Tests.ps1
git commit -m "test(windows): add npm stub to BeforeAll for cross-platform tests"
```

---

### Task 4: `New-SafeLink` helper (TDD)

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1` — add `Describe "New-SafeLink"` block
- Modify: `powershell/setup_windows.ps1` — add `New-SafeLink` function

- [ ] **Write the failing tests — add this `Describe` block at the end of `setup_windows.Tests.ps1`**

```powershell
Describe "New-SafeLink" {
  BeforeEach {
    Mock Get-Item     { $null }
    Mock Remove-Item  { }
    Mock New-Item     { }
    Mock Write-Output { }
  }

  It "creates a symlink when link does not exist" {
    New-SafeLink -Target "C:/target/file.json" -Link "C:/link/file.json"
    Should -Invoke New-Item -ParameterFilter { $ItemType -eq 'SymbolicLink' } -Times 1
  }

  It "creates a junction when -Junction flag is set" {
    New-SafeLink -Target "C:/target/dir" -Link "C:/link/dir" -Junction
    Should -Invoke New-Item -ParameterFilter { $ItemType -eq 'Junction' } -Times 1
  }

  It "skips when link already points to correct target" {
    Mock Get-Item { [PSCustomObject]@{ Target = "C:/target/file.json" } }
    New-SafeLink -Target "C:/target/file.json" -Link "C:/link/file.json"
    Should -Invoke New-Item   -Times 0
    Should -Invoke Remove-Item -Times 0
  }

  It "replaces symlink when target has changed" {
    Mock Get-Item { [PSCustomObject]@{ Target = "C:/old/file.json" } }
    New-SafeLink -Target "C:/new/file.json" -Link "C:/link/file.json"
    Should -Invoke Remove-Item -Times 1
    Should -Invoke New-Item    -ParameterFilter { $ItemType -eq 'SymbolicLink' } -Times 1
  }

  It "removes regular file before creating symlink" {
    Mock Get-Item { [PSCustomObject]@{ Target = $null } }
    New-SafeLink -Target "C:/target/file.json" -Link "C:/link/file.json"
    Should -Invoke Remove-Item -Times 1
    Should -Invoke New-Item    -Times 1
  }
}
```

- [ ] **Run tests to confirm they fail**

```bash
cd powershell && make test 2>&1 | grep -E "FAILED|New-SafeLink"
```

Expected: 5 failures — `New-SafeLink` is not defined.

- [ ] **Implement `New-SafeLink` in `setup_windows.ps1` — add before `Install-ChocolateyPackage`**

```powershell
function New-SafeLink {
  param(
    [string]$Target,
    [string]$Link,
    [switch]$Junction
  )
  $existing = Get-Item $Link -ErrorAction SilentlyContinue
  if ($null -ne $existing) {
    if ($existing.Target -eq $Target) {
      Write-Output "Already linked: $Link"
      return
    }
    Remove-Item $Link -Force -Recurse
  }
  if ($Junction) {
    $null = New-Item -ItemType Junction -Path $Link -Target $Target
  } else {
    $null = New-Item -ItemType SymbolicLink -Path $Link -Target $Target
  }
  Write-Output "Linked: $Link -> $Target"
}
```

- [ ] **Run tests to confirm 5 new tests pass**

```bash
cd powershell && make test
```

Expected: all tests pass.

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): add New-SafeLink helper for idempotent symlinks and junctions"
```

---

### Task 5: `Install-AiConfig` (TDD)

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1` — add `Describe "Install-AiConfig"` block
- Modify: `powershell/setup_windows.ps1` — add `Install-AiConfig` function

- [ ] **Write the failing tests — append this `Describe` block to `setup_windows.Tests.ps1`**

```powershell
Describe "Install-AiConfig" {
  BeforeEach {
    $global:LASTEXITCODE = 0
    Mock git         { }
    Mock Write-Output { }
    Mock Test-Path   { $false }
  }

  It "calls git clone when ai-config directory is absent" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/ai-config' }
    Install-AiConfig
    Should -Invoke git -ParameterFilter { $args -contains 'clone' } -Times 1
  }

  It "calls git pull when ai-config directory is present" {
    Mock Test-Path { $true } -ParameterFilter { $Path -like '*/ai-config' }
    Install-AiConfig
    Should -Invoke git -ParameterFilter { $args -contains 'pull' } -Times 1
  }

  It "throws when git clone fails" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/ai-config' }
    Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains 'clone' }
    { Install-AiConfig } | Should -Throw
  }

  It "throws when git pull fails" {
    Mock Test-Path { $true } -ParameterFilter { $Path -like '*/ai-config' }
    Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains 'pull' }
    { Install-AiConfig } | Should -Throw
  }
}
```

- [ ] **Run tests to confirm they fail**

```bash
cd powershell && make test 2>&1 | grep -E "FAILED|Install-AiConfig"
```

Expected: 4 failures.

- [ ] **Implement `Install-AiConfig` in `setup_windows.ps1` — add after `New-SafeLink`**

```powershell
function Install-AiConfig {
  $aiConfigDir = "~/git-repos/personal/ai-config"
  if (-Not (Test-Path -Path $aiConfigDir -PathType Container)) {
    Write-Output "Cloning ai-config..."
    git clone git@github.com:brujack/ai-config $aiConfigDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
  } else {
    Write-Output "Updating ai-config..."
    git -C $aiConfigDir pull --rebase --autostash
    if ($LASTEXITCODE -ne 0) { throw "git pull failed with exit code $LASTEXITCODE" }
  }
}
```

- [ ] **Run tests to confirm 4 new tests pass**

```bash
cd powershell && make test
```

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): add Install-AiConfig to clone/pull ai-config repo"
```

---

### Task 6: `Set-ClaudeConfig` (TDD)

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1` — add `Describe "Set-ClaudeConfig"` block
- Modify: `powershell/setup_windows.ps1` — add `Set-ClaudeConfig` function

- [ ] **Write the failing tests — append this `Describe` block to `setup_windows.Tests.ps1`**

```powershell
Describe "Set-ClaudeConfig" {
  BeforeEach {
    $script:savedPAT  = $env:GITHUB_PAT
    $env:GITHUB_PAT   = $null
    Mock New-SafeLink  { }
    Mock New-Item      { }
    Mock Test-Path     { $true }
    Mock Get-Content   { '{"token":"${GITHUB_PAT}"}' }
    Mock Set-Content   { }
    Mock Write-Output  { }
    Mock Write-Warning { }
  }
  AfterEach {
    $env:GITHUB_PAT = $script:savedPAT
  }

  It "creates ~/.claude when it does not exist" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/.claude' }
    Set-ClaudeConfig
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/.claude' } -Times 1
  }

  It "links settings.json as a symlink" {
    Set-ClaudeConfig
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/settings.json' -and $Junction -eq $false
    } -Times 1
  }

  It "links skills directory as a junction" {
    Set-ClaudeConfig
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/skills' -and $Junction -eq $true
    } -Times 1
  }

  It "links commands and standards directories as junctions" {
    Set-ClaudeConfig
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/commands' -and $Junction -eq $true
    } -Times 1
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/standards' -and $Junction -eq $true
    } -Times 1
  }

  It "writes mcp.json with GITHUB_PAT substituted" {
    $env:GITHUB_PAT = "ghp_test123"
    Set-ClaudeConfig
    Should -Invoke Set-Content -ParameterFilter {
      $Value -like '*ghp_test123*' -and $Path -like '*/mcp.json'
    } -Times 1
  }

  It "warns and writes template unchanged when GITHUB_PAT is unset" {
    $env:GITHUB_PAT = $null
    Set-ClaudeConfig
    Should -Invoke Write-Warning -Times 1
    Should -Invoke Set-Content   -ParameterFilter { $Path -like '*/mcp.json' } -Times 1
  }
}
```

- [ ] **Run tests to confirm they fail**

```bash
cd powershell && make test 2>&1 | grep -E "FAILED|Set-ClaudeConfig"
```

Expected: 6 failures.

- [ ] **Implement `Set-ClaudeConfig` in `setup_windows.ps1` — add after `Install-AiConfig`**

```powershell
function Set-ClaudeConfig {
  $aiClaude  = "~/git-repos/personal/ai-config/.claude"
  $claudeDir = "~/.claude"

  if (-Not (Test-Path -Path $claudeDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $claudeDir -Force
  }

  foreach ($file in @("settings.json", "CLAUDE.md", "mcp.json.template")) {
    New-SafeLink -Target "$aiClaude/$file" -Link "$claudeDir/$file"
  }

  foreach ($dir in @("skills", "commands", "standards")) {
    New-SafeLink -Target "$aiClaude/$dir" -Link "$claudeDir/$dir" -Junction
  }

  $templatePath = "$claudeDir/mcp.json.template"
  $outputPath   = "$claudeDir/mcp.json"
  if (Test-Path $templatePath) {
    $content = Get-Content $templatePath -Raw
    $pat = $env:GITHUB_PAT
    if ([string]::IsNullOrEmpty($pat)) {
      Write-Warning "GITHUB_PAT not set — writing mcp.json without substitution"
    } else {
      $content = $content -replace '\$\{GITHUB_PAT\}', $pat
    }
    Set-Content -Path $outputPath -Value $content
  }
}
```

- [ ] **Run tests to confirm 6 new tests pass**

```bash
cd powershell && make test
```

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): add Set-ClaudeConfig to link ai-config into ~/.claude"
```

---

### Task 7: `Set-CursorConfig` (TDD)

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1` — add `Describe "Set-CursorConfig"` block
- Modify: `powershell/setup_windows.ps1` — add `Set-CursorConfig` function

- [ ] **Write the failing tests — append this `Describe` block to `setup_windows.Tests.ps1`**

```powershell
Describe "Set-CursorConfig" {
  BeforeEach {
    $env:APPDATA = "C:/Users/Test/AppData/Roaming"
    Mock New-SafeLink  { }
    Mock New-Item      { }
    Mock Test-Path     { $true }
    Mock Write-Output  { }
  }

  It "creates ~/.cursor and AppData Cursor User dirs when absent" {
    Mock Test-Path { $false }
    Set-CursorConfig
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/.cursor' }  -Times 1
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/Cursor/User' } -Times 1
  }

  It "links plugins, rules, and skills-cursor as junctions into ~/.cursor" {
    Set-CursorConfig
    foreach ($dir in @('plugins', 'rules', 'skills-cursor')) {
      Should -Invoke New-SafeLink -ParameterFilter {
        $Link -like "*/$dir" -and $Junction -eq $true
      } -Times 1
    }
  }

  It "links settings.json as a symlink into Cursor User dir" {
    Set-CursorConfig
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/Cursor/User/settings.json' -and $Junction -eq $false
    } -Times 1
  }

  It "links keybindings.json as a symlink into Cursor User dir" {
    Set-CursorConfig
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/Cursor/User/keybindings.json' -and $Junction -eq $false
    } -Times 1
  }

  It "links snippets as a junction into Cursor User dir" {
    Set-CursorConfig
    Should -Invoke New-SafeLink -ParameterFilter {
      $Link -like '*/Cursor/User/snippets' -and $Junction -eq $true
    } -Times 1
  }
}
```

- [ ] **Run tests to confirm they fail**

```bash
cd powershell && make test 2>&1 | grep -E "FAILED|Set-CursorConfig"
```

Expected: 5 failures.

- [ ] **Implement `Set-CursorConfig` in `setup_windows.ps1` — add after `Set-ClaudeConfig`**

```powershell
function Set-CursorConfig {
  $aiCursor      = "~/git-repos/personal/ai-config/.cursor"
  $cursorDir     = "~/.cursor"
  $cursorUserDir = "$env:APPDATA/Cursor/User"

  if (-Not (Test-Path -Path $cursorDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $cursorDir -Force
  }
  if (-Not (Test-Path -Path $cursorUserDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $cursorUserDir -Force
  }

  foreach ($dir in @("plugins", "rules", "skills-cursor")) {
    New-SafeLink -Target "$aiCursor/$dir" -Link "$cursorDir/$dir" -Junction
  }

  foreach ($file in @("settings.json", "keybindings.json")) {
    New-SafeLink -Target "$aiCursor/User/$file" -Link "$cursorUserDir/$file"
  }

  New-SafeLink -Target "$aiCursor/User/snippets" -Link "$cursorUserDir/snippets" -Junction
}
```

- [ ] **Run tests to confirm 5 new tests pass**

```bash
cd powershell && make test
```

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): add Set-CursorConfig to link ai-config into ~/.cursor and AppData"
```

---

### Task 8: `Set-NpmGlobalPackages` (TDD)

**Files:**

- Modify: `powershell/tests/setup_windows.Tests.ps1` — add `Describe "Set-NpmGlobalPackages"` block
- Modify: `powershell/setup_windows.ps1` — add `Set-NpmGlobalPackages` function

- [ ] **Write the failing tests — append this `Describe` block to `setup_windows.Tests.ps1`**

```powershell
Describe "Set-NpmGlobalPackages" {
  BeforeEach {
    Mock npm          { }
    Mock Write-Output { }
    Mock Write-Warning { }
  }

  It "calls npm install -g firecrawl-cli when node is available" {
    Mock Get-Command {
      [PSCustomObject]@{ Name = 'node' }
    } -ParameterFilter { $Name -eq 'node' }
    Set-NpmGlobalPackages
    Should -Invoke npm -ParameterFilter {
      $args -contains 'install' -and $args -contains '-g' -and $args -contains 'firecrawl-cli'
    } -Times 1
  }

  It "skips npm and warns when node is not in PATH" {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'node' }
    Set-NpmGlobalPackages
    Should -Invoke npm          -Times 0
    Should -Invoke Write-Warning -Times 1
  }
}
```

- [ ] **Run tests to confirm they fail**

```bash
cd powershell && make test 2>&1 | grep -E "FAILED|Set-NpmGlobalPackages"
```

Expected: 2 failures.

- [ ] **Implement `Set-NpmGlobalPackages` in `setup_windows.ps1` — add after `Set-CursorConfig`**

```powershell
function Set-NpmGlobalPackages {
  if (-Not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Warning "node not found in PATH — skipping npm global package install"
    return
  }
  Write-Output "Installing npm global packages"
  npm install -g firecrawl-cli
}
```

- [ ] **Run tests to confirm 2 new tests pass**

```bash
cd powershell && make test
```

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): add Set-NpmGlobalPackages to install firecrawl-cli"
```

---

### Task 9: Wire orchestrators and update orchestrator tests

**Files:**

- Modify: `powershell/setup_windows.ps1:197-228` — update `Invoke-DotfilesSetup` and `Invoke-DotfilesUpdate`
- Modify: `powershell/tests/setup_windows.Tests.ps1` — update `Invoke-DotfilesSetup` and `Invoke-DotfilesUpdate` `Describe` blocks

- [ ] **Update `Invoke-DotfilesSetup` in `setup_windows.ps1`**

Replace the existing `Invoke-DotfilesSetup` function body:

```powershell
function Invoke-DotfilesSetup {
  Set-WindowsOption
  Install-ChocolateyPackage
  Enable-RequiredWindowsOptionalFeature
  Install-WSL
  Set-ExecutionPolicy Unrestricted -Scope CurrentUser
  New-DirectoryStructure
  Copy-GitConfig
  Install-AiConfig
  Set-ClaudeConfig
  Set-CursorConfig
  Set-NpmGlobalPackages
}
```

- [ ] **Update `Invoke-DotfilesUpdate` in `setup_windows.ps1`**

Replace the existing `Invoke-DotfilesUpdate` function body:

```powershell
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

  Install-AiConfig
  Set-NpmGlobalPackages

  Write-Output "Installing Windows Updates"
  Install-WindowsUpdate
}
```

- [ ] **Update the `Invoke-DotfilesSetup` `Describe` block in the test file**

In `powershell/tests/setup_windows.Tests.ps1`, in the `Describe "Invoke-DotfilesSetup"` `BeforeEach`, add mocks for the four new functions:

```powershell
  BeforeEach {
    Mock Set-WindowsOption                     { }
    Mock Install-ChocolateyPackage             { }
    Mock Enable-RequiredWindowsOptionalFeature { }
    Mock Install-WSL                           { }
    Mock Set-ExecutionPolicy                   { }
    Mock New-DirectoryStructure                { }
    Mock Copy-GitConfig                        { }
    Mock Install-AiConfig                      { }
    Mock Set-ClaudeConfig                      { }
    Mock Set-CursorConfig                      { }
    Mock Set-NpmGlobalPackages                 { }
  }
```

Then add four new `It` blocks (after the existing seven):

```powershell
  It "calls Install-AiConfig" {
    Invoke-DotfilesSetup
    Should -Invoke Install-AiConfig -Times 1 -Exactly
  }
  It "calls Set-ClaudeConfig" {
    Invoke-DotfilesSetup
    Should -Invoke Set-ClaudeConfig -Times 1 -Exactly
  }
  It "calls Set-CursorConfig" {
    Invoke-DotfilesSetup
    Should -Invoke Set-CursorConfig -Times 1 -Exactly
  }
  It "calls Set-NpmGlobalPackages" {
    Invoke-DotfilesSetup
    Should -Invoke Set-NpmGlobalPackages -Times 1 -Exactly
  }
```

- [ ] **Update the `Invoke-DotfilesUpdate` `Describe` block in the test file**

In `powershell/tests/setup_windows.Tests.ps1`, in the `Describe "Invoke-DotfilesUpdate"` `BeforeEach`, add mocks for the two new functions:

```powershell
  BeforeEach {
    Mock choco                 { }
    Mock Install-WindowsUpdate { }
    Mock Install-AiConfig      { }
    Mock Set-NpmGlobalPackages { }
    Mock Test-Path             { $false }
    Mock Write-Output          { }
  }
```

Add two new `It` blocks (after the existing three):

```powershell
  It "calls Install-AiConfig to pull latest config" {
    Invoke-DotfilesUpdate
    Should -Invoke Install-AiConfig -Times 1 -Exactly
  }
  It "calls Set-NpmGlobalPackages to update npm globals" {
    Invoke-DotfilesUpdate
    Should -Invoke Set-NpmGlobalPackages -Times 1 -Exactly
  }
```

- [ ] **Run full test suite to confirm all tests pass**

```bash
cd powershell && make test
```

Expected: all tests pass including the 6 new orchestrator tests.

- [ ] **Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat(windows): wire ai-config and npm setup into setup and update orchestrators"
```

---

### Task 10: Measure coverage, update CLAUDE.md

**Files:**

- Modify: `powershell/run-tests.ps1:36` — coverage floor (only if new coverage exceeds current 90% floor)
- Modify: `CLAUDE.md` — document Windows ai-config setup and hooks gap

- [ ] **Measure new coverage**

```bash
cd powershell && make test 2>&1 | grep -i coverage
```

Note the percentage (format: `Coverage: N.NN%`). The floor check is at `powershell/run-tests.ps1:36`:

```powershell
if ($result.CodeCoverage.CoveragePercent -lt 90) {
```

New functions are well-covered by the tests in Tasks 4–9, so coverage should remain above 90%. If it unexpectedly drops below 90%, investigate before changing the floor.

- [ ] **Add Windows ai-config section to `CLAUDE.md`**

In `CLAUDE.md`, after the PowerShell Scripts section, add:

```markdown
### Windows AI Config Setup

`setup_windows.ps1 -setup` now links ai-config into native Windows alongside WSL2:

- `~/.claude/` — `settings.json`, `CLAUDE.md`, `mcp.json.template` as symlinks; `skills/`, `commands/`, `standards/` as junctions
- `~/.claude/mcp.json` — generated from template with `$env:GITHUB_PAT` substitution (set `GITHUB_PAT` in system env before running setup)
- `~/.cursor/` — `plugins/`, `rules/`, `skills-cursor/` as junctions
- `$env:APPDATA\Cursor\User\` — `settings.json`, `keybindings.json` as symlinks; `snippets/` as junction

**Hooks gap:** `.claude/hooks/` bash scripts are not linked on native Windows — they only run in WSL2 via `setup_env.sh`.

`setup_windows.ps1 -update` pulls the latest ai-config and updates npm globals (`firecrawl-cli`).
```

- [ ] **Run lint and tests one final time**

```bash
cd powershell && make test
```

Expected: all tests pass, coverage at or above floor.

- [ ] **Commit**

```bash
git add CLAUDE.md
git commit -m "docs(windows): document ai-config setup and hooks gap"
```

---

### Task 11: PR, CI, merge, cleanup

- [ ] **Run full shell tests from repo root to confirm nothing regressed**

```bash
make test
```

Expected: 627+ BATS tests pass.

- [ ] **Push branch and open PR**

```bash
git push -u origin feature/windows-ai-native-setup
gh pr create --title "feat(windows): AI-native dev environment setup" --body "$(cat <<'EOF'
## Summary

- Adds `New-SafeLink` helper for idempotent symlinks and junctions
- `Install-AiConfig` clones/pulls ai-config on setup and update
- `Set-ClaudeConfig` links settings, skills, commands, standards into `~/.claude`; generates `mcp.json` from template
- `Set-CursorConfig` links plugins, rules, skills-cursor into `~/.cursor`; links User settings into AppData
- `Set-NpmGlobalPackages` installs `firecrawl-cli` via npm
- Adds `nodejs` to Chocolatey list
- 28 new Pester tests

## Test plan

- [ ] `cd powershell && make test` passes
- [ ] `make test` (BATS) passes from repo root
- [ ] Coverage at or above 90% floor

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Monitor CI**

```bash
gh pr checks --watch
```

- [ ] **After merge: clean up worktree and branches**

```bash
git worktree remove ~/git-repos/personal/dotfiles-windows-ai-native
git fetch --prune
git pull
git branch -D feature/windows-ai-native-setup
git push origin --delete feature/windows-ai-native-setup 2>/dev/null || true
```

---

### Task 12: Post-merge docs update (do on main after PR merges — NOT in worktree)

- [ ] **Update `docs/superpowers/README.md` — add row and mark Done**

Add a row to the All Plans table:

```markdown
| 2026-05-18 | [windows-ai-native-setup](plans/2026-05-18-windows-ai-native-setup.md) | [spec](specs/2026-05-18-windows-ai-native-setup-design.md) | Done |
```

- [ ] **Add Done banner to plan file**

At the top of `docs/superpowers/plans/2026-05-18-windows-ai-native-setup.md`, add:

```markdown
> **Status: DONE**
```

- [ ] **Commit directly on main**

```bash
git add docs/superpowers/README.md docs/superpowers/plans/2026-05-18-windows-ai-native-setup.md
git commit -m "docs(superpowers): mark windows-ai-native-setup plan as Done"
git push
```
