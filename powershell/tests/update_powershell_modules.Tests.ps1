BeforeAll {
  # Every command that could install or change repository state is stubbed if absent and
  # mocked BEFORE any dot-source or script run.
  foreach ($name in @('Install-Module', 'Update-Module', 'Save-Module', 'Set-PSRepository', 'Install-PSResource')) {
    if (-Not (Get-Command $name -ErrorAction SilentlyContinue)) {
      Set-Item -Path "function:global:$name" -Value { param($Name, $RequiredVersion, $Repository, $Scope, [switch]$Force, [switch]$AcceptLicense) }
    }
    Mock $name { }
  }
  Mock Write-Output { }
  Mock Get-Module   { $null }
  # Only to get Get-ModulePin; the guard stops it installing anything.
  . (Join-Path $PSScriptRoot '..' '..' 'install_powershell_modules.ps1')
  $script:updateScript = Join-Path $PSScriptRoot '..' '..' 'update_powershell_modules.ps1'
}

Describe "update_powershell_modules.ps1" {
  BeforeEach {
    Mock Install-Module   { }
    Mock Update-Module    { }
    Mock Set-PSRepository { }
    Mock Write-Output     { }
    Mock Get-Module       { $null }
  }

  It "never calls Update-Module, which would move modules past the pins" {
    & $script:updateScript
    Should -Invoke Update-Module -Times 0
  }

  It "enforces the pins by installing each pinned module" {
    & $script:updateScript
    $pins = Get-ModulePin -Unix:($IsLinux -or $IsMacOS)
    Should -Invoke Install-Module -Times $pins.Count -Exactly -ParameterFilter {
      $RequiredVersion -eq $pins[[string]$Name]
    }
  }

  It "does nothing when every pinned version is already installed" {
    Mock Get-Module {
      $pins = Get-ModulePin -Unix:($IsLinux -or $IsMacOS)
      [PSCustomObject]@{ Name = $Name; Version = [version]$pins[[string]$Name] }
    }
    & $script:updateScript
    Should -Invoke Install-Module -Times 0
  }

  It "never changes PSGallery trust" {
    & $script:updateScript
    Should -Invoke Set-PSRepository -Times 0
  }
}
