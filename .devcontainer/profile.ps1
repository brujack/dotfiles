Import-Module oh-my-posh

if($env:LC_TERMINAL -eq "iTerm2") {
  $ThemeSettings.Options.ConsoleTitle = $false
}
Set-PoshPrompt -Theme agnosterplus
