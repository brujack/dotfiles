# functions
Make() {
  if [ -f Taskfile.yml ]; then
    task "$@"
  elif [ -f Taskfile.yaml ]; then
    task "$@"
  else
    if [[ ${MACOS} ]]; then
      if [[ ${RATNA} ]]; then
        alias make='/usr/local/bin/gmake'
      fi
      if [[ ${LAPTOP} ]]; then
        alias make='/opt/homebrew/bin/gmake'
      elif [[ ${BRUCEWORK} ]]; then
        alias make='/opt/homebrew/bin/gmake'
      fi
    fi
    make "$@"
  fi
}

# choose which env we are running on
[ "$(uname -s)" = "Darwin" ] && export MACOS=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1

if [[ ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && export UBUNTU=1
  [[ ${LINUX_TYPE} = "CentOS Linux" ]] && export CENTOS=1
  [[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && export REDHAT=1
  [[ ${LINUX_TYPE} = "Fedora" ]] && export FEDORA=1
fi

[[ $(uname -r) =~ microsoft ]] && export WINDOWS=1
[[ $(hostname -s) = "ratna" ]] && export RATNA=1
[[ $(hostname -s) = "brucework" ]] && export BRUCEWORK=1
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "workstation" ]] && export WORKSTATION=1
[[ $(hostname -s) = "cruncher" ]] && export CRUNCHER=1

# for keychain ssh key management
if [[ ${MACOS} ]]; then
  if [[ ${RATNA} ]]; then
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_rsa`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any home`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any github`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any gitlab`
    eval `/usr/local/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  elif [[ ${LAPTOP} ]] || [[ ${STUDIO} ]]; then
    #eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any yubikey1`
    #eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_rsa`
    #eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
    eval `/opt/homebrew/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  elif [[ ${BRUCEWORK} ]]; then
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
    eval `/opt/homebrew/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  fi
elif [[ ${LINUX} ]]; then
  if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
    #eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
    #eval `/usr/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/usr/bin/keychain --eval --agents ssh --inherit any home`
    eval `/usr/bin/keychain --eval --agents ssh --inherit any github`
    eval `/usr/bin/keychain --eval --agents ssh --inherit any gitlab`
    eval `/usr/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  else
    eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
  fi
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

GO_VER="1.17"
RUBY_VER="3.1.1"
GITREPOS="${HOME}/git-repos"

# setup some variables for virtualenv
export WORKON_HOME=${HOME}/.virtualenvs
export PROJECT_HOME=${HOME}./virtualenvs
if [[ ${MACOS} ]]; then
  VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
  VIRTUALENVWRAPPER_PYTHON=/usr/local/bin/python3
  if [[ ${RATNA} ]]; then
    CHRUBY_LOC="/usr/local/opt/chruby/share"
  fi
  if [[ ${LAPTOP} ]] || [[ ${STUDIO} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share/"
  elif [[ ${BRUCEWORK} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share/"
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
# ZSH_THEME="bruce"
# ZSH_THEME="powerlevel10k/powerlevel10k"

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

# setting up path
# for unique path entries
typeset -U path
# for /usr/local includes
path+=('/usr/local/bin')
path+=('/usr/local/sbin')

# adding in home bin/scripts path
path+=("${HOME}/bin")
path+=("${HOME}/scripts")

if [[ ${MACOS} ]]; then
  path+=('/opt/homebrew/bin')
fi

if [[ ${LINUX} ]]; then
  path+=('/opt/local/bin')
  path+=('/opt/local/sbin')
  path+=('/home/linuxbrew/.linuxbrew/bin')
  if [[ ${UBUNTU} ]]; then
    path+=("/usr/lib/go-${GO_VER}/bin")
    path+=('/snap/bin')
  fi
  if [[ ${REDHAT} ]]; then
    path+=('/usr/sbin')
    path+=('/usr/local/go/bin')
  fi
fi
# for fzf not installed via a package
if [[ -d ${HOME}/.fzf ]]; then
  path+=("${HOME}/.fzf/bin")
fi
export PATH

# for fzf
if [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${BRUCEWORK} ]]; then
  export FZF_BASE=/opt/homebrew/bin/fzf
fi
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zsh-autosuggestions
if [[ ! -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
fi

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
if [[ ${MACOS} ]]; then
  plugins=(ag ansible aws brew docker fzf git git-prompt helm history-substring-search kubectl macos python terraform vscode pyenv zsh-autosuggestions)
fi
if [[ ${UBUNTU} ]]; then
  plugins=(ag ansible aws brew docker fzf git git-prompt helm history-substring-search kubectl python terraform ubuntu vscode pyenv zsh-autosuggestions)
fi
if [[ ${FEDORA} ]]; then
  plugins=(ag ansible aws docker fzf git git-prompt fedora helm history-substring-search kubectl python terraform vscode pyenv zsh-autosuggestions)
fi
if [[ ${CENTOS} ]]; then
  plugins=(ag ansible aws docker fzf git git-prompt fedora helm history-substring-search kubectl python terraform vscode pyenv zsh-autosuggestions)
fi
if [[ ${REDHAT} ]]; then
  plugins=(ag ansible aws docker fzf git git-prompt fedora helm history-substring-search kubectl python terraform vscode pyenv zsh-autosuggestions)
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

# export ANSIBLEUSER so that we run as the correct user
export ANSIBLEUSER="ubuntu"

# setting PSHOME for powershell use
if [[ ${MACOS} ]]; then
  export PSHOME="/usr/local/microsoft/powershell/7/"
fi
if [[ ${LINUX} ]]; then
  export PSHOME="/opt/microsoft/powershell/7/"
fi

# aliases for home
alias home='ssh bruce@home.conecrazy.ca'
alias bastion='tsh ssh bruce@bastion'
alias downloads='tsh ssh bruce@downloads'
alias server='ssh bruce@server.conecrazy.io'
alias ratna='ssh bruce@ratna.conecrazy.io'
alias workstation='ssh bruce@workstation'
alias fah-0='tsh ssh bruce@fah-0'
alias fah-1='tsh ssh bruce@fah-1'
alias bind-master='tsh ssh bruce@bind-master'
alias bind-slave='tsh ssh bruce@bind-slave'
alias rancher='tsh ssh bruce@rancher'
alias plex='tsh ssh bruce@plex'
alias teleport-server='tsh ssh bruce@teleport'
alias docker-server='tsh ssh bruce@docker-server'
alias nut='tsh ssh bruce@nut'
alias prox-0='tsh ssh root@prox-0'
alias prox-1='tsh ssh root@prox-1'
alias prox-2='tsh ssh root@prox-2'
alias us-24='ssh bruce@us-24-pro'
alias us-16-xg-bottom='ssh bruce@us-16-xg-bottom'
alias us-16-xg-top='ssh bruce@us-16-xg-top'
alias us-8-1='ssh bruce@us-8-1'
alias us-8-2='ssh bruce@us-8-2'
alias frontyard='ssh bruce@frontyard'
alias downstairs='ssh bruce@downstairs'
alias basement='ssh bruce@basement'
alias backyard='ssh bruce@backyard'
alias frontyard='ssh bruce@frontyard'

# aliases for work servers

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
alias make='Make'
alias m='Make'
alias mp='make plan'
alias ma='make apply'
alias mi='make init'
alias tw='~/scripts/tmux-workstation.sh'
alias kgp='kubectl get pods --all-namespaces'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deploy'
alias kgr='kubectl get rs'
alias kgs='kubectl get services --all-namespaces'
alias kcv='kubectl config view'
alias kcc='kubectl config current-context'
alias kcu='kubectl config use-context $@'

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
# moved to pyenv
# if [[ -d ~/.virtualenvs/ansible ]]; then
#   if [[ ${MACOS} || ${LINUX} ]]; then
#     source ${VIRTUALENVWRAPPER_SCRIPT}
#   fi
#   workon ansible
#   if [[ -f ${HOME}/.vault_pass.txt ]]; then
#     export ANSIBLE_VAULT_PASSWORD_FILE=${HOME}/.vault_pass.txt
#   fi
# fi

# pyenv setup
if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]] || [[ ${RATNA} ]] || [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${BRUCEWORK} ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init --path)"
  if command -v pyenv 1>/dev/null 2>&1; then
    if ! [[ -d ${HOME}/.pyenv/versions/ansible ]]; then
      if [[ ${MACOS} || ${LINUX} ]]; then
        pyenv virtualenv ${PYTHON_VER} ansible
        pyenv activate ansible
        # to fix the prompt so that the python virtualenv is shown at the far left of the prompt
        export PYENV_VIRTUALENV_DISABLE_PROMPT=1
        export PS1='($(pyenv version-name)) '$PS1
      fi
    fi
    if [[ -d ${HOME}/.pyenv/versions/ansible ]]; then
      if [[ ${MACOS} || ${LINUX} ]]; then
        pyenv shell ansible
        # to fix the prompt so that the python virtualenv is shown at the far left of the prompt
        export PYENV_VIRTUALENV_DISABLE_PROMPT=1
        export PS1='($(pyenv version-name)) '$PS1
      fi
      if [[ -f ${HOME}/.vault_pass.txt ]]; then
        export ANSIBLE_VAULT_PASSWORD_FILE=${HOME}/.vault_pass.txt
      fi
    fi
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
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

# cheat.sh tab completion
fpath=(${HOME}/.zsh.d/ $fpath)

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

if [[ ${LINUX} ]]; then
  # find out which distribution we are running on
  distro=$(awk '/^ID=/' /etc/*-release | awk -F'=' '{ print tolower($2) }')

  # set an icon based on the distro
  case $distro in
      *kali*)                  ICON="ﴣ";;
      *arch*)                  ICON="";;
      *debian*)                ICON="";;
      *raspbian*)              ICON="";;
      *ubuntu*)                ICON="";;
      *elementary*)            ICON="";;
      *fedora*)                ICON="";;
      *coreos*)                ICON="";;
      *gentoo*)                ICON="";;
      *mageia*)                ICON="";;
      *centos*)                ICON="";;
      *opensuse*|*tumbleweed*) ICON="";;
      *sabayon*)               ICON="";;
      *slackware*)             ICON="";;
      *linuxmint*)             ICON="";;
      *alpine*)                ICON="";;
      *aosc*)                  ICON="";;
      *nixos*)                 ICON="";;
      *devuan*)                ICON="";;
      *manjaro*)               ICON="";;
      *rhel*)                  ICON="";;
      *)                       ICON="";;
  esac
fi
if [[ ${MACOS} ]]; then
  ICON=""
fi

# Load Starship
export STARSHIP_DISTRO="$ICON "
eval "$(starship init zsh)"
