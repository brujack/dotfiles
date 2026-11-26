# Versions looked up 2026-11-26 via Find-Module. Bump by hand after reading the release.
function Get-ModulePins {
  param([bool]$Unix)

  $pins = [ordered]@{
    'AWSPowerShell.NetCore' = '5.0.345'
    'Az'                    = '17.0.0'
    'Az.Blueprint'          = '0.5.1'
    'Microsoft.Graph'       = '2.41.2'
    'oh-my-posh'            = '7.85.2'
    'posh-awsp'             = '0.9.1'
    'posh-git'              = '1.1.0'
    'PSFzf'                 = '2.7.12'
    'Terminal-Icons'        = '0.11.0'
  }
  if ($Unix) {
    # Successor of Microsoft.PowerShell.UnixCompleters, which is no longer on PSGallery.
    $pins['Microsoft.PowerShell.UnixTabCompletion'] = '0.5.0'
  }
  return $pins
}

function Install-Mods {
  $pins = Get-ModulePins -Unix ([bool]($IsLinux -or $IsMacOS))

  foreach ($name in $pins.Keys) {
    $version = $pins[$name]
    $installed = Get-Module -ListAvailable -Name $name |
      Where-Object { $_.Version -eq [version]$version }
    if ($installed) {
      Write-Output "Module '$name' $version is already installed"
      continue
    }
    Write-Output "Installing '$name' $version"
    # -Force only skips the untrusted-repository prompt for this one pinned install;
    # it does not persist trust, so PSGallery stays Untrusted machine-wide.
    Install-Module -Name $name -RequiredVersion $version -Repository PSGallery -Scope CurrentUser -Force
  }
}

# Skip when dot-sourced (tests) so loading the file never installs anything.
if ($MyInvocation.InvocationName -ne '.') {
  Install-Mods
}
