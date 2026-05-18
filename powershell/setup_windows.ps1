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

function Install-ChocolateyPackage {
  if (-Not (Get-Command "choco.exe" -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://boxstarter.org/bootstrapper.ps1')); Get-Boxstarter -Force
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
    "cursoride",
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
    "nodejs",
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

function Get-UpdateSearcher  { New-Object -ComObject Microsoft.Update.Searcher  }
function Get-UpdateSession   { New-Object -ComObject Microsoft.Update.Session    }
function Get-UpdateInstaller { New-Object -ComObject Microsoft.Update.Installer  }

function Install-WindowsUpdate {
  # define update criteria
  $Criteria = "IsInstalled=0"

  # search for relevant updates.
  $Searcher = Get-UpdateSearcher
  $SearchResult = $Searcher.Search($Criteria).Updates

  # download updates
  $Session = Get-UpdateSession
  $Downloader = $Session.CreateUpdateDownloader()
  $Downloader.Updates = $SearchResult
  if ($SearchResult) {
    $Downloader.Download()
  }

  # install updates
  $Installer = Get-UpdateInstaller
  $Installer.Updates = $SearchResult
  $Result = $null
  if ($SearchResult) {
    $Result = $Installer.Install()
  }

  # reboot if required
  If ($Result.rebootRequired) { shutdown.exe /t 0 /r }
}

function Enable-RequiredWindowsOptionalFeature {
  # enable hyper-v and sandbox containers
  $RequiredWindowsOptionalFeatures = @(
    "Microsoft-Hyper-V"
    "Containers-DisposableClientVM"
  )
  $RequiredWindowsOptionalFeaturesResults = foreach ($feature in $RequiredWindowsOptionalFeatures) {Get-WindowsOptionalFeature -Online -FeatureName $feature | Where-Object {$_.State -eq "Disabled"}}

  if ($RequiredWindowsOptionalFeaturesResults) {
    foreach ($feature in $RequiredWindowsOptionalFeaturesResults) {
      Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName
      Write-Output "Enabled feature $($feature.FeatureName)"
    }
  }
}

function Set-WindowsOption {
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -value 0
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
  Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
}

function Install-WSL {
  $WSLStatus = wsl --status
  if (-Not ($WSLStatus -match "Default Version: 2")) {
    wsl --install
  }
}

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

function Copy-GitConfig {
  $GitConfigSource = "~/git-repos/personal/dotfiles/.gitconfig_windows"
  if (Test-Path -Path $GitConfigSource -PathType Leaf) {
    try {
      $null = Remove-Item ~/.gitconfig -ErrorAction SilentlyContinue
      $null = Copy-Item -Path $GitConfigSource -Destination ~/.gitconfig -ErrorAction Stop
      Write-Output "copied ~/.gitconfig"
    }
    catch {
      throw $_.Exception.Message
    }
  }
}

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
