# Versions live in powershell_module_pins.psd1 (shared with the updater and profile.ps1).
function Get-ModulePin {
  param([bool]$Unix)

  $data = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'powershell_module_pins.psd1')
  $pins = [ordered]@{}
  foreach ($name in ($data.Common.Keys | Sort-Object)) { $pins[$name] = $data.Common[$name] }
  if ($Unix) {
    foreach ($name in ($data.Unix.Keys | Sort-Object)) { $pins[$name] = $data.Unix[$name] }
  }
  return $pins
}

function Install-PinnedModule {
  $pins = Get-ModulePin -Unix ([bool]($IsLinux -or $IsMacOS))

  foreach ($name in $pins.Keys) {
    $version = $pins[$name]
    $installed = Get-Module -ListAvailable -Name $name |
      Where-Object { $_.Version -eq [version]$version }
    if ($installed) {
      Write-Output "Module '$name' $version is already installed"
      continue
    }
    Write-Output "Installing '$name' $version"
    # -Force only skips the untrusted-repository prompt for this one pinned install.
    # This script never changes PSGallery trust. A host that ran the version before
    # 2026-11-26 still has PSGallery Trusted until someone runs, by hand:
    #   Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted
    # -AcceptLicense accepts, on the operator's behalf, the licences of: Az and Az.Blueprint
    # (aka.ms/azps-license), Microsoft.Graph (Microsoft Developer Services Agreement,
    # aka.ms/devservicesagreement) and Microsoft.PowerShell.UnixTabCompletion (MIT).
    # Without it an unattended install of those fails. Windows PowerShell 5.1's inbox
    # PowerShellGet 1.0.0.1 has no -AcceptLicense, so it is passed only where supported.
    $installArgs = @{
      Name            = $name
      RequiredVersion = $version
      Repository      = 'PSGallery'
      Scope           = 'CurrentUser'
      Force           = $true
    }
    if ((Get-Command Install-Module).Parameters.ContainsKey('AcceptLicense')) {
      $installArgs['AcceptLicense'] = $true
    }
    Install-Module @installArgs
  }
}

# Skip when dot-sourced (tests) so loading the file never installs anything.
if ($MyInvocation.InvocationName -ne '.') {
  Install-PinnedModule
}
