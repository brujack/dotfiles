Import-Module posh-git
Import-Module oh-my-posh
Import-Module -Name Microsoft.PowerShell.UnixCompleters
Import-Module -Name Terminal-Icons
Import-Module -Name AWSPowerShell.NetCore

# if($env:LC_TERMINAL -eq "iTerm2") {
#   $ThemeSettings.Options.ConsoleTitle = $false
# }
Set-PoshPrompt -Theme agnosterplus

function BackOne {
  Set-Location ..
}
function BackTwo {
  Set-Location ../..
}
function ShowIcons {
  Get-ChildItem -Path . -Force
}
function ShowIdleDisconnect {
  (Get-APSFleetList -Region us-east-1) + (Get-APSFleetList -Region us-west-2)|where IdleDisconnectTimeoutInSeconds -ne 0 |select name
}
function AWSProfilePrd {
  Set-AWSCredential -ProfileName multiview-prd
}
function AWSProfileTest {
  Set-AWSCredential -ProfileName multiview-test
}

New-Alias -Name '..' -Value 'BackOne'
New-Alias -Name '...' -Value 'BackTwo'
New-Alias -Name 'll' -Value 'ShowIcons'

Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineOption -HistorySearchCursorMovesToEnd:$true
