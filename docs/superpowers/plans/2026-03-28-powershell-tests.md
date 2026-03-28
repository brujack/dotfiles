# PowerShell Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Pester v5 unit tests and PSScriptAnalyzer linting for `powershell/setup_windows.ps1`, runnable cross-platform via `pwsh` from a standalone `powershell/Makefile`.

**Architecture:** Three functions (`Install-ChocolateyPackages`, `Install-WindowsUpdates`, `Enable-WindowsOptionalFeatures`) are moved outside the `if ($IsWindows)` guard so they can be dot-sourced in tests on macOS. External commands are mocked with Pester's `Mock`. COM objects are mocked with `PSCustomObject` instances carrying script-method members, with script-scoped tracking variables to verify calls. `make test` depends on `make lint`, which runs PSScriptAnalyzer against `setup_windows.ps1`.

**Tech Stack:** PowerShell Core (pwsh), Pester v5, PSScriptAnalyzer

---

## File Structure

**New files:**
- `powershell/Makefile` — `lint`, `test`, `help` targets; `test: lint`
- `powershell/PSScriptAnalyzerSettings.psd1` — excludes `PSAvoidUsingInvokeExpression` (official Chocolatey bootstrapper requires it)
- `powershell/tests/setup_windows.Tests.ps1` — 9 Pester tests for all 3 functions

**Modified files:**
- `powershell/setup_windows.ps1` — move 3 function definitions above `if ($IsWindows)`; fix `$null -eq $result` comparison order

---

### Task 1: Create Makefile and PSScriptAnalyzer settings

**Files:**
- Create: `powershell/Makefile`
- Create: `powershell/PSScriptAnalyzerSettings.psd1`

**Context:** Pester v5 and PSScriptAnalyzer must be installed before the Makefile targets will work. Install them once as the first step. The Makefile mirrors the root repo pattern: `test: lint`, tab-indented recipes, `help` target.

- [ ] **Step 1: Install Pester v5 and PSScriptAnalyzer**

```bash
pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"
```

Expected: both install without error.

- [ ] **Step 2: Create powershell/PSScriptAnalyzerSettings.psd1**

```powershell
@{
  ExcludeRules = @(
    # The official Chocolatey bootstrapper uses Invoke-Expression — cannot be changed
    'PSAvoidUsingInvokeExpression'
  )
}
```

- [ ] **Step 3: Create powershell/Makefile**

```makefile
.PHONY: test lint help

help:
	@printf "Available targets:\n"
	@printf "  make test   Run Pester tests (requires pwsh, Pester v5)\n"
	@printf "  make lint   Run PSScriptAnalyzer on setup_windows.ps1\n"
	@printf "  make help   Show this help\n"

lint:
	pwsh -Command " \
	  Import-Module PSScriptAnalyzer; \
	  $$results = Invoke-ScriptAnalyzer -Path ./setup_windows.ps1 \
	    -Settings ./PSScriptAnalyzerSettings.psd1; \
	  $$results | Format-Table -AutoSize; \
	  if ($$results) { exit 1 }"

test: lint
	pwsh -Command " \
	  Import-Module Pester; \
	  $$config = New-PesterConfiguration; \
	  $$config.Run.Path = 'tests/'; \
	  $$config.Output.Verbosity = 'Detailed'; \
	  $$config.Run.Exit = $$true; \
	  Invoke-Pester -Configuration $$config"
```

Note: `$$` in Makefile produces `$` in the shell, which PowerShell receives as a variable sigil.

- [ ] **Step 4: Run make lint on the current unmodified script**

```bash
cd /path/to/dotfiles/powershell && make lint
```

Expected: PSScriptAnalyzer reports violations. The likely violation is `PSPossibleIncorrectComparisonWithNull` for the line `if ($result -eq $null)` — this will be fixed in Task 2 during the restructure. If there are other violations not covered in Task 2, fix them now.

- [ ] **Step 5: Commit**

```bash
git add powershell/Makefile powershell/PSScriptAnalyzerSettings.psd1
git commit -m "feat: add powershell/Makefile with lint and test targets

Uses PSScriptAnalyzer for linting and Pester v5 for unit tests.
PSAvoidUsingInvokeExpression excluded: official Chocolatey bootstrapper
requires iex.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Restructure setup_windows.ps1

**Files:**
- Modify: `powershell/setup_windows.ps1`

**Context:** The three functions are currently inside `if ($IsWindows)`. On macOS `$IsWindows` is `$false`, so dot-sourcing the script in tests does not define any functions. Moving the definitions above the guard makes them accessible on all platforms. The invocation logic (calls to the functions plus registry/WSL/directory setup) stays inside `if ($IsWindows)`. Also fix `$result -eq $null` → `$null -eq $result` (PSPossibleIncorrectComparisonWithNull).

- [ ] **Step 1: Replace the entire file with the restructured version**

```powershell
<#
.SYNOPSIS

This will setup a new windows 10/11 instance and keep it up to date

.PARAMETER -setup
Whether to do an initial setup

.PARAMETER -update
Whether to update installed chocolatey, windows packages and powershell modules

#>

param(
  [Parameter(Mandatory=$false)]
  [Switch]$setup,
  [Switch]$update
)

function Install-ChocolateyPackages {
  if (-Not (Get-Command "choco.exe" -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://boxstarter.org/bootstrapper.ps1')); Get-Boxstarter -Force
  }

  $ChocoPackagesToBeInstalled = @(
    "1password",
    "adobereader",
    "ag",
    "atom",
    "awscli",
    "azure-cli",
    "bat",
    "bambustudio"
    "beyondcompare",
    "boxstarter",
    "claude",
    "claude-code",
    "crystaldiskmark",
    "dbeaver",
    "discord",
    "docker-desktop",
    "docker-compose",
    "dotnet",
    "evernote",
    "firefox",
    "fzf",
    "gcloudsdk",
    "geekbench",
    "gh",
    "git",
    "git-lfs",
    "golang",
    "googlechrome",
    "go-task",
    "iperf3",
    "k9s",
    "kubernetes-cli",
    "kubernetes-helm",
    "launchy",
    "lazydocker",
    "make",
    "microsoft-teams",
    "microsoft-windows-terminal",
    "mongosh",
    "mongodb-atlas",
    "neovim",
    "postman",
    "powertoys",
    "putty.install",
    "python3",
    "reflect-free",
    "ripgrep",
    "rust",
    "simplenote",
    "slack",
    "sourcetree",
    "spotify",
    "starship",
    "steam-client",
    "teamviewer",
    "terraform",
    "typora",
    "vlc",
    "vscode",
    "winscp",
    "zed",
    "zoom",
    "zoxide",
    "7zip"
  )

  # check to see if a package is installed before installing it
  foreach ($package in $ChocoPackagesToBeInstalled) {
    $result = choco list -lo | Where-object { $_.ToLower().StartsWith("$package".ToLower()) }
    if ($null -eq $result) {
      choco install $package -y
      Write-Output "Installed $package"
    }
    else {
      Write-Output "$package already installed"
    }
  }
}

function Install-WindowsUpdates {
  # define update criteria
  $Criteria = "IsInstalled=0"

  # search for relevant updates.
  $Searcher = New-Object -ComObject Microsoft.Update.Searcher
  $SearchResult = $Searcher.Search($Criteria).Updates

  # download updates
  $Session = New-Object -ComObject Microsoft.Update.Session
  $Downloader = $Session.CreateUpdateDownloader()
  $Downloader.Updates = $SearchResult
  if ($SearchResult) {
    $Downloader.Download()
  }

  # install updates
  $Installer = New-Object -ComObject Microsoft.Update.Installer
  $Installer.Updates = $SearchResult
  if ($SearchResult) {
    $Result = $Installer.Install()
  }

  # reboot if required
  If ($Result.rebootRequired) { shutdown.exe /t 0 /r }
}

function Enable-WindowsOptionalFeatures {
  # enable hyper-v and sandbox containers
  $RequiredWindowsOptionalFeatures = @(
    "Microsoft-Hyper-V"
    "Containers-DisposableClientVM"
  )
  $RequiredWindowsOptionalFeaturesResults = foreach ($feature in $RequiredWindowsOptionalFeatures) {Get-WindowsOptionalFeature -Online -FeatureName $feature | Where-Object {$_.State -eq "Disabled"}}

  if ($RequiredWindowsOptionalFeaturesResults) {
    foreach ($features in $RequiredWindowsOptionalFeatures) {
      Enable-WindowsOptionalFeature -Online -FeatureName $features
      Write-Output "Enabled feature $features"
    }
  }
}

if ($IsWindows) {
  if ($setup.IsPresent) {
    # set windows options
    # enable RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -value 0
    # turn off firewall
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar

    Install-ChocolateyPackages

    Enable-WindowsOptionalFeatures

    # enable wsl
    $WSLEnabled = wsl --status
    if (-Not ($WSLEnabled -contains "Default Version: 2")) {
      wsl --install
    }

    # enable current user to be able to execute powershell scripts
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser

    if (-Not (Test-Path -Path ~/.config -PathType Container)) {
      try {
        $null = New-Item -ItemType File -Path ~/.config -Force -ErrorAction Stop
        Write-Output "The directory [~/.config] has been created."
      }
      catch {
          throw $_.Exception.Message
      }
    }

    if (-Not (Test-Path -Path ~/git-repos/personal -PathType Container)) {
      try {
        $null = New-Item -ItemType File -Path ~/git-repos/personal -Force -ErrorAction Stop
        Write-Output "The directory [~/git-repos/personal] has been created."
      }
      catch {
          throw $_.Exception.Message
      }
    }

    if (Test-Path -Path ~/.gitconfig -PathType Leaf) {
      try {
        $null = Remove-Item ~/.gitconfig -ErrorAction SilentlyContinue
        $null = Copy-Item -Path ~/git-repos/personal/dotfiles/.gitconfig_windows -Destination ~/.gitconfig -ErrorAction SilentlyContinue
        Write-Output "copied ~/.gitconfig"
      }
      catch {
        throw $_.Exception.Message
      }
    }

  }

  if ($update.IsPresent) {
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
    Install-WindowsUpdates
  }
}
```

- [ ] **Step 2: Run make lint to verify no violations**

```bash
cd /path/to/dotfiles/powershell && make lint
```

Expected: exit 0, no output (no violations). If violations appear, fix them before proceeding.

- [ ] **Step 3: Commit**

```bash
git add powershell/setup_windows.ps1
git commit -m "refactor: move functions outside IsWindows guard for testability

Enables dot-sourcing on macOS in Pester tests. Also fixes null comparison
order: \$null -eq \$result (PSPossibleIncorrectComparisonWithNull).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Write Install-ChocolateyPackages tests

**Files:**
- Create: `powershell/tests/setup_windows.Tests.ps1`

**Context:** Pester v5 syntax: `Describe`/`It`/`BeforeEach`/`Mock`/`Should -Invoke`. `BeforeAll` dot-sources the script — on macOS `$IsWindows` is `$false` so only the function definitions load. `Mock choco` intercepts all `choco` calls; `-ParameterFilter { $args[0] -eq 'list' }` distinguishes `choco list` from `choco install`. `Should -Invoke cmd -Times 0` asserts never called; `-Times 1` asserts called at least once.

- [ ] **Step 1: Create powershell/tests/setup_windows.Tests.ps1**

```powershell
BeforeAll {
  . "$PSScriptRoot/../setup_windows.ps1"
}

Describe "Install-ChocolateyPackages" {
  BeforeEach {
    Mock Invoke-Expression { }
    Mock Get-Boxstarter { }
    Mock New-Object {
      $fakeWC = [PSCustomObject]@{}
      $fakeWC | Add-Member -MemberType ScriptMethod -Name 'DownloadString' -Value { return '' }
      return $fakeWC
    } -ParameterFilter { $TypeName -eq 'System.Net.WebClient' }
    Mock Write-Output { }
  }

  It "installs choco bootstrapper when choco.exe is not found" {
    Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco { @() }
    Install-ChocolateyPackages
    Should -Invoke Invoke-Expression -Times 1 -Exactly
  }

  It "skips choco bootstrapper when choco.exe is already present" {
    Mock Get-Command {
      return [PSCustomObject]@{ Name = 'choco.exe' }
    } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco { @() }
    Install-ChocolateyPackages
    Should -Invoke Invoke-Expression -Times 0
  }

  It "calls choco install for packages not in the installed list" {
    Mock Get-Command {
      return [PSCustomObject]@{ Name = 'choco.exe' }
    } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco { @() } -ParameterFilter { $args[0] -eq 'list' }
    Mock choco { } -ParameterFilter { $args[0] -eq 'install' }
    Install-ChocolateyPackages
    Should -Invoke choco -ParameterFilter { $args[0] -eq 'install' } -Times 1
  }

  It "skips choco install for packages already in the installed list" {
    Mock Get-Command {
      return [PSCustomObject]@{ Name = 'choco.exe' }
    } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco {
      @(
        "1password 1.0", "adobereader 1.0", "ag 1.0", "atom 1.0", "awscli 1.0",
        "azure-cli 1.0", "bat 1.0", "bambustudio 1.0", "beyondcompare 1.0",
        "boxstarter 1.0", "claude 1.0", "claude-code 1.0", "crystaldiskmark 1.0",
        "dbeaver 1.0", "discord 1.0", "docker-desktop 1.0", "docker-compose 1.0",
        "dotnet 1.0", "evernote 1.0", "firefox 1.0", "fzf 1.0", "gcloudsdk 1.0",
        "geekbench 1.0", "gh 1.0", "git 1.0", "git-lfs 1.0", "golang 1.0",
        "googlechrome 1.0", "go-task 1.0", "iperf3 1.0", "k9s 1.0",
        "kubernetes-cli 1.0", "kubernetes-helm 1.0", "launchy 1.0",
        "lazydocker 1.0", "make 1.0", "microsoft-teams 1.0",
        "microsoft-windows-terminal 1.0", "mongosh 1.0", "mongodb-atlas 1.0",
        "neovim 1.0", "postman 1.0", "powertoys 1.0", "putty.install 1.0",
        "python3 1.0", "reflect-free 1.0", "ripgrep 1.0", "rust 1.0",
        "simplenote 1.0", "slack 1.0", "sourcetree 1.0", "spotify 1.0",
        "starship 1.0", "steam-client 1.0", "teamviewer 1.0", "terraform 1.0",
        "typora 1.0", "vlc 1.0", "vscode 1.0", "winscp 1.0", "zed 1.0",
        "zoom 1.0", "zoxide 1.0", "7zip 1.0"
      )
    } -ParameterFilter { $args[0] -eq 'list' }
    Mock choco { } -ParameterFilter { $args[0] -eq 'install' }
    Install-ChocolateyPackages
    Should -Invoke choco -ParameterFilter { $args[0] -eq 'install' } -Times 0
  }
}
```

- [ ] **Step 2: Run the tests**

```bash
cd /path/to/dotfiles/powershell && make test
```

Expected: 4 tests pass, 0 failures. If a test fails, check that the mock for `Get-Command` uses the exact parameter name (`$Name`) that `Get-Command` binds the positional argument to.

- [ ] **Step 3: Commit**

```bash
git add powershell/tests/setup_windows.Tests.ps1
git commit -m "test: add Install-ChocolateyPackages tests (4 tests)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Write Install-WindowsUpdates tests

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`

**Context:** `Install-WindowsUpdates` uses COM objects (`New-Object -ComObject`). These can't be mocked at the COM level — instead, mock `New-Object` with `-ParameterFilter { $ComObject -eq '...' }` and return `PSCustomObject` instances with `Add-Member ScriptMethod` for `Search`, `CreateUpdateDownloader`, `Download`, and `Install`. Use script-scoped variables (`$script:`) to track whether methods were called, since Pester's `Should -Invoke` doesn't cover method calls on objects. `shutdown.exe` is a regular external command — mock it with `Mock 'shutdown.exe' { }`.

- [ ] **Step 1: Append Install-WindowsUpdates Describe block to powershell/tests/setup_windows.Tests.ps1**

Append to the end of the file:

```powershell

Describe "Install-WindowsUpdates" {
  BeforeEach {
    Mock 'shutdown.exe' { }
  }

  It "calls Download and Install when updates are found" {
    $script:downloadCalled = $false
    $script:installCalled = $false
    $script:installResult = [PSCustomObject]@{ rebootRequired = $false }

    $fakeDownloader = [PSCustomObject]@{ Updates = $null }
    $fakeDownloader | Add-Member -MemberType ScriptMethod -Name 'Download' -Value {
      $script:downloadCalled = $true
    }

    $fakeInstaller = [PSCustomObject]@{ Updates = $null }
    $fakeInstaller | Add-Member -MemberType ScriptMethod -Name 'Install' -Value {
      $script:installCalled = $true
      return $script:installResult
    }

    $fakeUpdates = @([PSCustomObject]@{ Title = 'Security Update 1' })
    $fakeSearchResult = [PSCustomObject]@{ Updates = $fakeUpdates }
    $fakeSearcher = [PSCustomObject]@{}
    $fakeSearcher | Add-Member -MemberType ScriptMethod -Name 'Search' -Value {
      return $script:searchResult
    }

    $fakeSession = [PSCustomObject]@{}
    $fakeSession | Add-Member -MemberType ScriptMethod -Name 'CreateUpdateDownloader' -Value {
      return $script:downloader
    }

    $script:searchResult = $fakeSearchResult
    $script:downloader = $fakeDownloader
    $script:searcher = $fakeSearcher
    $script:session = $fakeSession
    $script:installer = $fakeInstaller

    Mock New-Object { return $script:searcher } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Searcher' }
    Mock New-Object { return $script:session }  -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
    Mock New-Object { return $script:installer } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Installer' }

    Install-WindowsUpdates

    $script:downloadCalled | Should -Be $true
    $script:installCalled  | Should -Be $true
  }

  It "skips Download and Install when no updates are found" {
    $script:downloadCalled = $false
    $script:installCalled = $false

    $fakeDownloader = [PSCustomObject]@{ Updates = $null }
    $fakeDownloader | Add-Member -MemberType ScriptMethod -Name 'Download' -Value {
      $script:downloadCalled = $true
    }

    $fakeInstaller = [PSCustomObject]@{ Updates = $null }
    $fakeInstaller | Add-Member -MemberType ScriptMethod -Name 'Install' -Value {
      $script:installCalled = $true
      return [PSCustomObject]@{ rebootRequired = $false }
    }

    $fakeSearchResult = [PSCustomObject]@{ Updates = @() }
    $fakeSearcher = [PSCustomObject]@{}
    $fakeSearcher | Add-Member -MemberType ScriptMethod -Name 'Search' -Value {
      return $script:searchResult
    }

    $fakeSession = [PSCustomObject]@{}
    $fakeSession | Add-Member -MemberType ScriptMethod -Name 'CreateUpdateDownloader' -Value {
      return $script:downloader
    }

    $script:searchResult = $fakeSearchResult
    $script:downloader = $fakeDownloader
    $script:searcher = $fakeSearcher
    $script:session = $fakeSession
    $script:installer = $fakeInstaller

    Mock New-Object { return $script:searcher } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Searcher' }
    Mock New-Object { return $script:session }  -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
    Mock New-Object { return $script:installer } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Installer' }

    Install-WindowsUpdates

    $script:downloadCalled | Should -Be $false
    $script:installCalled  | Should -Be $false
  }

  It "calls shutdown when rebootRequired is true" {
    $script:installResult = [PSCustomObject]@{ rebootRequired = $true }

    $fakeDownloader = [PSCustomObject]@{ Updates = $null }
    $fakeDownloader | Add-Member -MemberType ScriptMethod -Name 'Download' -Value { }

    $fakeInstaller = [PSCustomObject]@{ Updates = $null }
    $fakeInstaller | Add-Member -MemberType ScriptMethod -Name 'Install' -Value {
      return $script:installResult
    }

    $fakeUpdates = @([PSCustomObject]@{ Title = 'Update 1' })
    $fakeSearchResult = [PSCustomObject]@{ Updates = $fakeUpdates }
    $fakeSearcher = [PSCustomObject]@{}
    $fakeSearcher | Add-Member -MemberType ScriptMethod -Name 'Search' -Value {
      return $script:searchResult
    }

    $fakeSession = [PSCustomObject]@{}
    $fakeSession | Add-Member -MemberType ScriptMethod -Name 'CreateUpdateDownloader' -Value {
      return $script:downloader
    }

    $script:searchResult = $fakeSearchResult
    $script:downloader = $fakeDownloader
    $script:searcher = $fakeSearcher
    $script:session = $fakeSession
    $script:installer = $fakeInstaller

    Mock New-Object { return $script:searcher } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Searcher' }
    Mock New-Object { return $script:session }  -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
    Mock New-Object { return $script:installer } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Installer' }

    Install-WindowsUpdates

    Should -Invoke 'shutdown.exe' -Times 1
  }
}
```

- [ ] **Step 2: Run the tests**

```bash
cd /path/to/dotfiles/powershell && make test
```

Expected: 7 tests pass (4 from Task 3 + 3 new), 0 failures.

- [ ] **Step 3: Commit**

```bash
git add powershell/tests/setup_windows.Tests.ps1
git commit -m "test: add Install-WindowsUpdates tests (3 tests)

COM objects mocked with PSCustomObject + ScriptMethod members.
shutdown.exe mocked to prevent reboot during testing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Write Enable-WindowsOptionalFeatures tests

**Files:**
- Modify: `powershell/tests/setup_windows.Tests.ps1`

**Context:** `Enable-WindowsOptionalFeatures` calls `Get-WindowsOptionalFeature -Online -FeatureName $feature` (a Windows-only cmdlet) and pipes to `Where-Object {$_.State -eq "Disabled"}`. Mock `Get-WindowsOptionalFeature` to return an object with `State = "Disabled"` or `State = "Enabled"`. Mock `Enable-WindowsOptionalFeature` (also Windows-only) to prevent actual system changes and enable `Should -Invoke` assertions.

- [ ] **Step 1: Append Enable-WindowsOptionalFeatures Describe block to powershell/tests/setup_windows.Tests.ps1**

Append to the end of the file:

```powershell

Describe "Enable-WindowsOptionalFeatures" {
  BeforeEach {
    Mock Write-Output { }
  }

  It "enables features that are disabled" {
    Mock Get-WindowsOptionalFeature {
      [PSCustomObject]@{ FeatureName = $FeatureName; State = 'Disabled' }
    }
    Mock Enable-WindowsOptionalFeature { }

    Enable-WindowsOptionalFeatures

    Should -Invoke Enable-WindowsOptionalFeature -Times 1
  }

  It "skips enabling features that are already enabled" {
    Mock Get-WindowsOptionalFeature {
      [PSCustomObject]@{ FeatureName = $FeatureName; State = 'Enabled' }
    }
    Mock Enable-WindowsOptionalFeature { }

    Enable-WindowsOptionalFeatures

    Should -Invoke Enable-WindowsOptionalFeature -Times 0
  }
}
```

- [ ] **Step 2: Run make test — all 9 tests must pass**

```bash
cd /path/to/dotfiles/powershell && make test
```

Expected: 9 tests pass, 0 failures, exit 0.

- [ ] **Step 3: Commit**

```bash
git add powershell/tests/setup_windows.Tests.ps1
git commit -m "test: add Enable-WindowsOptionalFeatures tests (2 tests)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Update README.md

**Files:**
- Modify: `README.md`

**Context:** The README has a `## Testing` section covering BATS. Add a `### PowerShell` subsection explaining how to test the PowerShell script separately. The root `make test` does NOT cover PowerShell (by design — isolated).

- [ ] **Step 1: Read README.md to find the Testing section**

Read `/path/to/dotfiles/README.md`.

- [ ] **Step 2: Append PowerShell subsection under ## Testing**

After the existing Testing section content, append:

```markdown
### PowerShell

`powershell/` has its own Makefile. Run from the `powershell/` directory:

```bash
cd powershell
make test        # lint then run Pester tests
make lint        # PSScriptAnalyzer only
```

Prerequisites (one-time install):
```bash
pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"
```
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add PowerShell testing instructions to README

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Test count

| File | Tests |
|---|---|
| `powershell/tests/setup_windows.Tests.ps1` | 9 |

## Self-review notes

- All 3 spec functions covered: Install-ChocolateyPackages (4), Install-WindowsUpdates (3), Enable-WindowsOptionalFeatures (2)
- Script restructure is prerequisite for all tests — Task 2 must land before Task 3
- `shutdown.exe` mock uses quoted name `'shutdown.exe'` to match the literal `.exe` call in the script
- `New-Object -ComObject` mocks use `$ComObject` in ParameterFilter — this matches the `-ComObject` parameter name of `New-Object`
- The all-packages list in Task 3 Test 4 exactly mirrors the `$ChocoPackagesToBeInstalled` array from the restructured script — if the package list changes, both must be updated
