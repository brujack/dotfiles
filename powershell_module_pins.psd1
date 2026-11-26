# Single source of truth for PowerShell module versions. Read by
# install_powershell_modules.ps1, update_powershell_modules.ps1 and profile.ps1.
#
# Versions are the newest at least 14 days old as of 2026-11-26 (ADR-0057 cooldown), via
# Find-Module. Bump by hand after reading the release. Check any new pin's PSGallery
# owner and ProjectUri before adding it.
#
# These are the top-level modules only. Dependencies are NOT pinned: Az 16.5.0 and
# Az.Blueprint 0.5.1 require Az.Accounts by open range ([5.5.4, ) and [5.5.2, )), and
# PowerShellGet v2 resolves the newest (5.5.5 today). Exact pinning of dependencies needs
# PSResourceGet with -SkipDependencyCheck (see the docs/superpowers Backlog).
@{
  Common = @{
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
  # Linux and macOS only.
  Unix = @{
    # Successor of Microsoft.PowerShell.UnixCompleters, which is no longer on PSGallery.
    # Provenance verified 2026-11-26 via Find-Module: owners JamesTruher-MSFT and
    # stevel-msft (Microsoft PowerShell team), Author Microsoft, ProjectUri
    # https://github.com/PowerShell/UnixCompleters (same repo as the old module, now
    # archived), 0.5.0 published 2022-04-20.
    'Microsoft.PowerShell.UnixTabCompletion' = '0.5.0'
  }
}
