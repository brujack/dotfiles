function Install-Mods {
  $ModulesToBeInstalled = @(
    "AWSPowerShell.NetCore",
    "Az",
    "Az.Blueprint",
    "Microsoft.Graph",
    "Microsoft.PowerShell.UnixCompleters",
    "oh-my-posh",
    "posh-awsp",
    "posh-git",
    "PSFzf",
    "Terminal-Icons"
  )

  Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

  foreach ($Mod in $ModulesToBeInstalled) {
    if (Get-Module -ListAvailable $Mod) {
      Write-Host "Module '$Mod' is already installed"
    }
    else {
      Write-Host "Installing '$Mod'"
      Install-Module $Mod
    }
  }
}

Install-Mods
