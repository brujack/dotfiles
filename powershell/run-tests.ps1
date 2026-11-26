# Restore user module paths not added when running with -NoProfile.
# Use GetFolderPath('MyDocuments') instead of $HOME/Documents so that
# OneDrive-redirected Documents folders on Windows are resolved correctly.
$sep = [IO.Path]::PathSeparator
$docs = [Environment]::GetFolderPath('MyDocuments')
@(
    (Join-Path $HOME '.local' 'share' 'powershell' 'Modules')   # pwsh, macOS/Linux
    (Join-Path $docs 'PowerShell' 'Modules')                    # pwsh, Windows
    (Join-Path $docs 'WindowsPowerShell' 'Modules')             # Windows PowerShell, Windows
) | Where-Object { $_ -and (Test-Path $_) -and ($env:PSModulePath -split $sep) -notcontains $_ } |
    ForEach-Object { $env:PSModulePath = $_ + $sep + $env:PSModulePath }

Import-Module PSScriptAnalyzer
# Fail closed: -ErrorAction Stop does not terminate Invoke-ScriptAnalyzer, so a missing
# settings file or target would print an error and still exit 0. Check every path up
# front, analyse each file in its own call (-Path takes one string) and treat any error
# the analyzer records as a failure.
$settings = './PSScriptAnalyzerSettings.psd1'
$targets = @('./setup_windows.ps1', '../install_powershell_modules.ps1', '../update_powershell_modules.ps1')
foreach ($path in @($settings) + $targets) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Error "lint input missing: $path"; exit 1 }
}
$r = @()
foreach ($file in $targets) {
    $analyzerErrors = $null
    $r += @(Invoke-ScriptAnalyzer -Path $file -Settings $settings -ErrorVariable analyzerErrors -ErrorAction SilentlyContinue)
    if ($analyzerErrors) { Write-Error "PSScriptAnalyzer failed on ${file}: $($analyzerErrors -join '; ')"; exit 1 }
}
if ($r.Count -gt 0) { $r | Format-Table -AutoSize; exit 1 }

Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = 'tests/'
$config.Run.Exit = $true
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './setup_windows.ps1'
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = './coverage.xml'
$result = Invoke-Pester -Configuration $config

if ($null -eq $result.CodeCoverage) {
    Write-Error "Pester returned no CodeCoverage result - verify Pester >= 5.0"
    exit 1
}
Write-Host ""
Write-Host "Coverage: $($result.CodeCoverage.CoveragePercent)%"

if ($result.CodeCoverage.CoveragePercent -lt 90) {
    Write-Error "Coverage $($result.CodeCoverage.CoveragePercent)% is below 90% floor"
    exit 1
}
