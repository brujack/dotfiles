# dotfiles for osx/linux/windows

You can setup either a macos or linux environment by running `./setup_env.sh`
It will also do an upgrade of packages et al

# Prerequisites:
1. An ability to clone this repo, which means you will need git installed already.
2. On macos, the easiest way to install git is by already installing homebrew, which will install xcode command line tools to get you git.

# Running:
'./setup_env.sh -t OPTION'

OPTION:
setup_user: just sets up a basic user environment for the current user
setup: runs a full machine and developer setup
developer: runs a developer setup with packages and python virtual environment for running ansible
ansible: just runs the ansible setup using a python virtual environment.  Typically used after a python update. To run, "rm ~/.virtualenvs/ansible && ./setup_env.sh -t ansible"
update: does a system update of packages including brew packages
