GO_VER="1.22"
RUBY_VER="3.3.4"
GITREPOS="${HOME}/git-repos"

if [[ ${MACOS} ]]; then
  if [[ ${RATNA} ]]; then
    CHRUBY_LOC="/usr/local/opt/chruby/share"
  fi
  if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share/"
  fi
fi
if [[ ${LINUX} ]]; then
  CHRUBY_LOC="/usr/local/share"
fi

# for fzf
if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n {OFFICE} ]] || [[ -n ${HOMES} ]]; then
  export FZF_BASE=/opt/homebrew/bin/fzf
fi
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zsh-autosuggestions
if [[ ! -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
fi

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

# for chruby setup
if [[ -d ${CHRUBY_LOC}/chruby ]]; then
  if [[ -n ${MACOS} ]]; then
    source ${CHRUBY_LOC}/chruby/chruby.sh
    source ${CHRUBY_LOC}/chruby/auto.sh
    chruby ${RUBY_VER}
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      source ${CHRUBY_LOC}/chruby/chruby.sh
      source ${CHRUBY_LOC}/chruby/auto.sh
      chruby ${RUBY_VER}
    elif [[ -n ${NOBLE} ]]; then
      rbenv init
      rbenv local ${RUBY_VER}
    fi
  fi
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

# ansible vault password file
if [[ -f ${HOME}/.ansible_vault_pass.txt ]]; then
  export ANSIBLE_VAULT_PASSWORD_FILE=${HOME}/.ansible_vault_pass.txt
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

# for gcloud command completion
if [[ ${MACOS} ]]; then
  if [[ ${RATNA} ]]; then
    if [[ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc ]]; then
      source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
    fi
  elif [[ ${LAPTOP} ]] || [[ ${STUDIO} ]]; then
    if [[ -f /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc ]]; then
      source '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
    fi
    if [[ -f /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc ]]; then
      source '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
    fi
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

# for keychain ssh key management
if [[ ${MACOS} ]]; then
  if [[ ${RATNA} ]]; then
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_rsa`
    # eval `/usr/local/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any home`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any github`
    eval `/usr/local/bin/keychain --eval --agents ssh --inherit any gitlab`
    # eval `/usr/local/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  elif [[ ${LAPTOP} ]]; then
    # eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any yubikey1`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_rsa`
    # eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
    # eval `/opt/homebrew/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  elif [[ ${STUDIO} ]]; then
    # eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any yubikey1`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_rsa`
    # eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
    # eval `/opt/homebrew/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  elif [[ ${RECEPTION} ]]; then
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_rsa`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
  elif [[ ${OFFICE} ]]; then
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_rsa`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
  elif [[ ${HOMES} ]]; then
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any id_rsa`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any home`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any github`
    eval `/opt/homebrew/bin/keychain --eval --agents ssh --inherit any gitlab`
  fi
elif [[ ${LINUX} ]]; then
  if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
    eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
    # eval `/usr/bin/keychain --eval --agents ssh --inherit any id_ed25519`
    eval `/usr/bin/keychain --eval --agents ssh --inherit any home`
    eval `/usr/bin/keychain --eval --agents ssh --inherit any github`
    eval `/usr/bin/keychain --eval --agents ssh --inherit any gitlab`
    # eval `/usr/bin/keychain --eval --agents gpg B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062 --inherit any`
  else
    eval `/usr/bin/keychain --eval --agents ssh --inherit any id_rsa`
  fi
fi
