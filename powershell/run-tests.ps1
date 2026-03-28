Import-Module PSScriptAnalyzer
$r = Invoke-ScriptAnalyzer -Path ./setup_windows.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
if ($r) { $r | Format-Table -AutoSize; exit 1 }

Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = 'tests/'
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit = $true
Invoke-Pester -Configuration $config
