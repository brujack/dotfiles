# Versions are the newest at least 14 days old as of 2026-11-26 (ADR-0057 cooldown), via
# Find-Module. Bump by hand after reading the release.
function Get-ModulePin {
  param([bool]$Unix)

  $pins = [ordered]@{
    'AWSPowerShell.NetCore' = '5.0.333'
    'Az'                    = '16.5.0'
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
    # Provenance verified 2026-11-26 via Find-Module: owners JamesTruher-MSFT and
    # stevel-msft (Microsoft PowerShell team), Author Microsoft, ProjectUri
    # https://github.com/PowerShell/UnixCompleters (same repo as the old module, now
    # archived), 0.5.0 published 2022-04-20.
    # Check any new pin the same way (owner + ProjectUri) before adding it.
    $pins['Microsoft.PowerShell.UnixTabCompletion'] = '0.5.0'
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
    # -AcceptLicense: UnixTabCompletion sets RequireLicenseAcceptance (MIT, read 2026-11-26);
    # without it an unattended install fails.
    Install-Module -Name $name -RequiredVersion $version -Repository PSGallery -Scope CurrentUser -Force -AcceptLicense
  }
}

# Skip when dot-sourced (tests) so loading the file never installs anything.
if ($MyInvocation.InvocationName -ne '.') {
  Install-PinnedModule
}
