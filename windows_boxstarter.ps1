# install boxstarter so that we can start things off
# Only need to run this once and then we are off

# After boxstarter is installed, then using a boxstarter shell you can run setup_windows.ps1

. { iwr -useb https://boxstarter.org/bootstrapper.ps1 } | iex; Get-Boxstarter -Force
