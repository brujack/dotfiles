BeforeAll {
  # Every command that could install or change repository state is stubbed if absent and
  # mocked BEFORE anything else runs (these tests spawn child processes, but keep the rule).
  foreach ($name in @('Install-Module', 'Update-Module', 'Save-Module', 'Set-PSRepository', 'Install-PSResource')) {
    if (-Not (Get-Command $name -ErrorAction SilentlyContinue)) {
      Set-Item -Path "function:global:$name" -Value { param($Name, $RequiredVersion, $Repository, $Scope, [switch]$Force, [switch]$AcceptLicense) }
    }
    Mock $name { }
  }

  $script:powershellDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
  $script:pwshExe = Join-Path $PSHOME 'pwsh'

  # Run a runner script in a child pwsh whose HOME and PSModulePath point at empty fixtures,
  # so PSScriptAnalyzer and Pester cannot load. Bounded by a timeout; a child that overruns
  # it is killed by PID (only the one started here).
  function global:Invoke-RunnerWithoutModules {
    param([string]$Runner, [string]$FixtureRoot, [int]$TimeoutSeconds = 90, [switch]$StubAnalyzer)
    $emptyHome = Join-Path $FixtureRoot 'home'
    $emptyModules = Join-Path $FixtureRoot 'modules'
    $null = New-Item -ItemType Directory -Path $emptyHome, $emptyModules -Force
    if ($StubAnalyzer) {
      # A PSScriptAnalyzer that loads and finds nothing, so the runner reaches the Pester check.
      $stubDir = Join-Path $emptyModules 'PSScriptAnalyzer'
      $null = New-Item -ItemType Directory -Path $stubDir -Force
      Set-Content -LiteralPath (Join-Path $stubDir 'PSScriptAnalyzer.psm1') -Value 'function Invoke-ScriptAnalyzer { [CmdletBinding()] param([string]$Path, [string]$Settings) }'
      Set-Content -LiteralPath (Join-Path $stubDir 'PSScriptAnalyzer.psd1') -Value "@{ RootModule = 'PSScriptAnalyzer.psm1'; ModuleVersion = '1.0.0'; GUID = '11111111-2222-3333-4444-555555555555'; FunctionsToExport = @('Invoke-ScriptAnalyzer') }"
    }
    $psi = [System.Diagnostics.ProcessStartInfo]::new($script:pwshExe)
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', (Join-Path $script:powershellDir $Runner))) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $script:powershellDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.Environment['HOME'] = $emptyHome
    $psi.Environment['PSModulePath'] = $emptyModules
    # pwsh on Linux and macOS adds $XDG_DATA_HOME/powershell/Modules to the module path
    # whenever XDG_DATA_HOME is set, so an inherited value would let the child find the
    # real modules; point every XDG root at the empty home too.
    foreach ($xdg in @('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
      $psi.Environment[$xdg] = Join-Path $emptyHome $xdg
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $proc.Kill($true); $proc.WaitForExit() }
    [PSCustomObject]@{ ExitCode = $proc.ExitCode; TimedOut = $timedOut; Output = ($stdout.Result + $stderr.Result) }
  }
}

AfterAll {
  Remove-Item function:global:Invoke-RunnerWithoutModules -ErrorAction SilentlyContinue
}

# On Windows the user module path comes from Documents, not HOME, so the fixture cannot
# hide the installed modules there; CI runs this suite on Linux.
Describe "runner scripts fail closed when a tool module cannot load" -Skip:$IsWindows {
  It "<runner> exits non-zero, names the remedy and does nothing further" -ForEach @(
    @{ runner = 'run-lint.ps1' }
    @{ runner = 'run-tests.ps1' }
  ) {
    $r = Invoke-RunnerWithoutModules -Runner $runner -FixtureRoot (Join-Path $TestDrive $runner)
    $r.TimedOut | Should -BeFalse
    $r.ExitCode | Should -Not -Be 0
    $r.Output | Should -Match 'cannot be loaded\. Install it'
    # Nothing past the module check may run: no analyzer call, no Pester start.
    $r.Output | Should -Not -Match 'not recognized|Pester returned no CodeCoverage|Describing'
  }

  It "run-tests.ps1 reaches and fails closed on the Pester check when only the analyzer loads" {
    $r = Invoke-RunnerWithoutModules -Runner 'run-tests.ps1' -FixtureRoot (Join-Path $TestDrive 'pester-branch') -StubAnalyzer
    $r.TimedOut | Should -BeFalse
    $r.ExitCode | Should -Not -Be 0
    $r.Output | Should -Match 'Pester >= 5\.0 cannot be loaded\. Install it'
    $r.Output | Should -Not -Match 'PSScriptAnalyzer cannot be loaded|not recognized|Pester returned no CodeCoverage|Describing'
  }
}
