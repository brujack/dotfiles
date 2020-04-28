# choose which env we are running on
[ "$(uname -s)" = "Darwin" ] && export MACOS=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1

GO_VER="1.13"
RUBY_VER="2.7.1"
GITREPOS="${HOME}/git-repos"

if [[ ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && export UBUNTU=1
  [[ ${LINUX_TYPE} = "CentOS Linux" ]] && export CENTOS=1
  [[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && export REDHAT=1
  [[ ${LINUX_TYPE} = "Fedora" ]] && export FEDORA=1
fi

[[ $(uname -r) =~ Microsoft$ ]] && export WINDOWS=1

[[ $(hostname -s) = "ratna" ]] && export RATNA=1
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "bruce-work" ]] && export BRUCEWORK=1

# setup some variables for virtualenv
export WORKON_HOME=${HOME}/.virtualenvs
export PROJECT_HOME=${HOME}./virtualenvs
if [[ ${MACOS} ]]; then
  VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
  if [[ ${RATNA} || ${LAPTOP} || ${BRUCEWORK} ]]; then
    VIRTUALENVWRAPPER_PYTHON=/usr/local/bin/python3
    CHRUBY_LOC="/usr/local/opt/chruby/share"
  fi
fi
if [[ ${LINUX} ]]; then
  if [[ -f ${HOME}/.local/bin/virtualenvwrapper.sh ]]; then
    VIRTUALENVWRAPPER_SCRIPT="${HOME}/.local/bin/virtualenvwrapper.sh"
  elif [[ -f "/usr/local/bin/virtualenvwrapper.sh" ]]; then
    VIRTUALENVWRAPPER_SCRIPT="/usr/local/bin/virtualenvwrapper.sh"
  fi
  VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3
  CHRUBY_LOC="/usr/local/share"
fi

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

# rancherssh will do fuzzy find for your query between %%
# rssh container-keyword
rssh () {
  cd ${HOME}/.rancherssh || return
  rancherssh %"$1"%
  cd ${HOME} || return
}

# Path to your oh-my-zsh installation.
export ZSH=${HOME}/.oh-my-zsh

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-zsh is loaded.
# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
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
if [[ ${MACOS} ]]; then
  plugins=(ansible python aws brew docker git git-prompt helm kubectl osx terraform vscode history-substring-search)
fi
if [[ ${WINDOWS} ]]; then
  plugins=(ansible python aws docker git git-prompt helm kubectl terraform vscode history-substring-search)
fi
if [[ ${UBUNTU} ]]; then
  plugins=(aws git git-prompt docker helm kubectl ubuntu terraform vscode history-substring-search)
fi
if [[ ${FEDORA} ]]; then
  plugins=(aws git git-prompt docker helm kubectl fedora terraform vscode history-substring-search)
fi
if [[ ${CENTOS} ]]; then
  plugins=(aws git git-prompt docker helm kubectl fedora terraform vscode history-substring-search)
fi
if [[ ${REDHAT} ]]; then
  plugins=(aws git git-prompt docker helm kubectl fedora terraform vscode history-substring-search)
fi

source $ZSH/oh-my-zsh.sh

bindkey "^[[A" history-substring-search-up
bindkey "^[[B" history-substring-search-down

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION || ${LINUX} ]]; then
  export EDITOR='vim'
  export GIT_EDITOR='vim'
else
  export EDITOR='code'
  export GIT_EDITOR='code'
fi

# for keychain ssh key management
if [[ ${MACOS} ]]; then
  eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_rsa`
elif [[ ${LINUX} ]]; then
  eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
fi

if [[ ! ${WINDOWS} ]]; then
  # adding in home bin/scripts path
  path+="${HOME}/bin"
  path+="${HOME}/scripts"

  # for /usr/local includes
  path+='/usr/local/bin'
  path+='/usr/local/sbin'

  # for /opt/local includes
  path+='/opt/local/bin'
  path+='/opt/local/sbin'

  if [[ ${REDHAT} ]]; then
    path+='/usr/sbin'
    path+='/usr/local/go/bin'
  fi
  export PATH
fi

# on wsl (windows subsystem for linux) we want to specifically define a path so that do not inherit a path from windows
if [[ ${WINDOWS} ]]; then
  path=(
    ${HOME}/.local/bin/
    /usr/lib/go-${GO_VER}/bin
    ${HOME}/go/bin
    /mnt/c/ProgramData/chocolatey/bin
    /mnt/c/Program\ Files/Microsoft\ VS\ Code/bin
    /mnt/c/WINDOWS/system32
    /mnt/c/WINDOWS
    /mnt/c/WINDOWS/System32/Wbem
    /opt/local/sbin
    /opt/local/bin
    /usr/local/sbin
    /usr/local/bin
    /usr/sbin
    /usr/bin
    /sbin
    /bin
  )
  export PATH
fi

# export ANSIBLEUSER so that we run as the correct user
export ANSIBLEUSER="ubuntu"

# setting PSHOME for powershell use
if [[ ${MACOS} ]]; then
  export PSHOME="/usr/local/microsoft/powershell/6/"
fi

if [[ ${LINUX} ]]; then
  export PSHOME="/opt/microsoft/powershell/6/"
fi

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
alias home='ssh bruce@home.conecrazy.ca'
alias bastion='ssh bruce@bastion'
alias mac='ssh bruce@mac'
alias server='ssh bruce@server'
alias ratna='ssh bruce@ratna'
alias laptop='ssh bruce@laptop'
alias kube-0='ssh bruce@kube-0'
alias kube-1='ssh bruce@kube-1'
alias kube-2='ssh bruce@kube-2'
alias us-24='ssh bruce@us-24'
alias us-16='ssh bruce@us-16'
alias us-8-1='ssh bruce@us-8-1'
alias us-8-2='ssh bruce@us-8-2'
alias upstairs='ssh bruce@upstairs'
alias downstairs='ssh bruce@downstairs'
alias basement='ssh bruce@basement'
alias backyard='ssh bruce@backyard'
alias attic='ssh bruce@frontyard'
# aliases for work servers
alias hwk8001='ssh dvo-lconf@hwk8001-vm'
alias hdp8001='ssh dvo-lconf@hdp8001-vm'
alias hdp8002='ssh dvo-lconf@hdp8002-vm'
alias hdp8003='ssh dvo-lconf@hdp8003-vm'
alias hdp8004='ssh dvo-lconf@hdp8004-vm'
alias hdp8005='ssh dvo-lconf@hdp8005-vm'
alias hdp8006='ssh dvo-lconf@hdp8006-vm'
alias hdf8001='ssh dvo-lconf@hdf8001-vm'
alias hdf8002='ssh dvo-lconf@hdf8002-vm'
alias hdf8003='ssh dvo-lconf@hdf8003-vm'
alias hdf8004='ssh dvo-lconf@hdf8004-vm'
alias hdf8005='ssh dvo-lconf@hdf8005-vm'
alias hdf8006='ssh dvo-lconf@hdf8006-vm'
alias hww8001='ssh dvo-lconf@hww8001-vm'
alias hww8002='ssh dvo-lconf@hww8002-vm'
alias hww8003='ssh dvo-lconf@hww8003-vm'
alias hww8004='ssh dvo-lconf@hww8004-vm'
alias hww8005='ssh dvo-lconf@hww8005-vm'
alias hww8006='ssh dvo-lconf@hww8006-vm'
alias hww8007='ssh dvo-lconf@hww8007-vm'
alias hww8008='ssh dvo-lconf@hww8008-vm'
alias hwk9001='ssh dvo-lconf@hwk9001-vm'
alias hdp9001='ssh dvo-lconf@hdp9001-vm'
alias hdp9002='ssh dvo-lconf@hdp9002-vm'
alias hdp9003='ssh dvo-lconf@hdp9003-vm'
alias hdp9004='ssh dvo-lconf@hdp9004-vm'
alias hdp9005='ssh dvo-lconf@hdp9005-vm'
alias hdp9006='ssh dvo-lconf@hdp9006-vm'
alias hdf9001='ssh dvo-lconf@hdf9001-vm'
alias hdf9002='ssh dvo-lconf@hdf9002-vm'
alias hdf9003='ssh dvo-lconf@hdf9003-vm'
alias hdf9004='ssh dvo-lconf@hdf9004-vm'
alias hdf9005='ssh dvo-lconf@hdf9005-vm'
alias hdf9006='ssh dvo-lconf@hdf9006-vm'
alias hww9001='ssh dvo-lconf@hww9001-vm'
alias hww9002='ssh dvo-lconf@hww9002-vm'
alias hww9003='ssh dvo-lconf@hww9003-vm'
alias hww9004='ssh dvo-lconf@hww9004-vm'
alias hww9005='ssh dvo-lconf@hww9005-vm'
alias hww9006='ssh dvo-lconf@hww9006-vm'
alias hww9007='ssh dvo-lconf@hww9007-vm'
alias hww9008='ssh dvo-lconf@hww9008-vm'
alias den8001='ssh dvo-lconf@den8001-vm'
alias den9001='ssh dvo-lconf@den9001-vm'
alias den9002='ssh dvo-lconf@den9002-vm'
alias pax8001='ssh dvo-lconf@pax8001-vm'
alias pax8002='ssh dvo-lconf@pax8002-vm'
alias pax8003='ssh dvo-lconf@pax8003-vm'
alias pax8004='ssh dvo-lconf@pax8004-vm'
alias pax8005='ssh dvo-lconf@pax8005-vm'
alias pax8006='ssh dvo-lconf@pax8006-vm'
alias pax9001='ssh dvo-lconf@pax9001-vm'
alias pax9002='ssh dvo-lconf@pax9002-vm'
alias pax9003='ssh dvo-lconf@pax9003-vm'
alias pax9004='ssh dvo-lconf@pax9004-vm'
alias pax9005='ssh dvo-lconf@pax9005-vm'
alias pax9006='ssh dvo-lconf@pax9006-vm'
alias sas8001='ssh dvo-lconf@sas8001-vm'
alias sas8002='ssh dvo-lconf@sas8002-vm'
alias sas8003='ssh dvo-lconf@sas8003-vm'
alias sas9001='ssh dvo-lconf@sas9001-vm'
alias sas9002='ssh dvo-lconf@sas9002-vm'
alias sas9003='ssh dvo-lconf@sas9003-vm'
alias sas9004='ssh dvo-lconf@sas9004-vm'
alias sas9005='ssh dvo-lconf@sas9005-vm'
alias dvo9000='ssh dvo-lconf@dvo9000-vm'
alias dvo9003='ssh dvo-lconf@dvo9003-vm'
alias dvo9004='ssh dvo-lconf@dvo9004-vm'
alias wrk9001='ssh dvo-lconf@wrk9001-vm'
alias wrk9003='ssh dvo-lconf@wrk9003-vm'
alias wrk9005='ssh dvo-lconf@wrk9005-vm'

# command aliases
alias au='sudo apt-get update'
alias ad='sudo apt-get dist-upgrade -y'
alias aa='sudo apt-get autoremove -y'
alias dot='cd ~/git-repos/personal/dotfiles && git pl && source ~/.zshrc'
alias update='cd ~/git-repos/personal/dotfiles && git pl && ./setup_env.sh -t update'
alias zu='cd ~/git-repos/z && git pl'
alias oh='cd ~/.oh-my-zsh && git pl'
alias tp='terraform plan -out terraform-plan'
alias ta='terraform apply "terraform-plan"'
alias tiu='terraform init --upgrade'
alias ti='terraform init'
alias tv='terraform validate'
alias td='terraform destroy'

# alias for ls to exa removed due to breaking globbing for ansible aws integration
if quiet_which exa
then
  alias gs="exa -lg --git"
  alias ll="ls -la"
  alias ls="ls -l"
else
  alias ll="ls -la"
  alias ls="ls -l"
fi

# for chruby setup
if [[ -d ${CHRUBY_LOC}/chruby ]]; then
  source ${CHRUBY_LOC}/chruby/chruby.sh
  source ${CHRUBY_LOC}/chruby/auto.sh
  chruby ${RUBY_VER}
fi

# zsh options
# Share history between instances
setopt share_history

# Remove unnecessary blanks from history
setopt hist_reduce_blanks

# add in aws creds for terraform and ansible
export AWS_HOME=${HOME}/.aws

# add in google cloud creds for terraform
if [[ -f ${HOME}/.google_creds ]]; then
  source ${HOME}/.google_creds
fi

# setup for python 3.7 for ansible by using virtualenv
if [[ -d ~/.virtualenvs/ansible ]]; then
  if [[ ${MACOS} || ${LINUX} ]]; then
    source ${VIRTUALENVWRAPPER_SCRIPT}
  fi
  workon ansible
  if [[ -f ${HOME}/.vault_pass.txt ]]; then
    export ANSIBLE_VAULT_PASSWORD_FILE=${HOME}/.vault_pass.txt
  fi
fi

# setup kubectl autocompletion to save typing
if [[ -f /usr/local/bin/kubectl ]]; then
  source <(kubectl completion zsh)
fi

# setup gpg
export GPG_TTY=$(tty)

# for brew zsh-completions
if [[ ${MACOS} ]]; then
  fpath=(/usr/local/share/zsh-completions $fpath)
fi

# for kubeconfig setup
if [[ -f ${HOME}/.kube/config ]]; then
  export KUBECONFIG=${HOME}/.kube/config
fi

# for helm charts
if [[ -d ${HOME}/.helm ]]; then
  export HELM_HOME=${HOME}/.helm
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

# for gcloud command completion
if [[ ${MACOS} ]]; then
  if [[ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc ]]; then
    source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
  fi
fi
if [[ ${UBUNTU} ]]; then
  if [[ -f /usr/share/google-cloud-sdk/completion.zsh.inc ]]; then
    source '/usr/share/google-cloud-sdk/completion.zsh.inc'
  fi
fi
if [[ ${REDHAT} ]]; then
  if [[ -f /usr/lib64/google-cloud-sdk/completion.zsh.inc ]]; then
    source '/usr/lib64/google-cloud-sdk/completion.zsh.inc'
  fi
fi

if [[ ${WINDOWS} ]]; then
  export DOCKER_HOST=tcp://0.0.0.0:2375
fi

# for hashicorp vault, consul and nomad cli autocompletion
if [[ ${MACOS} || ${LINUX} ]]; then
  autoload -U +X bashcompinit && bashcompinit
  if [[ -f /usr/local/bin/vault ]]; then
    complete -o nospace -C /usr/local/bin/vault vault
  fi
  if [[ -f /usr/local/bin/consul ]]; then
    complete -o nospace -C /usr/local/bin/consul consul
  fi
  if [[ -f /usr/local/bin/nomad ]]; then
    complete -o nospace -C /usr/local/bin/nomad nomad
  fi
fi

# for ibmcloud command completion
if [[ ${MACOS} ]]; then
  if [[ -d /usr/local/ibmcloud/autocomplete/zsh_autocomplete ]]; then
    source '/usr/local/ibmcloud/autocomplete/zsh_autocomplete'
  fi
fi

# for z fuzzy cd
if [[ -f ${GITREPOS}/z/z.sh ]]; then
  source ${GITREPOS}/z/z.sh
fi

# az command completion
if [[ ${MACOS} ]]; then
  if [[ -f /usr/local/etc/bash_completion.d/az ]]; then
    autoload -U +X bashcompinit && bashcompinit
    source /usr/local/etc/bash_completion.d/az
  fi
fi
if [[ ${LINUX} ]]; then
  if [[ -f /usr/lib64/az/lib/python3.6/site-packages/argcomplete/bash_completion.d/python-argcomplete ]]; then
    autoload -U +X bashcompinit && bashcompinit
    source /usr/lib64/az/lib/python3.6/site-packages/argcomplete/bash_completion.d/python-argcomplete
  fi
fi

# Powershell modules to install
# Install-Module -Name Az
# Install-Module -Name Az.Blueprint
# Install-Module -Name Microsoft.Graph
