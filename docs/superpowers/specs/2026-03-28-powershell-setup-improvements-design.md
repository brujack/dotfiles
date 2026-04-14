# PowerShell Setup Improvements Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Fix four bugs in `powershell/setup_windows.ps1` and extract the untested `if ($IsWindows)` setup block into four testable functions, bringing test coverage from 9 to 22 tests.

## Scope

- **In scope:** Bug fixes in `setup_windows.ps1`; extraction of `Set-WindowsOptions`, `Install-WSL`, `New-DirectoryStructure`, `Copy-GitConfig`; new Pester tests for all four functions plus one regression test for the existing `Enable-RequiredWindowsOptionalFeature` bug
- **Out of scope:** Changes to `Install-ChocolateyPackage`, `Install-WindowsUpdate`, or `Enable-RequiredWindowsOptionalFeature` logic (other than the bug fix); changes to the `update` block

---

## Section 1: Bug fixes

### Bug 1 — `Enable-RequiredWindowsOptionalFeature` enables wrong set of features

**File:** `powershell/setup_windows.ps1`

**Root cause:** The function filters for disabled features into `$RequiredWindowsOptionalFeaturesResults`, checks if that list is non-empty, but then iterates the original unfiltered `$RequiredWindowsOptionalFeatures` list when calling `Enable-WindowsOptionalFeature`. If one feature is already enabled and the other is not, both are enabled anyway.

**Fix:** Iterate `$RequiredWindowsOptionalFeaturesResults` (the filtered list) in the `foreach` that calls `Enable-WindowsOptionalFeature`.

```powershell
# Before
if ($RequiredWindowsOptionalFeaturesResults) {
  foreach ($features in $RequiredWindowsOptionalFeatures) {
    Enable-WindowsOptionalFeature -Online -FeatureName $features
  }
}

# After
if ($RequiredWindowsOptionalFeaturesResults) {
  foreach ($feature in $RequiredWindowsOptionalFeaturesResults) {
    Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName
    Write-Output "Enabled feature $($feature.FeatureName)"
  }
}
```

### Bug 2 — `New-Item -ItemType File` used to create directories

**File:** `powershell/setup_windows.ps1` (two locations in setup block — moved to `New-DirectoryStructure` in Section 2)

**Fix:** Change `-ItemType File` to `-ItemType Directory` in both `New-Item` calls.

### Bug 3 — `.gitconfig` copy skipped on fresh machine

**File:** `powershell/setup_windows.ps1` (setup block — moved to `Copy-GitConfig` in Section 2)

**Root cause:** `if (Test-Path -Path ~/.gitconfig -PathType Leaf)` guards the copy. On a new machine with no existing `.gitconfig`, setup silently skips the copy.

**Fix:** Check whether the source file exists rather than the destination:

```powershell
# Before
if (Test-Path -Path ~/.gitconfig -PathType Leaf) { ... }

# After
$GitConfigSource = "~/git-repos/personal/dotfiles/.gitconfig_windows"
if (Test-Path -Path $GitConfigSource -PathType Leaf) {
  $null = Remove-Item ~/.gitconfig -ErrorAction SilentlyContinue
  $null = Copy-Item -Path $GitConfigSource -Destination ~/.gitconfig -ErrorAction SilentlyContinue
  Write-Output "copied ~/.gitconfig"
}
```

### Bug 4 — `$Result` uninitialized in `Install-WindowsUpdate`

**File:** `powershell/setup_windows.ps1`

**Root cause:** `$Result` is only assigned inside `if ($SearchResult)`. If no updates are found, `$Result` is never set and `If ($Result.rebootRequired)` accesses a property on `$null`.

**Fix:** Initialize `$Result = $null` before the conditional block.

---

## Section 2: Function extraction

Four new functions are defined above the `if ($IsWindows)` guard, following the existing pattern.

### `Set-WindowsOptions`

Groups all one-time system option changes:

```powershell
function Set-WindowsOptions {
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -value 0
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
  Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
}
```

### `Install-WSL`

```powershell
function Install-WSL {
  $WSLStatus = wsl --status
  if (-Not ($WSLStatus -contains "Default Version: 2")) {
    wsl --install
  }
}
```

### `New-DirectoryStructure`

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

### `Copy-GitConfig`

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

### Updated `if ($IsWindows)` setup block

```powershell
if ($IsWindows) {
  if ($setup.IsPresent) {
    Set-WindowsOptions
    Install-ChocolateyPackage
    Enable-RequiredWindowsOptionalFeature
    Install-WSL
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser
    New-DirectoryStructure
    Copy-GitConfig
  }

  if ($update.IsPresent) {
    Write-Output "Updating chocolatey packages"
    choco upgrade all -y
    ...
    Install-WindowsUpdate
  }
}
```

`Set-ExecutionPolicy` stays inline — it is a single call with no conditional logic worth extracting.

---

## Section 3: Tests

### New stubs required in `BeforeAll`

```powershell
if (-Not (Get-Command Set-NetFirewallProfile -ErrorAction SilentlyContinue)) {
  function global:Set-NetFirewallProfile { }
}
if (-Not (Get-Command Set-WindowsExplorerOptions -ErrorAction SilentlyContinue)) {
  function global:Set-WindowsExplorerOptions { }
}
if (-Not (Get-Command wsl -ErrorAction SilentlyContinue)) {
  function global:wsl { }
}
```

### `Set-WindowsOptions` — 3 tests

| #   | Test                                                   | Assert                                                                                |
| --- | ------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| 1   | Calls `Set-ItemProperty` to enable RDP                 | `Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq 'fDenyTSConnections' }` |
| 2   | Calls `Set-NetFirewallProfile` to disable all profiles | `Should -Invoke Set-NetFirewallProfile -Times 1`                                      |
| 3   | Calls `Set-WindowsExplorerOptions` with correct flags  | `Should -Invoke Set-WindowsExplorerOptions -Times 1`                                  |

### `Install-WSL` — 2 tests

| #   | Test                                            | Setup                                                                               | Assert                                                                         |
| --- | ----------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| 1   | Calls `wsl --install` when WSL2 not configured  | `Mock wsl { @() }` (returns nothing for `--status`)                                 | `Should -Invoke wsl -ParameterFilter { $args -contains '--install' }`          |
| 2   | Skips `wsl --install` when WSL2 already default | `Mock wsl { "Default Version: 2" } -ParameterFilter { $args -contains '--status' }` | `Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 0` |

### `New-DirectoryStructure` — 4 tests

| #   | Test                                       | Setup                                                                               | Assert                                                                            |
| --- | ------------------------------------------ | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 1   | Creates `~/.config` when absent            | `Mock Test-Path { $false } -ParameterFilter { $Path -like '*/.config' }`            | `Should -Invoke New-Item -ParameterFilter { $Path -like '*/.config' }`            |
| 2   | Skips `~/.config` when present             | `Mock Test-Path { $true } -ParameterFilter { $Path -like '*/.config' }`             | `Should -Invoke New-Item -ParameterFilter { $Path -like '*/.config' } -Times 0`   |
| 3   | Creates `~/git-repos/personal` when absent | `Mock Test-Path { $false } -ParameterFilter { $Path -like '*/git-repos/personal' }` | `Should -Invoke New-Item -ParameterFilter { $Path -like '*/git-repos/personal' }` |
| 4   | Skips `~/git-repos/personal` when present  | `Mock Test-Path { $true }` for all paths                                            | `Should -Invoke New-Item -Times 0`                                                |

### `Copy-GitConfig` — 3 tests

| #   | Test                                           | Setup                       | Assert                                |
| --- | ---------------------------------------------- | --------------------------- | ------------------------------------- |
| 1   | Copies gitconfig when source exists            | `Mock Test-Path { $true }`  | `Should -Invoke Copy-Item -Times 1`   |
| 2   | Removes existing `~/.gitconfig` before copying | `Mock Test-Path { $true }`  | `Should -Invoke Remove-Item -Times 1` |
| 3   | Skips copy when source does not exist          | `Mock Test-Path { $false }` | `Should -Invoke Copy-Item -Times 0`   |

### `Enable-RequiredWindowsOptionalFeature` — 1 new test (regression for bug 1)

| #   | Test                                                                      | Setup                                                                                                                          | Assert                                                  |
| --- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------- |
| 1   | Enables only the disabled feature when one is disabled and one is enabled | `Mock Get-WindowsOptionalFeature` returns `Disabled` for `Microsoft-Hyper-V` and `Enabled` for `Containers-DisposableClientVM` | `Should -Invoke Enable-WindowsOptionalFeature -Times 1` |

---

## Test count projection

| File                                       | Before | Added | After |
| ------------------------------------------ | ------ | ----- | ----- |
| `powershell/tests/setup_windows.Tests.ps1` | 9      | +13   | 22    |
