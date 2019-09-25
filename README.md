# dotfiles for osx/linux/windows/wsl

You can setup either a macos or linux environment by running `./setup_env.sh`
It will also do an upgrade of packages et al

## Prerequisites

1. An ability to clone this repo, which means you will need git installed already.
2. On macos, the easiest way to install git is by already installing homebrew, which will install xcode command line tools to get you git.

## Running

```
./setup_env.sh -t OPTION
```

OPTION:
setup_user: just sets up a basic user environment for the current user
setup: runs a full machine and developer setup
developer: runs a developer setup with packages and python virtual environment for running ansible
ansible: just runs the ansible setup using a python virtual environment.  Typically used after a python update. To run

```
rm ~/.virtualenvs/ansible && ./setup_env.sh -t ansible
```

update: does a system update of packages including brew packages

After changing to zsh, you will need to do another './setup_env.sh -t setup' if that is what you wanted, since by changing shells, you will lose the original shell process and need to start over again.

## For Windows/wsl setup

1. Windows 10 Pro current so that you can run containers and wsl
2. Boxstarter installed from [boxstarter](https://boxstarter.org/) using the command in windows_boxstarter.ps1 in this repo
3. An ability to clone this repo, which means you will need git installed and I recommend Sourcetree from [sourcetreeapp](https://www.sourcetreeap.com/)
4. Run setup_windows.ps1 to install windows programs/services
5. Install a linux distribution from the Windows App store, I recommend Ubuntu 18.04 as this is where things were tested and I use
6. Run `./setup_env.sh -t OPTION` to setup a linux development environment inside of wsl
