# PowerShell Test Coverage Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Add unit tests and linting for `powershell/setup_windows.ps1` using Pester v5 and PSScriptAnalyzer, runnable cross-platform via `pwsh` on macOS or Windows, with a standalone `powershell/Makefile`.

## Scope

- **In scope:** `powershell/Makefile`, `powershell/tests/setup_windows.Tests.ps1`, restructure of `setup_windows.ps1` to move function definitions outside the `if ($IsWindows)` guard
- **Out of scope:** Integration into the root `Makefile`, changing any function logic in `setup_windows.ps1`, adding tests for scripts outside `powershell/`

## Architecture

Functions are moved above the `if ($IsWindows)` guard so they can be dot-sourced in tests on macOS (`$IsWindows` is false, so the invocation block never runs). Tests dot-source the script in a `BeforeAll` block, then use Pester `Mock` to intercept external commands (`choco`, `New-Object`, `shutdown.exe`, `Get-WindowsOptionalFeature`, `Enable-WindowsOptionalFeature`).

PSScriptAnalyzer provides static analysis (undefined variables, deprecated aliases, unused parameters). `test: lint` ensures lint failures block the test run.

---

## Section 1: Script restructure

### Modified file: `powershell/setup_windows.ps1`

Move these three function definitions above the `if ($IsWindows)` block:
- `Install-ChocolateyPackages`
- `Install-WindowsUpdates`
- `Enable-WindowsOptionalFeatures` (currently defined inside `if ($setup.IsPresent)` — move to top level)

The `if ($IsWindows)` block retains only invocation logic:
```powershell
function Install-ChocolateyPackages { ... }
function Install-WindowsUpdates { ... }
function Enable-WindowsOptionalFeatures { ... }

if ($IsWindows) {
  if ($setup.IsPresent) {
    # registry/firewall/wsl/directory setup calls
    Install-ChocolateyPackages
    Enable-WindowsOptionalFeatures
    ...
  }
  if ($update.IsPresent) {
    choco upgrade all -y
    ...
    Install-WindowsUpdates
  }
}
```

---

## Section 2: Test file

### New file: `powershell/tests/setup_windows.Tests.ps1`

```powershell
BeforeAll {
  . "$PSScriptRoot/../setup_windows.ps1"
}
```

### `Install-ChocolateyPackages` — 4 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Installs choco when absent | Mock `Get-Command` to return `$null` | `iex` called (bootstrapper invoked) |
| 2 | Skips choco install when present | Mock `Get-Command` to return a fake command object | `iex` not called |
| 3 | Calls `choco install` for absent package | Mock `choco list -lo` returning list without the package | `choco install <package> -y` called |
| 4 | Skips `choco install` for present package | Mock `choco list -lo` returning list with the package | `choco install` not called |

### `Install-WindowsUpdates` — 3 tests

COM objects are mocked by replacing `New-Object` with a mock that returns fake PSCustomObjects with controllable `Updates`, `Download()`, `Install()`, and `rebootRequired` properties.

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Downloads and installs when updates found | Fake searcher returns non-empty updates | `Download()` and `Install()` called |
| 2 | Skips download/install when no updates | Fake searcher returns empty updates | `Download()` and `Install()` not called |
| 3 | Reboots when rebootRequired is true | Fake installer result has `rebootRequired = $true` | `shutdown.exe /t 0 /r` called |

### `Enable-WindowsOptionalFeatures` — 2 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Enables feature when disabled | Mock `Get-WindowsOptionalFeature` returns `State = Disabled` | `Enable-WindowsOptionalFeature` called |
| 2 | Skips feature when already enabled | Mock `Get-WindowsOptionalFeature` returns `State = Enabled` | `Enable-WindowsOptionalFeature` not called |

---

## Section 3: Makefile

### New file: `powershell/Makefile`

```makefile
.PHONY: test lint help

help:
	@printf "Available targets:\n"
	@printf "  make test   Run Pester tests\n"
	@printf "  make lint   Run PSScriptAnalyzer\n"
	@printf "  make help   Show this help\n"

lint:
	pwsh -Command "Import-Module PSScriptAnalyzer; \
	  $$results = Invoke-ScriptAnalyzer -Path . -Recurse; \
	  $$results | Format-Table -AutoSize; \
	  if ($$results) { exit 1 }"

test: lint
	pwsh -Command "Import-Module Pester; \
	  Invoke-Pester tests/ -Output Detailed -CI"
```

`-CI` on `Invoke-Pester` causes non-zero exit on any test failure. PSScriptAnalyzer exits non-zero if any rule violations are found.

---

## Test count projection

| File | Tests |
|---|---|
| `powershell/tests/setup_windows.Tests.ps1` | 9 |

## Dependencies

- `pwsh` (PowerShell Core) — must be installed: `brew install --cask powershell`
- `Pester` v5 — installed via: `pwsh -Command "Install-Module Pester -Force -Scope CurrentUser"`
- `PSScriptAnalyzer` — installed via: `pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"`
