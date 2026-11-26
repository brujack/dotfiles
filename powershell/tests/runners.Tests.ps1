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
    param([string]$Runner, [string]$FixtureRoot, [int]$TimeoutSeconds = 90)
    $emptyHome = Join-Path $FixtureRoot 'home'
    $emptyModules = Join-Path $FixtureRoot 'modules'
    $null = New-Item -ItemType Directory -Path $emptyHome, $emptyModules -Force
    $psi = [System.Diagnostics.ProcessStartInfo]::new($script:pwshExe)
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', (Join-Path $script:powershellDir $Runner))) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $script:powershellDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.Environment['HOME'] = $emptyHome
    $psi.Environment['PSModulePath'] = $emptyModules
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

Describe "runner scripts fail closed when a tool module cannot load" {
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
}
