# choose which env we are running on
[ $(uname -s) = "Darwin" ] && export MACOS=1
[ $(uname -s) = "Linux" ] && export LINUX=1
if [ -f /etc/lsb-release ];
then
  export UBUNTU=1
fi
if [ -f /etc/redhat-release ];
then
  export REDHAT=1
fi
[[ $(uname -r) =~ Microsoft$ ]] && export WINDOWS=1

[ $(hostname -s) = "ratna" ] && export RATNA=1
[ $(hostname -s) = "bjackson" ] && export BJACKSON=1

# setup some variables for virtualenv
export WORKON_HOME=${HOME}/.virtualenvs
export PROJECT_HOME=${HOME}./virtualenvs
if [[ ${MACOS} ]]
then
  VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
  if [[ ${RATNA} ]]
  then
    VIRTUALENVWRAPPER_PYTHON=/usr/bin/python
  fi
  if [[ ${BJACKSON} ]]
  then
    VIRTUALENVWRAPPER_PYTHON=/usr/local/bin/python3
  fi
fi
if [[ ${LINUX} ]]
then
  VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
fi

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

# rancherssh will do fuzzy find for your query between %%
# rssh container-keyword
rssh () {
  cd ${HOME}/.rancherssh
  rancherssh %"$1"%
  cd -
}

# Path to your oh-my-zsh installation.
export ZSH=${HOME}/.oh-my-zsh

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-zsh is loaded.
# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
#ZSH_THEME="robbyrussell"
ZSH_THEME="bruce"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
export UPDATE_ZSH_DAYS=3

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# HISTORY customizations:
export HISTCONTROL=ignoredups;
export HISTIGNORE="ls:cd:cd -:pwd:exit:date:* --help";

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
if [[ ${MACOS} ]]
then
  plugins=(aws brew docker git helm kubectl osx terraform vscode)
fi
if [[ ${UBUNTU} ]]
then
  plugins=(aws git docker kubectl ubuntu)
fi
if [[ ${REDHAT} ]]
then
  plugins=(aws git docker kubectl fedora)
fi

source $ZSH/oh-my-zsh.sh

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION || ${LINUX} ]]; then
  export EDITOR='vim'
  export GIT_EDITOR='vim'
else
  export EDITOR='code'
  export GIT_EDITOR='code'
fi

# for keychain ssh key management
if [[ ${MACOS} ]]
then
  eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_rsa`
elif [[ ${LINUX} ]]
then
  eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
fi

# adding in home go path
if [[ -d /Users/bjackson ]]
then
  path+='/Users/bjackson/bin'
fi
if [[ -d /Users/bruce ]]
then
  path+='/Users/bruce/bin'
fi

# for /usr/local includes
path+='/usr/local/bin'
path+='/usr/local/sbin'

# for /opt/local includes
path+='/opt/local/bin'
path+='/opt/local/sbin'

# adding in home go path
if [[ -d /Users/bjackson ]]
then
  path+='/Users/bjackson/go/bin'
fi
if [[ -d /Users/bruce ]]
then
  path+='/Users/bruce/go/bin'
fi

if [[ ${LINUX} ]]
then
  path+='/home/bruce/go/bin'
  path+='/usr/lib/go-1.10/bin'
fi

#export the PATH
export PATH

# export ANSIBLEUSER so that we run as the correct user
export ANSIBLEUSER="ubuntu"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
alias home='ssh bruce@conecrazy.ca'
alias mac='ssh bruce@mac'
alias server='ssh bruce@server'
alias ratna='ssh bruce@ratna'
alias kube-0='ssh bruce@kube-0'
alias kube-1='ssh bruce@kube-1'
alias kube-2='ssh bruce@kube-2'
alias us-24='ssh bruce@us-24'
alias us-16='ssh bruce@us-16'
alias us-8-1='ssh bruce@us-8-1'
alias us-pro='ssh bruce@us-pro'
alias nano-hd='ssh bruce@nano-hd'
# aliases for work servers
alias work='ssh bjackson@172.16.1.124'
alias vader='ssh bjackson@vader.leo.obj'
alias yoda='ssh bjackson@yoda.leo.obj'
alias kube-00='ssh bjackson@kube-0.leo.obj'
alias kube-10='ssh bjackson@kube-1.leo.obj'
alias kube-20='ssh bjackson@kube-2.leo.obj'
alias ns0='ssh bjackson@ns0.lab.leo.obj'
alias ns1='ssh bjackson@ns1.lab.leo.obj'
alias deploy-1='ssh bjackson@deploy-1.leo.obj'
alias deploy-2='ssh bjackson@deploy-2.leo.obj'

# command aliasesssh
alias au='sudo apt-get update'
alias ag='sudo apt-get dist-upgrade -y'
alias aa='sudo apt-get autoremove -y'
alias dot='cd ~/git-repos/personal/dotfiles && git pl && source ~/.zshrc'
alias oh='cd ~/.oh-my-zsh && git pl'

if quiet_which exa
# alias for ls to exa removed due to breaking globbing for ansible aws integration
then
  alias gs="exa -lg --git"
  alias ls="ls -l"
else
  alias ls="ls -l"
fi

# for chruby setup
if [[ ${MACOS} ]]
then
  source /usr/local/opt/chruby/share/chruby/chruby.sh
  source /usr/local/opt/chruby/share/chruby/auto.sh
  chruby ruby-2.3.5
fi

# zsh options
# Share history between instances
setopt share_history

# Remove unnecessary blanks from history
setopt hist_reduce_blanks

# add in aws creds for terraform and ansible
export AWS_HOME=${HOME}/.aws

if [[ -f ${AWS_HOME}/.aws_creds ]]
then
  source ${AWS_HOME}/.aws_creds
fi

# add in google cloud creds for terraform
if [[ -f ${HOME}/.google_creds ]]
then
  source ${HOME}/.google_creds
fi

# setup for python 3.7 for ansible by using virtualenv
#source /usr/local/bin/virtualenvwrapper.sh
if [[ -d ~/.virtualenvs ]]
then
  if [[ ${MACOS} ]]
  then
    source /usr/local/bin/virtualenvwrapper.sh
  fi
  if [[ ${LINUX} ]]
  then
    source /usr/local/bin/virtualenvwrapper.sh
  fi
  workon ansible
  if [[ -f ${HOME}/.vault_pass.txt ]]
  then
    export ANSIBLE_VAULT_PASSWORD_FILE=${HOME}/.vault_pass.txt
  fi
fi

# setup kubectl autocompletion to save typing
if [[ -f /usr/local/bin/kubectl ]]
then
  source <(kubectl completion zsh)
fi

# setup gpg
export GPG_TTY=$(tty)

# for brew zsh-completions
if [[ ${MACOS} ]]
then
  fpath=(/usr/local/share/zsh-completions $fpath)
fi

# for kubeconfig setup
if [[ -f ${HOME}/.kube/config ]]
then
  export KUBECONFIG=${HOME}/.kube/config
fi
if [[ -f ${HOME}/.kube/kube-0-leo-obj/config ]]
then
  export KUBECONFIG=${KUBECONFIG}:${HOME}/.kube/kube-0-leo-obj/config
fi
if [[ -f ${HOME}/.kube/local/config ]]
then
  export KUBECONFIG=${KUBECONFIG}:${HOME}/.kube/local/config
fi
if [[ -f ${HOME}/.kube/rancher-conecrazy/config ]]
then
  export KUBECONFIG=${KUBECONFIG}:${HOME}/.kube/rancher-conecrazy/config
fi

# for aws info at the cli
# add a "--region xxx" to change regions
alias idesc="aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Placement.AvailabilityZone, State.Name, InstanceId,InstanceType,Tags]' --output text"

# show .oh_my_zsh plugins and their shortcuts
function options() {
    PLUGIN_PATH="$HOME/.oh-my-zsh/plugins/"
    for plugin in $plugins; do
        echo "\n\nPlugin: $plugin"; grep -r "^function \w*" $PLUGIN_PATH$plugin | awk '{print $2}' | sed 's/()//'| tr '\n' ', '; grep -r "^alias" $PLUGIN_PATH$plugin | awk '{print $2}' | sed 's/=.*//' |  tr '\n' ', '
    done
}

if [[ ${WINDOWS} ]]
then
  export DOCKER_HOST=tcp://0.0.0.0:2375
fi
