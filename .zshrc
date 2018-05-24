# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# choose which env we are running on
[ $(uname -s) = "Darwin" ] && export MACOS=1
[ $(uname -s) = "Linux" ] && export LINUX=1

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

# rancherssh will do fuzzy find for your query between %%
# rssh container-keyword
rssh () {
  cd ~/.rancherssh
  rancherssh %"$1"%
  cd -
}

# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

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

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git osx brew terraform)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION || ${LINUX} ]]; then
  export EDITOR='vim'
  export GIT_EDITOR='vim'
else
  export EDITOR='code'
  export GIT_EDITOR='code'
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# for keychain ssh key management
if [[ ${MACOS} ]]
then
  eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_rsa`
elif [[ ${LINUX} ]]
then
  eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
fi
# ssh
# export SSH_KEY_PATH="~/.ssh/rsa_id"

# for /usr/local includes
path+='/usr/local/bin'
path+='/usr/local/sbin'
#export PATH="/usr/local/bin:/usr/local/sbin:$PATH"

# for /opt/local includes
path+='/opt/local/bin'
path+='/opt/local/sbin'
#export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

# adding in local go path
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
  path+='/usr/lib/go-1.10/bin'
fi

#export the PATH
export PATH

# PYTHONPATH for correct use for ansible
# not needed as of Mar 28, 2018
# export PYTHONPATH="~/Library/Python/2.7/lib/python/site-packages:/Library/Python/2.7/site-packages"
# export PYTHONPATH="/usr/local/lib/python3.6/site-packages"

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
alias docker-0='ssh bruce@docker-0'
alias docker-1='ssh bruce@docker-1'
# aliases for fullscript servers
alias work='ssh bjackson@10.200.0.92'
alias mini-01='ssh fullscript@mini-01.ott.full.rx'
alias mini-02='ssh fullscript@mini-02.ott.full.rx'
alias router-01='ssh bjackson@router-01.ott.full.rx'
alias ca1='ssh ubuntu@ca1.ca-prd.full.rx'
alias lithium='ssh rancher@lithium.ca-prd.full.rx'
alias willet='ssh rancher@willet.ca-prd.full.rx'
alias enron='ssh ubuntu@enron.glb.full.rx'
alias hw-natural='ssh ubuntu@hw-natural-medicines.glb.full.rx'
alias kafka-01='ssh bjackson@kafka-01.glb.full.rx'
alias kafka-02='ssh bjackson@kafka-02.glb.full.rx'
alias kafka-03='ssh bjackson@kafka-03.glb.full.rx'
alias logman='ssh ubuntu@logman.glb.full.rx'
alias rancher_glb='ssh ubuntu@rancher.glb.full.rx'
alias t2gitlab='ssh ubuntu@t2gitlab.glb.full.rx'
alias bud='ssh ubuntu@bud.us-prd.full.rx'
alias fourroses='ssh ubuntu@fourroses.us-prd.full.rx'
alias pow='ssh ubuntu@pow.us-prd.full.rx'
alias quantum='ssh ubuntu@quantum.us-prd.full.rx'
alias shred='ssh ubuntu@shred.us-prd.full.rx'
alias xero='ssh ubuntu@xero.us-prd.full.rx'
alias sauna='ssh ubuntu@sauna.us-stg.full.rx'
alias daredevil='ssh ubuntu@daredevil.us-stg.full.rx'
alias heroes='ssh ubuntu@heroes.us-stg.full.rx'

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
if [[ -f ~/.aws_creds ]]
then
  source ~/.aws_creds
fi

# setup for python 3.6.4 for ansible by using virtualenv
source /usr/local/bin/virtualenvwrapper.sh
workon ansible
if [[ -f ~/.vault_pass.txt ]]
then
  export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass.txt
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
