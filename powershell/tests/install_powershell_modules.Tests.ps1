BeforeAll {
  # Stubs for commands absent on some hosts; nothing here touches PSGallery. Every command
  # that could install or change repository state is mocked BEFORE any dot-source, so a
  # broken guard in the script under test can never reach the real cmdlets.
  foreach ($name in @('Install-Module', 'Update-Module', 'Save-Module', 'Set-PSRepository', 'Install-PSResource')) {
    if (-Not (Get-Command $name -ErrorAction SilentlyContinue)) {
      Set-Item -Path "function:global:$name" -Value { param($Name, $RequiredVersion, $Repository, $Scope, [switch]$Force, [switch]$AcceptLicense) }
    }
    Mock $name { }
  }
  Mock Write-Output { }
  Mock Get-Module   { $null }
  $script:installScript = Join-Path $PSScriptRoot '..' '..' 'install_powershell_modules.ps1'
  # Dot-sourcing must only define functions; the guard keeps Install-PinnedModule from running.
  . $script:installScript
}

Describe "dot-sourcing install_powershell_modules.ps1" {
  It "does not install anything or touch repository trust" {
    # Mock, dot-source and assert all in this scope so the calls the file makes are counted.
    Mock Install-Module   { }
    Mock Set-PSRepository { }
    Mock Update-Module    { }
    Mock Write-Output     { }
    Mock Get-Module       { $null }
    . $script:installScript
    Should -Invoke Install-Module   -Times 0 -Exactly
    Should -Invoke Set-PSRepository -Times 0 -Exactly
    Should -Invoke Update-Module    -Times 0 -Exactly
  }
}

Describe "Get-ModulePin" {
  It "pins every module to a version" {
    foreach ($v in (Get-ModulePin -Unix:$true).Values) {
      { [version]$v } | Should -Not -Throw
    }
  }
  It "includes UnixTabCompletion only on the Unix list" {
    (Get-ModulePin -Unix:$true).Keys  | Should -Contain 'Microsoft.PowerShell.UnixTabCompletion'
    (Get-ModulePin -Unix:$false).Keys | Should -Not -Contain 'Microsoft.PowerShell.UnixTabCompletion'
  }
  It "no longer lists the renamed UnixCompleters module" {
    (Get-ModulePin -Unix:$true).Keys | Should -Not -Contain 'Microsoft.PowerShell.UnixCompleters'
  }
}

Describe "Install-PinnedModule" {
  BeforeEach {
    Mock Install-Module   { }
    Mock Set-PSRepository { }
    Mock Write-Output     { }
    Mock Get-Module       { $null }
    # Default: a PowerShellGet that supports -AcceptLicense.
    Mock Get-Command { [PSCustomObject]@{ Parameters = @{ AcceptLicense = $true } } } -ParameterFilter { $Name -eq 'Install-Module' }
  }

  It "never changes PSGallery trust" {
    Install-PinnedModule
    Should -Invoke Set-PSRepository -Times 0
  }

  It "installs every module pinned, from PSGallery, for CurrentUser" {
    Install-PinnedModule
    $pins = Get-ModulePin -Unix:($IsLinux -or $IsMacOS)
    Should -Invoke Install-Module -Times $pins.Count -Exactly
    Should -Invoke Install-Module -Times $pins.Count -Exactly -ParameterFilter {
      $Repository -eq 'PSGallery' -and $Scope -eq 'CurrentUser' -and $Force -and
      $RequiredVersion -eq $pins[[string]$Name]
    }
  }

  It "never installs a name that is not in the pin table" {
    Install-PinnedModule
    $pins = Get-ModulePin -Unix:($IsLinux -or $IsMacOS)
    Should -Invoke Install-Module -Times 0 -ParameterFilter { -not $pins.Contains([string]$Name) }
  }

  It "skips a module whose exact pinned version is already installed" {
    Mock Get-Module {
      [PSCustomObject]@{ Name = 'posh-git'; Version = [version]'1.1.0' }
    } -ParameterFilter { $Name -eq 'posh-git' }
    Install-PinnedModule
    Should -Invoke Install-Module -Times 0 -ParameterFilter { $Name -eq 'posh-git' }
  }

  It "installs the pin when only a different version is installed" {
    Mock Get-Module {
      [PSCustomObject]@{ Name = 'posh-git'; Version = [version]'0.7.3' }
    } -ParameterFilter { $Name -eq 'posh-git' }
    Install-PinnedModule
    Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
      $Name -eq 'posh-git' -and $RequiredVersion -eq '1.1.0'
    }
  }

  It "passes -AcceptLicense when Install-Module supports it" {
    Install-PinnedModule
    Should -Invoke Install-Module -Times 1 -ParameterFilter { $AcceptLicense }
    Should -Invoke Install-Module -Times 0 -ParameterFilter { -not $AcceptLicense }
  }

  It "omits -AcceptLicense when Install-Module lacks it (Windows PowerShell 5.1)" {
    Mock Get-Command { [PSCustomObject]@{ Parameters = @{} } } -ParameterFilter { $Name -eq 'Install-Module' }
    Install-PinnedModule
    $pins = Get-ModulePin -Unix:($IsLinux -or $IsMacOS)
    Should -Invoke Install-Module -Times $pins.Count -Exactly -ParameterFilter { -not $AcceptLicense }
  }
}
