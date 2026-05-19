BeforeAll {
  # Stub commands that don't exist on macOS so dot-sourcing and mocking work
  if (-Not (Get-Command Get-Boxstarter -ErrorAction SilentlyContinue)) {
    function global:Get-Boxstarter { }
  }
  if (-Not (Get-Command choco -ErrorAction SilentlyContinue)) {
    function global:choco { }
  }
  if (-Not (Get-Command 'shutdown.exe' -ErrorAction SilentlyContinue)) {
    function global:shutdown.exe { }
  }
  if (-Not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
    function global:Get-WindowsOptionalFeature { }
  }
  if (-Not (Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
    function global:Enable-WindowsOptionalFeature { }
  }
  if (-Not (Get-Command Set-NetFirewallProfile -ErrorAction SilentlyContinue)) {
    function global:Set-NetFirewallProfile { }
  }
  if (-Not (Get-Command Set-WindowsExplorerOptions -ErrorAction SilentlyContinue)) {
    function global:Set-WindowsExplorerOptions { }
  }
  if (-Not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    function global:wsl { }
  }
  if (-Not (Get-Command npm -ErrorAction SilentlyContinue)) {
    function global:npm { }
  }
  . "$PSScriptRoot/../setup_windows.ps1"
}

Describe "Install-ChocolateyPackage" {
  BeforeEach {
    Mock Invoke-Expression { }
    Mock Get-Boxstarter { }
    Mock Set-ExecutionPolicy { }
    Mock New-Object {
      $fakeWC = [PSCustomObject]@{}
      $fakeWC | Add-Member -MemberType ScriptMethod -Name 'DownloadString' -Value { return 'Write-Output stub' }
      return $fakeWC
    } -ParameterFilter { $TypeName -eq 'System.Net.WebClient' }
    Mock Write-Output { }
  }

  It "installs choco bootstrapper when choco.exe is not found" {
    Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco { @() }
    Install-ChocolateyPackage
    Should -Invoke Invoke-Expression -Times 1 -Exactly
  }

  It "skips choco bootstrapper when choco.exe is already present" {
    Mock Get-Command {
      return [PSCustomObject]@{ Name = 'choco.exe' }
    } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco { @() }
    Install-ChocolateyPackage
    Should -Invoke Invoke-Expression -Times 0
  }

  It "calls choco install for packages not in the installed list" {
    Mock Get-Command {
      return [PSCustomObject]@{ Name = 'choco.exe' }
    } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco { @() } -ParameterFilter { $args[0] -eq 'list' }
    Mock choco { } -ParameterFilter { $args[0] -eq 'install' }
    Install-ChocolateyPackage
    Should -Invoke choco -ParameterFilter { $args[0] -eq 'install' } -Times 1
  }

  It "skips choco install for packages already in the installed list" {
    Mock Get-Command {
      return [PSCustomObject]@{ Name = 'choco.exe' }
    } -ParameterFilter { $Name -eq 'choco.exe' }
    Mock choco {
      @(
        "1password 1.0",
        "adobereader 1.0",
        "ag 1.0",
        "atom 1.0",
        "awscli 1.0",
        "azure-cli 1.0",
        "bat 1.0",
        "bambustudio 1.0",
        "beyondcompare 1.0",
        "boxstarter 1.0",
        "claude 1.0",
        "claude-code 1.0",
        "crystaldiskmark 1.0",
        "cursoride 1.0",
        "dbeaver 1.0",
        "discord 1.0",
        "docker-desktop 1.0",
        "docker-compose 1.0",
        "dotnet 1.0",
        "evernote 1.0",
        "firefox 1.0",
        "fzf 1.0",
        "gcloudsdk 1.0",
        "geekbench 1.0",
        "gh 1.0",
        "git 1.0",
        "git-lfs 1.0",
        "golang 1.0",
        "googlechrome 1.0",
        "go-task 1.0",
        "iperf3 1.0",
        "k9s 1.0",
        "kubernetes-cli 1.0",
        "kubernetes-helm 1.0",
        "launchy 1.0",
        "lazydocker 1.0",
        "make 1.0",
        "microsoft-teams 1.0",
        "microsoft-windows-terminal 1.0",
        "mongosh 1.0",
        "mongodb-atlas 1.0",
        "neovim 1.0",
        "nodejs 1.0",
        "postman 1.0",
        "powertoys 1.0",
        "putty.install 1.0",
        "python3 1.0",
        "reflect-free 1.0",
        "ripgrep 1.0",
        "rust 1.0",
        "simplenote 1.0",
        "slack 1.0",
        "sourcetree 1.0",
        "spotify 1.0",
        "starship 1.0",
        "steam-client 1.0",
        "teamviewer 1.0",
        "terraform 1.0",
        "typora 1.0",
        "vlc 1.0",
        "vscode 1.0",
        "winscp 1.0",
        "zed 1.0",
        "zoom 1.0",
        "zoxide 1.0",
        "7zip 1.0"
      )
    } -ParameterFilter { $args[0] -eq 'list' }
    Mock choco { } -ParameterFilter { $args[0] -eq 'install' }
    Install-ChocolateyPackage
    Should -Invoke choco -ParameterFilter { $args[0] -eq 'install' } -Times 0
  }
}

Describe "Install-WindowsUpdate" {
  BeforeEach {
    Mock 'shutdown.exe' { }
  }

  It "calls Download and Install when updates are found" {
    $script:downloadCalled = $false
    $script:installCalled  = $false
    $script:installResult  = [PSCustomObject]@{ rebootRequired = $false }

    $fakeDownloader = [PSCustomObject]@{ Updates = $null }
    $fakeDownloader | Add-Member -MemberType ScriptMethod -Name 'Download' -Value {
      $script:downloadCalled = $true
    }

    $fakeInstaller = [PSCustomObject]@{ Updates = $null }
    $fakeInstaller | Add-Member -MemberType ScriptMethod -Name 'Install' -Value {
      $script:installCalled = $true
      return $script:installResult
    }

    $fakeUpdates       = @([PSCustomObject]@{ Title = 'Security Update 1' })
    $fakeSearchResult  = [PSCustomObject]@{ Updates = $fakeUpdates }
    $fakeSearcher      = [PSCustomObject]@{}
    $fakeSearcher | Add-Member -MemberType ScriptMethod -Name 'Search' -Value {
      return $script:searchResult
    }

    $fakeSession = [PSCustomObject]@{}
    $fakeSession | Add-Member -MemberType ScriptMethod -Name 'CreateUpdateDownloader' -Value {
      return $script:downloader
    }

    $script:searchResult = $fakeSearchResult
    $script:downloader   = $fakeDownloader
    $script:searcher     = $fakeSearcher
    $script:session      = $fakeSession
    $script:installer    = $fakeInstaller

    Mock Get-UpdateSearcher  { return $script:searcher  }
    Mock Get-UpdateSession   { return $script:session   }
    Mock Get-UpdateInstaller { return $script:installer }

    Install-WindowsUpdate

    $script:downloadCalled | Should -Be $true
    $script:installCalled  | Should -Be $true
  }

  It "skips Download and Install when no updates are found" {
    $script:downloadCalled = $false
    $script:installCalled  = $false

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
    $fakeSearcher     = [PSCustomObject]@{}
    $fakeSearcher | Add-Member -MemberType ScriptMethod -Name 'Search' -Value {
      return $script:searchResult
    }

    $fakeSession = [PSCustomObject]@{}
    $fakeSession | Add-Member -MemberType ScriptMethod -Name 'CreateUpdateDownloader' -Value {
      return $script:downloader
    }

    $script:searchResult = $fakeSearchResult
    $script:downloader   = $fakeDownloader
    $script:searcher     = $fakeSearcher
    $script:session      = $fakeSession
    $script:installer    = $fakeInstaller

    Mock Get-UpdateSearcher  { return $script:searcher  }
    Mock Get-UpdateSession   { return $script:session   }
    Mock Get-UpdateInstaller { return $script:installer }

    Install-WindowsUpdate

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

    $fakeUpdates      = @([PSCustomObject]@{ Title = 'Update 1' })
    $fakeSearchResult = [PSCustomObject]@{ Updates = $fakeUpdates }
    $fakeSearcher     = [PSCustomObject]@{}
    $fakeSearcher | Add-Member -MemberType ScriptMethod -Name 'Search' -Value {
      return $script:searchResult
    }

    $fakeSession = [PSCustomObject]@{}
    $fakeSession | Add-Member -MemberType ScriptMethod -Name 'CreateUpdateDownloader' -Value {
      return $script:downloader
    }

    $script:searchResult = $fakeSearchResult
    $script:downloader   = $fakeDownloader
    $script:searcher     = $fakeSearcher
    $script:session      = $fakeSession
    $script:installer    = $fakeInstaller

    Mock Get-UpdateSearcher  { return $script:searcher  }
    Mock Get-UpdateSession   { return $script:session   }
    Mock Get-UpdateInstaller { return $script:installer }

    Install-WindowsUpdate

    Should -Invoke 'shutdown.exe' -Times 1
  }
}

Describe "Set-WindowsOption" {
  BeforeEach {
    Mock Set-ItemProperty { }
    Mock Set-NetFirewallProfile { }
    Mock Set-WindowsExplorerOptions { }
  }

  It "calls Set-ItemProperty to enable RDP" {
    Set-WindowsOption
    Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq 'fDenyTSConnections' } -Times 1
  }

  It "calls Set-NetFirewallProfile to disable all profiles" {
    Set-WindowsOption
    Should -Invoke Set-NetFirewallProfile -Times 1
  }

  It "calls Set-WindowsExplorerOptions with correct flags" {
    Set-WindowsOption
    Should -Invoke Set-WindowsExplorerOptions -Times 1
  }
}

Describe "Install-WSL" {
  It "calls wsl --install when WSL2 is not configured" {
    Mock wsl { @() } -ParameterFilter { $args -contains '--status' }
    Mock wsl { } -ParameterFilter { $args -contains '--install' }
    Install-WSL
    Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 1
  }

  It "skips wsl --install when WSL2 is already the default" {
    Mock wsl { "WSL version: 2.3.26`nDefault Version: 2`nKernel version: 5.15.0" } -ParameterFilter { $args -contains '--status' }
    Mock wsl { } -ParameterFilter { $args -contains '--install' }
    Install-WSL
    Should -Invoke wsl -ParameterFilter { $args -contains '--install' } -Times 0
  }
}

Describe "Enable-RequiredWindowsOptionalFeature" {
  BeforeEach {
    Mock Write-Output { }
  }

  It "enables features that are disabled" {
    Mock Get-WindowsOptionalFeature {
      [PSCustomObject]@{ FeatureName = $FeatureName; State = 'Disabled' }
    }
    Mock Enable-WindowsOptionalFeature { }

    Enable-RequiredWindowsOptionalFeature

    Should -Invoke Enable-WindowsOptionalFeature -Times 1
  }

  It "skips enabling features that are already enabled" {
    Mock Get-WindowsOptionalFeature {
      [PSCustomObject]@{ FeatureName = $FeatureName; State = 'Enabled' }
    }
    Mock Enable-WindowsOptionalFeature { }

    Enable-RequiredWindowsOptionalFeature

    Should -Invoke Enable-WindowsOptionalFeature -Times 0
  }

  It "enables only the disabled feature when one is disabled and one is already enabled" {
    Mock Get-WindowsOptionalFeature {
      param([switch]$Online, $FeatureName)
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
}

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

  It "rethrows when New-Item fails" {
    Mock Test-Path { $false } -ParameterFilter { $Path -like '*/.config' }
    Mock New-Item { throw "permission denied" }
    { New-DirectoryStructure } | Should -Throw "permission denied"
  }
}

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

  It "rethrows when Copy-Item fails" {
    Mock Test-Path { $true }
    Mock Copy-Item { throw "disk full" }
    { Copy-GitConfig } | Should -Throw "disk full"
  }
}

Describe "Invoke-DotfilesSetup" {
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
}

Describe "Invoke-DotfilesUpdate" {
  BeforeEach {
    Mock choco                 { }
    Mock Install-WindowsUpdate { }
    Mock Install-AiConfig      { }
    Mock Set-NpmGlobalPackages { }
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
  It "calls Install-AiConfig to pull latest config" {
    Invoke-DotfilesUpdate
    Should -Invoke Install-AiConfig -Times 1 -Exactly
  }
  It "calls Set-NpmGlobalPackages to update npm globals" {
    Invoke-DotfilesUpdate
    Should -Invoke Set-NpmGlobalPackages -Times 1 -Exactly
  }
}

Describe "COM update wrappers" {
  # On macOS/Linux, New-Object lacks the -ComObject parameter entirely, so
  # parameter binding fails before any mock can intercept. We override
  # New-Object as a global function inside this Describe so the script's
  # `New-Object -ComObject ...` calls resolve to our stub.
  BeforeAll {
    function global:New-Object {
      param(
        [Parameter(Position=0)] [string]$TypeName,
        [string]$ComObject,
        [object[]]$ArgumentList,
        [hashtable]$Property
      )
      [PSCustomObject]@{ ComObject = $ComObject; TypeName = $TypeName }
    }
  }
  AfterAll {
    Remove-Item function:global:New-Object -ErrorAction SilentlyContinue
  }

  It "Get-UpdateSearcher creates Microsoft.Update.Searcher COM object" {
    $result = Get-UpdateSearcher
    $result.ComObject | Should -Be 'Microsoft.Update.Searcher'
  }
  It "Get-UpdateSession creates Microsoft.Update.Session COM object" {
    $result = Get-UpdateSession
    $result.ComObject | Should -Be 'Microsoft.Update.Session'
  }
  It "Get-UpdateInstaller creates Microsoft.Update.Installer COM object" {
    $result = Get-UpdateInstaller
    $result.ComObject | Should -Be 'Microsoft.Update.Installer'
  }
}

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
    Should -Invoke New-Item    -Times 0
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

Describe "Install-AiConfig" {
  BeforeEach {
    $global:LASTEXITCODE = 0
    Mock git          { }
    Mock Write-Output { }
    Mock Test-Path    { $false }
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

Describe "Set-ClaudeConfig" {
  BeforeEach {
    $script:savedPAT = $env:GITHUB_PAT
    $env:GITHUB_PAT  = $null
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
    Should -Invoke New-Item -ParameterFilter { $Path -like '*/.cursor' }     -Times 1
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

Describe "Set-NpmGlobalPackages" {
  BeforeEach {
    Mock npm           { }
    Mock Write-Output  { }
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
    Should -Invoke npm           -Times 0
    Should -Invoke Write-Warning -Times 1
  }
}
