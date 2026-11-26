# Enforce the pinned module versions instead of a bare Update-Module, which would move
# every module past the pins in install_powershell_modules.ps1.
. (Join-Path $PSScriptRoot 'install_powershell_modules.ps1')
Install-PinnedModule
