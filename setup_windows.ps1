# First you would need to have run windows_boxstarter.ps1 to install boxstarter
# Second you can run this script using a boxstarter shell


# set windows options
Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar

# enable hyper-v and containers
Enable-WindowsOptionalFeature -Online -FeatureName:Microsoft-Hyper-V -All
Enable-WindowsOptionalFeature -Online -FeatureName:Containers-DisposableClientVM -All

# enable wsl
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux

# enable current user to be able to execute powershell scripts
Set-ExecutionPolicy Unrestricted -Scope CurrentUser


# function Install-NeededFor {
#   param(
#      [string] $packageName = ''
#     ,[bool] $defaultAnswer = $true
#   )
#     if ($packageName -eq '') {return $false}

#     $yes = '6'
#     $no = '7'
#     $msgBoxTimeout='-1'
#     $defaultAnswerDisplay = 'Yes'
#     $buttonType = 0x4;
#     if (!$defaultAnswer) { $defaultAnswerDisplay = 'No'; $buttonType= 0x104;}

#     $answer = $msgBoxTimeout
#     try {
#       $timeout = 10
#       $question = "Do you need to install $($packageName)? Defaults to `'$defaultAnswerDisplay`' after $timeout seconds"
#       $msgBox = New-Object -ComObject WScript.Shell
#       $answer = $msgBox.Popup($question, $timeout, "Install $packageName", $buttonType)
#     }
#     catch {
#     }

#     if ($answer -eq $yes -or ($answer -eq $msgBoxTimeout -and $defaultAnswer -eq $true)) {
#       write-host "Installing $packageName"
#       return $true
#     }

#     write-host "Not installing $packageName"
#     return $false
#   }

# #test for chocotlatey and install if not there
# # Install Chocolatey
# if (Install-NeededFor 'chocolatey') {
#   iex ((new-object net.webclient).DownloadString('http://chocolatey.org/install.ps1'))
# }



# install packages with chocolatey
cinst -y 1password
cinst -y ag
cinst -y atom
cinst -y awscli
cinst -y azure-cli
cinst -y beyond-compare
cinst -y dbeaver
cinst -y docker-desktop
cinst -y dropbox
cinst -y evernote
cinst -y firefox
cinst -y gcloudsdk
cinst -y gh
cinst -y git
cinst -y googlechrome
cinst -y hyper
cinst -y kubernetes-cli
cinst -y kubernetes-helm
cinst -y microsoft-windows-terminal
cinst -y postman
cinst -y putty.install
cinst -y puttygen
cinst -y python3
cinst -y sourcetree
cinst -y spotify
cinst -y teamviewer
cinst -y terraform
cinst -y typora
cinst -y vscode
cinst -y winscp
cinst -y 7zip
