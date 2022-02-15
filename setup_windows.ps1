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
      "dbeaver",
      "docker-desktop",
      "docker-compose",
      "dropbox",
      "evernote",
      "firefox",
      "fzf",
      "gcloudsdk",
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
      "vscode",
      "winscp",
      "zoom",
      "7zip"
    )

    foreach ($package in $ChocoPackagesToBeInstalled) {
      choco install $package -y
    }
  }

  # set windows options
  # enable RDP
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
  # turn off firewall
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

  Install-ChocolateyPackages

  Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar

  # enable hyper-v and sandbox containers
  Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -All
  Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All

  # enable wsl
  $WSLEnabled = wsl --status
  if (-Not ($WSLEnabled -contains "Default Version: 2")) {
    wsl --install
  }

  # enable current user to be able to execute powershell scripts
  Set-ExecutionPolicy Unrestricted -Scope CurrentUser

  if (-not(Test-Path -Path ~/.config -PathType Container)) {
    try {
      $null = New-Item -ItemType File -Path ~/.config -Force -ErrorAction Stop
      Write-Host "The directory [~/.config] has been created."
    }
    catch {
        throw $_.Exception.Message
    }
  }

  if (-not(Test-Path -Path ~/git-repos/personal -PathType Container)) {
    try {
      $null = New-Item -ItemType File -Path ~/git-repos/personal -Force -ErrorAction Stop
      Write-Host "The directory [~/git-repos/personal] has been created."
    }
    catch {
        throw $_.Exception.Message
    }
  }

  if (Test-Path -Path ~/git-repos/personal/.gitconfig -PathType Leaf) {
    try {
      $null = Remove-Item ~/git-repos/personal/.gitconfig -ErrorAction SilentlyContinue
    }
    catch {
      throw $_.Exception.Message
    }
  }

  if (-not(Get-ItemProperty ~/git-repos/personal/.gitconfig).LinkType){"symboliclink"} {
    try {
      $null = New-Item -ItemType SymbolicLink -Path ~/git-repos/personal/.gitconfig -Target ~/git-repos/personal/.gitconfig_windows -ErrorAction SilentlyContinue
    }
    catch {
      throw $_.Exception.Message
    }
  }

}
