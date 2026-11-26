BeforeAll {
  # Every command that could install or change repository state is stubbed if absent and
  # mocked BEFORE anything else runs.
  foreach ($name in @('Install-Module', 'Update-Module', 'Save-Module', 'Set-PSRepository', 'Install-PSResource')) {
    if (-Not (Get-Command $name -ErrorAction SilentlyContinue)) {
      Set-Item -Path "function:global:$name" -Value { param($Name, $RequiredVersion, $Repository, $Scope, [switch]$Force, [switch]$AcceptLicense) }
    }
    Mock $name { }
  }

  # profile.ps1 runs starship, zoxide and PSReadLine setup at top level, so it cannot be
  # dot-sourced in a test. Extract just the two functions under test from its AST.
  $profilePath = Join-Path $PSScriptRoot '..' '..' 'profile.ps1'
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$null, [ref]$null)
  $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
      $n.Name -in @('Get-ModulePinFile', 'Import-PinnedModule') }, $true)
  $script:profileFunctionText = @($fns | ForEach-Object { $_.Extent.Text })
  foreach ($fn in $fns) { Invoke-Expression $fn.Extent.Text }

  $script:realPinFile = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'powershell_module_pins.psd1')).Path
  $global:ProfileTestPins = @{}
  $data = Import-PowerShellDataFile -LiteralPath $script:realPinFile
  foreach ($g in 'Common', 'Unix') { foreach ($k in $data[$g].Keys) { $global:ProfileTestPins[$k] = $data[$g][$k] } }
  $script:expectedCount = if ($IsLinux -or $IsMacOS) { 6 } else { 5 }
}

AfterAll {
  Remove-Variable -Name ProfileTestPins -Scope Global -ErrorAction SilentlyContinue
}

Describe "Import-PinnedModule" {
  BeforeEach {
    Mock Import-Module { }
    Mock Write-Warning { }
    # Every module is installed at exactly its pinned version.
    Mock Get-Module { [PSCustomObject]@{ Name = $Name; Version = [version]$global:ProfileTestPins[[string]$Name] } }
  }

  It "imports each module with -RequiredVersion from the shared pin table" {
    Import-PinnedModule -PinFile $script:realPinFile
    Should -Invoke Import-Module -Times $script:expectedCount -Exactly
    Should -Invoke Import-Module -Times $script:expectedCount -Exactly -ParameterFilter {
      $RequiredVersion -eq $global:ProfileTestPins[[string]$Name]
    }
    Should -Invoke Write-Warning -Times 0
  }

  It "never imports without -RequiredVersion" {
    Import-PinnedModule -PinFile $script:realPinFile
    Should -Invoke Import-Module -Times 0 -ParameterFilter { -not $RequiredVersion }
  }

  It "skips and warns with the remedy when the pinned version is not installed" {
    Mock Get-Module { $null } -ParameterFilter { $Name -eq 'posh-git' }
    Import-PinnedModule -PinFile $script:realPinFile
    Should -Invoke Import-Module -Times 0 -ParameterFilter { $Name -eq 'posh-git' }
    Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
      $Message -like "*posh-git*install_powershell_modules.ps1*"
    }
    Should -Invoke Import-Module -Times ($script:expectedCount - 1) -Exactly
  }

  It "does not fall back to a different installed version" {
    Mock Get-Module { [PSCustomObject]@{ Name = 'posh-git'; Version = [version]'0.7.3' } } -ParameterFilter { $Name -eq 'posh-git' }
    Import-PinnedModule -PinFile $script:realPinFile
    Should -Invoke Import-Module -Times 0 -ParameterFilter { $Name -eq 'posh-git' }
    Should -Invoke Write-Warning -Times 1 -Exactly
  }

  It "skips and warns for a module that has no pin" {
    $pinFile = Join-Path $TestDrive 'pins.psd1'
    Set-Content -LiteralPath $pinFile -Value "@{ Common = @{ 'posh-git' = '1.1.0' }; Unix = @{} }"
    Import-PinnedModule -PinFile $pinFile
    Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'posh-git' -and $RequiredVersion -eq '1.1.0' }
    Should -Invoke Import-Module -Times 0 -ParameterFilter { $Name -ne 'posh-git' }
    Should -Invoke Write-Warning -Times ($script:expectedCount - 1) -Exactly -ParameterFilter { $Message -like "*no pin*" }
  }
}

Describe "Get-ModulePinFile" {
  It "finds the pin file next to a regular profile.ps1" {
    $dir = Join-Path $TestDrive 'plain'
    $null = New-Item -ItemType Directory -Path $dir
    $profileFile = Join-Path $dir 'profile.ps1'
    Set-Content -LiteralPath $profileFile -Value '# profile'
    Get-ModulePinFile -ProfilePath $profileFile | Should -Be (Join-Path $dir 'powershell_module_pins.psd1')
  }

  It "follows a symlinked profile.ps1 to the repo directory" -Skip:($IsWindows) {
    $repo = Join-Path $TestDrive 'repo'
    $cfg  = Join-Path $TestDrive 'config'
    $null = New-Item -ItemType Directory -Path $repo, $cfg
    Set-Content -LiteralPath (Join-Path $repo 'profile.ps1') -Value '# profile'
    $link = Join-Path $cfg 'profile.ps1'
    $null = New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $repo 'profile.ps1')
    Get-ModulePinFile -ProfilePath $link | Should -Be (Join-Path $repo 'powershell_module_pins.psd1')
  }
}

Describe "profile reached through a symlink" {
  It "finds the pin file by default (no -PinFile) via the profile's own path" -Skip:($IsWindows) {
    Mock Import-Module { }
    Mock Write-Warning { }
    Mock Get-Module { [PSCustomObject]@{ Name = $Name; Version = [version]$global:ProfileTestPins[[string]$Name] } }

    $repo = Join-Path $TestDrive 'linkrepo'
    $cfg  = Join-Path $TestDrive 'linkcfg'
    $null = New-Item -ItemType Directory -Path $repo, $cfg
    Copy-Item -LiteralPath $script:realPinFile -Destination (Join-Path $repo 'powershell_module_pins.psd1')
    # A profile made of the real functions plus the call, so $PSCommandPath is this file's path.
    $fnText = ($script:profileFunctionText -join [Environment]::NewLine)
    Set-Content -LiteralPath (Join-Path $repo 'profile.ps1') -Value ($fnText + [Environment]::NewLine + 'Import-PinnedModule')
    $link = Join-Path $cfg 'profile.ps1'
    $null = New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $repo 'profile.ps1')

    . $link

    Should -Invoke Import-Module -Times $script:expectedCount -Exactly -ParameterFilter {
      $RequiredVersion -eq $global:ProfileTestPins[[string]$Name]
    }
    Should -Invoke Write-Warning -Times 0
  }
}
