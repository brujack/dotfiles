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
if ($IsWindows) {

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
      "beyondcompare",
      "boxstarter",
      "crystaldiskmark",
      "dbeaver",
      "docker-desktop",
      "docker-compose",
      "dropbox",
      "evernote",
      "firefox",
      "fzf",
      "gcloudsdk",
      "geekbench",
      "gh",
      "git",
      "golang",
      "googlechrome",
      "go-task",
      "iperf3",
      "kubernetes-cli",
      "kubernetes-helm",
      "launchy",
      "make",
      "microsoft-teams",
      "microsoft-windows-terminal",
      "postman",
      "powertoys",
      "putty.install",
      "python3",
      "simplenote",
      "sourcetree",
      "spotify",
      "starship",
      "teamviewer",
      "terraform",
      "typora",
      "vlc",
      "vscode",
      "winscp",
      "zoom",
      "7zip"
    )

    # check to see if a package is installed before installing it
    foreach ($package in $ChocoPackagesToBeInstalled) {
      $result = choco list -lo | Where-object { $_.ToLower().StartsWith("$package".ToLower()) }
      if ($result -eq $null) {
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
    $Downloader.Download()

    # install updates
    $Installer = New-Object -ComObject Microsoft.Update.Installer
    $Installer.Updates = $SearchResult
    $Result = $Installer.Install()

    # reboot if required
    If ($Result.rebootRequired) { shutdown.exe /t 0 /r }
  }

  if ($setup.IsPresent) {
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
