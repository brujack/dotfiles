BeforeAll {
  # Stub commands that don't exist on macOS so dot-sourcing and mocking work
  if (-Not (Get-Command Get-Boxstarter -ErrorAction SilentlyContinue)) {
    function global:Get-Boxstarter { }
  }
  if (-Not (Get-Command choco -ErrorAction SilentlyContinue)) {
    function global:choco { }
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
