BeforeAll {
  # Stub commands absent on some hosts so mocking works; nothing here touches PSGallery.
  foreach ($name in @('Install-Module', 'Set-PSRepository')) {
    if (-Not (Get-Command $name -ErrorAction SilentlyContinue)) {
      Set-Item -Path "function:global:$name" -Value { }
    }
  }
  $script:installScript = Join-Path $PSScriptRoot '..' '..' 'install_powershell_modules.ps1'
  Mock Install-Module  { }
  Mock Set-PSRepository { }
  Mock Write-Output    { }
  # Dot-sourcing must only define functions; the guard keeps Install-PinnedModule from running.
  . $script:installScript
}

Describe "dot-sourcing install_powershell_modules.ps1" {
  It "does not install anything or touch repository trust" {
    Should -Invoke Install-Module  -Times 0 -Scope Describe
    Should -Invoke Set-PSRepository -Times 0 -Scope Describe
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
}
