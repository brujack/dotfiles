# install boxstarter so that we can start things off
# Only need to run this once and then we are off

. { iwr -useb https://boxstarter.org/bootstrapper.ps1 } | iex; Get-Boxstarter -Force
