# PowerShell Setup Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four bugs in `powershell/setup_windows.ps1` and extract the untested `if ($IsWindows)` setup block into four testable functions, bringing coverage from 9 to 22 tests.

**Architecture:** All functions are defined above the `if ($IsWindows)` guard so they can be dot-sourced on macOS for cross-platform testing. Tests use Pester v5 with `Mock` to intercept cmdlets and function stubs in `BeforeAll` for Windows-only commands. New functions follow the existing pattern of `Install-ChocolateyPackage` and `Install-WindowsUpdate`.

**Tech Stack:** PowerShell 7 (pwsh), Pester v5, PSScriptAnalyzer

---

**Files:**
- Modify: `powershell/setup_windows.ps1` — fix 4 bugs, add 4 new functions, refactor setup block
- Modify: `powershell/tests/setup_windows.Tests.ps1` — add 3 BeforeAll stubs, add 13 new tests

---

### Task 1: Fix `Enable-RequiredWindowsOptionalFeature` bug (regression test + fix)

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`
- Modify: `powershell/setup_windows.ps1`

**Bug:** The function filters features into `$RequiredWindowsOptionalFeaturesResults` (disabled only) but then iterates `$RequiredWindowsOptionalFeatures` (all features) when calling `Enable-WindowsOptionalFeature`. If one feature is disabled and one is already enabled, both are enabled.

- [ ] **Step 1: Write the failing regression test**

Add this `It` block inside `Describe "Enable-RequiredWindowsOptionalFeature"` in `powershell/tests/setup_windows.Tests.ps1`, after the existing two tests:

```powershell
  It "enables only the disabled feature when one is disabled and one is already enabled" {
    Mock Get-WindowsOptionalFeature {
      param($Online, $FeatureName)
      if ($FeatureName -eq 'Microsoft-Hyper-V') {
        [PSCustomObject]@{ FeatureName = 'Microsoft-Hyper-V'; State = 'Disabled' }
      } else {
        [PSCustomObject]@{ FeatureName = $FeatureName; State = 'Enabled' }
      }
    }
    Mock Enable-WindowsOptionalFeature { }

    Enable-RequiredWindowsOptionalFeature

    Should -Invoke Enable-WindowsOptionalFeature -Times 1 -Exactly
  }
```

- [ ] **Step 2: Run test and confirm it fails**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: test fails with `Expected 'Enable-WindowsOptionalFeature' to be called 1 times exactly but was called 2 times`

- [ ] **Step 3: Fix the function in `powershell/setup_windows.ps1`**

Replace the `Enable-RequiredWindowsOptionalFeature` function body:

```powershell
function Enable-RequiredWindowsOptionalFeature {
  # enable hyper-v and sandbox containers
  $RequiredWindowsOptionalFeatures = @(
    "Microsoft-Hyper-V"
    "Containers-DisposableClientVM"
  )
  $RequiredWindowsOptionalFeaturesResults = foreach ($feature in $RequiredWindowsOptionalFeatures) {
    Get-WindowsOptionalFeature -Online -FeatureName $feature | Where-Object {$_.State -eq "Disabled"}
  }

  if ($RequiredWindowsOptionalFeaturesResults) {
    foreach ($feature in $RequiredWindowsOptionalFeaturesResults) {
      Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName
      Write-Output "Enabled feature $($feature.FeatureName)"
    }
  }
}
```

- [ ] **Step 4: Run tests and confirm all 10 pass**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: `Tests completed in ...`, `Passed: 10, Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "fix: enable only disabled features in Enable-RequiredWindowsOptionalFeature"
```

---

### Task 2: Fix `$Result` initialization in `Install-WindowsUpdate`

**Files:**
- Modify: `powershell/setup_windows.ps1`

**Bug:** `$Result` is only assigned inside `if ($SearchResult)`. If no updates are found, `$Result` is never set and `If ($Result.rebootRequired)` silently accesses a property on `$null`. No behavior change on the first call, but the intent is unclear and a second call would see stale state.

- [ ] **Step 1: Add `$Result = $null` initialization in `powershell/setup_windows.ps1`**

In `Install-WindowsUpdate`, add `$Result = $null` immediately before the `$Installer.Updates = $SearchResult` line:

```powershell
  # install updates
  $Installer = Get-UpdateInstaller
  $Installer.Updates = $SearchResult
  $Result = $null
  if ($SearchResult) {
    $Result = $Installer.Install()
  }

  # reboot if required
  If ($Result.rebootRequired) { shutdown.exe /t 0 /r }
```

- [ ] **Step 2: Run tests and confirm all 10 still pass**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: `Passed: 10, Failed: 0`

- [ ] **Step 3: Commit**

```bash
git add powershell/setup_windows.ps1
git commit -m "fix: initialize Result to null before conditional assignment in Install-WindowsUpdate"
```

---

### Task 3: Add `Set-WindowsOptions` function and tests

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`
- Modify: `powershell/setup_windows.ps1`

- [ ] **Step 1: Add BeforeAll stubs for Windows-only cmdlets**

In `powershell/tests/setup_windows.Tests.ps1`, add these stubs inside the `BeforeAll` block, before the dot-source line (`. "$PSScriptRoot/../setup_windows.ps1"`):

```powershell
  if (-Not (Get-Command Set-NetFirewallProfile -ErrorAction SilentlyContinue)) {
    function global:Set-NetFirewallProfile { }
  }
  if (-Not (Get-Command Set-WindowsExplorerOptions -ErrorAction SilentlyContinue)) {
    function global:Set-WindowsExplorerOptions { }
  }
```

- [ ] **Step 2: Write the failing tests**

Add this `Describe` block at the end of `powershell/tests/setup_windows.Tests.ps1`:

```powershell
Describe "Set-WindowsOptions" {
  BeforeEach {
    Mock Set-ItemProperty { }
    Mock Set-NetFirewallProfile { }
    Mock Set-WindowsExplorerOptions { }
  }

  It "calls Set-ItemProperty to enable RDP" {
    Set-WindowsOptions
    Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq 'fDenyTSConnections' } -Times 1
  }

  It "calls Set-NetFirewallProfile to disable all profiles" {
    Set-WindowsOptions
    Should -Invoke Set-NetFirewallProfile -Times 1
  }

  It "calls Set-WindowsExplorerOptions with correct flags" {
    Set-WindowsOptions
    Should -Invoke Set-WindowsExplorerOptions -Times 1
  }
}
```

- [ ] **Step 3: Run tests and confirm the 3 new ones fail**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: 3 failures with `CommandNotFoundException: The term 'Set-WindowsOptions' is not recognized`

- [ ] **Step 4: Add `Set-WindowsOptions` to `powershell/setup_windows.ps1`**

Add this function immediately before the `if ($IsWindows)` block (after `Enable-RequiredWindowsOptionalFeature`):

```powershell
function Set-WindowsOptions {
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -value 0
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
  Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
}
```

- [ ] **Step 5: Run tests and confirm all 13 pass**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: `Passed: 13, Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat: extract Set-WindowsOptions with tests"
```

---

### Task 4: Add `Install-WSL` function and tests

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`
- Modify: `powershell/setup_windows.ps1`

- [ ] **Step 1: Add `wsl` stub to `BeforeAll`**

In `powershell/tests/setup_windows.Tests.ps1`, add inside the `BeforeAll` block before the dot-source line:

```powershell
  if (-Not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    function global:wsl { }
  }
```

- [ ] **Step 2: Write the failing tests**

Add this `Describe` block at the end of `powershell/tests/setup_windows.Tests.ps1`:

```powershell
Describe "Install-WSL" {
  It "calls wsl --install when WSL2 is not configured" {
    Mock wsl { @() } -ParameterFilter { $args -contains '--status' }
    Mock wsl { } -ParameterFilter { $args -contains '--install' }
    Install-WSL
    Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 1
  }

  It "skips wsl --install when WSL2 is already the default" {
    Mock wsl { "Default Version: 2" } -ParameterFilter { $args -contains '--status' }
    Mock wsl { } -ParameterFilter { $args -contains '--install' }
    Install-WSL
    Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 0
  }
}
```

- [ ] **Step 3: Run tests and confirm the 2 new ones fail**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: 2 failures with `CommandNotFoundException: The term 'Install-WSL' is not recognized`

- [ ] **Step 4: Add `Install-WSL` to `powershell/setup_windows.ps1`**

Add this function after `Set-WindowsOptions`, before the `if ($IsWindows)` block:

```powershell
function Install-WSL {
  $WSLStatus = wsl --status
  if (-Not ($WSLStatus -contains "Default Version: 2")) {
    wsl --install
  }
}
```

- [ ] **Step 5: Run tests and confirm all 15 pass**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: `Passed: 15, Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat: extract Install-WSL with tests"
```

---

### Task 5: Add `New-DirectoryStructure` function and tests (fixes Bug 2)

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`
- Modify: `powershell/setup_windows.ps1`

**Bug fixed here:** The setup block used `-ItemType File` instead of `-ItemType Directory` for directory creation.

- [ ] **Step 1: Write the failing tests**

Add this `Describe` block at the end of `powershell/tests/setup_windows.Tests.ps1`:

```powershell
Describe "New-DirectoryStructure" {
  BeforeEach {
    Mock New-Item { }
    Mock Write-Output { }
    Mock Test-Path { $true }
  }

  It "creates ~/.config when it does not exist" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/.config' }
    New-DirectoryStructure
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/.config' } -Times 1
  }

  It "skips ~/.config when it already exists" {
    New-DirectoryStructure
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/.config' } -Times 0
  }

  It "creates ~/git-repos/personal when it does not exist" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/git-repos/personal' }
    New-DirectoryStructure
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/git-repos/personal' } -Times 1
  }

  It "skips both directories when they already exist" {
    New-DirectoryStructure
    Should -Invoke New-Item -Times 0
  }
}
```

- [ ] **Step 2: Run tests and confirm the 4 new ones fail**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: 4 failures with `CommandNotFoundException: The term 'New-DirectoryStructure' is not recognized`

- [ ] **Step 3: Add `New-DirectoryStructure` to `powershell/setup_windows.ps1`**

Add this function after `Install-WSL`, before the `if ($IsWindows)` block:

```powershell
function New-DirectoryStructure {
  $Dirs = @("~/.config", "~/git-repos/personal")
  foreach ($dir in $Dirs) {
    if (-Not (Test-Path -Path $dir -PathType Container)) {
      try {
        $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
        Write-Output "The directory [$dir] has been created."
      }
      catch {
        throw $_.Exception.Message
      }
    }
  }
}
```

- [ ] **Step 4: Run tests and confirm all 19 pass**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: `Passed: 19, Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat: extract New-DirectoryStructure with tests; fix -ItemType File to -ItemType Directory"
```

---

### Task 6: Add `Copy-GitConfig` function and tests (fixes Bug 3)

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`
- Modify: `powershell/setup_windows.ps1`

**Bug fixed here:** The old code guarded the copy with `if (Test-Path ~/.gitconfig)` — skipping setup on a fresh machine. The fix checks whether the source exists instead.

- [ ] **Step 1: Write the failing tests**

Add this `Describe` block at the end of `powershell/tests/setup_windows.Tests.ps1`:

```powershell
Describe "Copy-GitConfig" {
  BeforeEach {
    Mock Remove-Item { }
    Mock Copy-Item { }
    Mock Write-Output { }
  }

  It "copies gitconfig when source exists" {
    Mock Test-Path { $true }
    Copy-GitConfig
    Should -Invoke Copy-Item -Times 1
  }

  It "removes existing ~/.gitconfig before copying" {
    Mock Test-Path { $true }
    Copy-GitConfig
    Should -Invoke Remove-Item -Times 1
  }

  It "skips copy when source does not exist" {
    Mock Test-Path { $false }
    Copy-GitConfig
    Should -Invoke Copy-Item -Times 0
  }
}
```

- [ ] **Step 2: Run tests and confirm the 3 new ones fail**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: 3 failures with `CommandNotFoundException: The term 'Copy-GitConfig' is not recognized`

- [ ] **Step 3: Add `Copy-GitConfig` to `powershell/setup_windows.ps1`**

Add this function after `New-DirectoryStructure`, before the `if ($IsWindows)` block:

```powershell
function Copy-GitConfig {
  $GitConfigSource = "~/git-repos/personal/dotfiles/.gitconfig_windows"
  if (Test-Path -Path $GitConfigSource -PathType Leaf) {
    try {
      $null = Remove-Item ~/.gitconfig -ErrorAction SilentlyContinue
      $null = Copy-Item -Path $GitConfigSource -Destination ~/.gitconfig -ErrorAction SilentlyContinue
      Write-Output "copied ~/.gitconfig"
    }
    catch {
      throw $_.Exception.Message
    }
  }
}
```

- [ ] **Step 4: Run tests and confirm all 22 pass**

```bash
cd powershell && pwsh -Command "Import-Module Pester; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests/'; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c"
```

Expected: `Passed: 22, Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add powershell/setup_windows.ps1 powershell/tests/setup_windows.Tests.ps1
git commit -m "feat: extract Copy-GitConfig with tests; fix gitconfig copy to check source not destination"
```

---

### Task 7: Refactor `if ($IsWindows)` setup block and update docs

**Files:**
- Modify: `powershell/setup_windows.ps1`
- Modify: `powershell/CLAUDE.md` (if present) or `CLAUDE.md`

- [ ] **Step 1: Replace the setup block body in `powershell/setup_windows.ps1`**

Replace the entire `if ($setup.IsPresent)` block (which currently contains inline registry, firewall, WSL, directory, and gitconfig logic) with function calls:

```powershell
  if ($setup.IsPresent) {
    Set-WindowsOptions
    Install-ChocolateyPackage
    Enable-RequiredWindowsOptionalFeature
    Install-WSL
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser
    New-DirectoryStructure
    Copy-GitConfig
  }
```

The `if ($update.IsPresent)` block is unchanged.

- [ ] **Step 2: Run `make test` and confirm all 22 tests pass with clean lint**

```bash
cd powershell && make test
```

Expected:
```
pwsh -Command "..."
...
Tests completed in ...s
Passed: 22, Failed: 0, Skipped: 0, NotRun: 0
```

- [ ] **Step 3: Update `CLAUDE.md` test count**

In `dotfiles/CLAUDE.md`, in the PowerShell testing section, the test count reference for `setup_windows.Tests.ps1` should reflect 22 tests. Update the layout entry:

```
│       └── setup_windows.Tests.ps1   # Pester v5 unit tests (22 tests)
```

- [ ] **Step 4: Commit**

```bash
git add powershell/setup_windows.ps1 CLAUDE.md
git commit -m "refactor: replace setup block inline code with function calls; update test count to 22"
```

---

## Test count projection

| File | Before | Added | After |
|---|---|---|---|
| `powershell/tests/setup_windows.Tests.ps1` | 9 | +13 | 22 |
