# install boxstarter so that we can start things off
# Only need to run this once and then we are off

# Need to set execution policy first so that we can run my ps1 scripts
# See https:/go.microsoft.com/fwlink/?LinkID=135170
#

# After boxstarter is installed, then using a boxstarter shell you can run setup_windows.ps1

. { iwr -useb https://boxstarter.org/bootstrapper.ps1 } | iex; Get-Boxstarter -Force
