export EDITOR=/usr/bin/vim
export GIT_EDITOR=/usr/bin/vim

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
        . ~/.bashrc
fi

# for git awesomeness
source ~/.bash_git
PS1='[\u@\h \[\033[0;36m\]\W$(__git_ps1 "\[\033[0m\]\[\033[0;33m\] (%s)")\[\033[0m\]]\$ '

# for bash completion
if [ -f $(brew --prefix)/etc/bash_completion ]; then
	. $(brew --prefix)/etc/bash_completion
fi

export HISTTIMEFORMAT="%d/%m/%y %T "
# VMware Fusion
if [ -d "/Applications/VMware Fusion.app/Contents/Library" ]; then
    export PATH=$PATH:"/Applications/VMware Fusion.app/Contents/Library"
fi

# for brew path includes
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"

# MacPorts Installer addition
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

# PYTHONPATH for correct use for ansible
export PYTHONPATH="~/Library/Python/2.7/lib/python/site-packages:/Library/Python/2.7/site-packages"

# for keychain ssh key management
eval `~/keychain/keychain --eval --agents ssh --inherit any id_rsa`

# for go home
export GOPATH=~/git_repos/go_work
export PATH=$PATH:"~/git_repos/go_work/bin"
