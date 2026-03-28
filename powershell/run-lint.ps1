# Restore user module paths not added when running with -NoProfile
$sep = [IO.Path]::PathSeparator
@(
    (Join-Path $HOME 'Documents' 'PowerShell' 'Modules')        # pwsh, Windows
    (Join-Path $HOME 'Documents' 'WindowsPowerShell' 'Modules') # Windows PowerShell, Windows
    (Join-Path $HOME '.local' 'share' 'powershell' 'Modules')   # pwsh, macOS/Linux
) | Where-Object { (Test-Path $_) -and ($env:PSModulePath -split $sep) -notcontains $_ } |
    ForEach-Object { $env:PSModulePath = $_ + $sep + $env:PSModulePath }

Import-Module PSScriptAnalyzer
$r = Invoke-ScriptAnalyzer -Path ./setup_windows.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
if ($r) { $r | Format-Table -AutoSize; exit 1 }
