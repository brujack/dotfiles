# powershell_module_pins.psd1 sits next to the real profile.ps1; the profile itself is
# usually a symlink in ~/.config/powershell, so follow it before looking for the file.
function Get-ModulePinFile {
  param([string]$ProfilePath)
  $item = Get-Item -LiteralPath $ProfilePath
  $real = $item.ResolveLinkTarget($true)
  $dir = if ($real) { $real.DirectoryName } else { $item.DirectoryName }
  return Join-Path $dir 'powershell_module_pins.psd1'
}

function Import-PinnedModule {
  param([string]$PinFile)
  if (-not $PinFile) { $PinFile = Get-ModulePinFile -ProfilePath $PSCommandPath }

  $ModulesToBeImported = @(
    "AWSPowerShell.NetCore",
    "Microsoft.PowerShell.UnixTabCompletion",
    "posh-awsp",
    "posh-git",
    "PSFzf",
    "Terminal-Icons"
  )

  $ModulesToBeImportedWindows = @(
    "AWSPowerShell.NetCore",
    "posh-awsp",
    "posh-git",
    "PSFzf",
    "Terminal-Icons"
  )

  if ($IsLinux -or $IsMacOS) { $wanted = $ModulesToBeImported }
  elseif ($IsWindows) { $wanted = $ModulesToBeImportedWindows }
  else { return }

  $data = Import-PowerShellDataFile -LiteralPath $PinFile
  $pins = @{}
  foreach ($group in @('Common', 'Unix')) {
    foreach ($name in $data[$group].Keys) { $pins[$name] = $data[$group][$name] }
  }

  foreach ($Mod in $wanted) {
    $version = $pins[$Mod]
    # Never import an unpinned module or fall back to whatever version is installed.
    if (-not $version) {
      Write-Warning "Module '$Mod' has no pin in $PinFile; not imported"
      continue
    }
    if (Get-Module -ListAvailable -Name $Mod | Where-Object { $_.Version -eq [version]$version }) {
      Import-Module -Name $Mod -RequiredVersion $version
    }
    else {
      Write-Warning "Module '$Mod' $version is not installed; run install_powershell_modules.ps1"
    }
  }
}

# oh-my-posh --init --shell pwsh --config ~/.config/powershell/bruce.omp.json | Invoke-Expression

# $env:POSH_GIT_ENABLED = $true

function BackOne {
  Set-Location ..
}
function BackTwo {
  Set-Location ../..
}
function ShowIcons {
  Get-ChildItem -Path . -Force
}
function ShowIdleDisconnect {
  (Get-APSFleetList -Region us-east-1) + (Get-APSFleetList -Region us-west-2) | Where-Object IdleDisconnectTimeoutInSeconds -ne 0 | Select-Object name
}
function AWSProfilePrd {
  Set-AWSCredential -ProfileName multiview-prd
}
function AWSProfileTest {
  Set-AWSCredential -ProfileName multiview-test
}

New-Alias -Name '..' -Value 'BackOne'
New-Alias -Name '...' -Value 'BackTwo'
New-Alias -Name 'll' -Value 'ShowIcons'
New-Alias -Name 'vim' -Value 'nvim'

if ($IsLinux -or $IsMacOS) {
  if (Get-Command "starship") {
    Invoke-Expression (&starship init powershell)
  }
  else {
    Write-Output "starship not installed"
  }
}
elseif ($IsWindows) {
  if (Get-Command "starship.exe") {
    Invoke-Expression (& 'C:\Program Files\starship\bin\starship.exe' init powershell)
  }
  else {
    Write-Output "starship.exe not installed"
  }
}

# for zoxide
if ($IsLinux -or $IsMacOS) {
  if (Get-Command "zoxide") {
    Invoke-Expression (& {
      $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
      (zoxide init --hook $hook powershell | Out-String)
    })
  }
  else {
    Write-Output "zoxide not installed"
  }
}
elseif ($IsWindows) {
  if (Get-Command "zoxide.exe") {
    Invoke-Expression (& {
      $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
      (zoxide init --hook $hook powershell | Out-String)
    })
  }
  else {
    Write-Output "zoxide.exe not installed"
  }
}

Import-PinnedModule

Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
# Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineOption -HistorySearchCursorMovesToEnd:$true

# replace 'Ctrl+t' and 'Ctrl+r' with your preferred bindings:
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
Set-PsFzfOption -TabExpansion
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
