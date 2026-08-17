GO_VER="1.26"
RUBY_VER="4.0.5"
GITREPOS="${HOME}/git-repos"

# Homebrew prefix, not hostname, answers "is this an ARM mac": the blocks
# below used to enumerate five hostnames (RATNA carried a separate arm for
# Intel), so a new Intel mac meant editing every site that asked the
# question. _OVERRIDE_HOMEBREW_PREFIX_ARM / _OVERRIDE_HOMEBREW_PREFIX_INTEL
# are test seams, same convention as _OVERRIDE_GNUBIN_ARM/_OVERRIDE_GNUBIN_INTEL
# in 6_path.zsh -- production leaves them unset and reads the real prefixes.
_homebrew_prefix_arm="${_OVERRIDE_HOMEBREW_PREFIX_ARM:-/opt/homebrew}"
_homebrew_prefix_intel="${_OVERRIDE_HOMEBREW_PREFIX_INTEL:-/usr/local/opt}"

if [[ ${MACOS} ]]; then
  if [[ -d ${_homebrew_prefix_arm} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share/"
  elif [[ -d ${_homebrew_prefix_intel} ]]; then
    CHRUBY_LOC="/usr/local/opt/chruby/share"
  fi
fi
if [[ ${LINUX} ]]; then
  CHRUBY_LOC="/usr/local/share"
fi

# for fzf
if [[ -d ${_homebrew_prefix_arm} ]]; then
  export FZF_BASE=/opt/homebrew/bin/fzf
fi
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

unset _homebrew_prefix_arm _homebrew_prefix_intel

# zsh-autosuggestions — self-healing fallback if plugin dir missing
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

# for chruby (macOS) / rbenv (Linux Noble+) setup
if [[ -n ${MACOS} ]]; then
  if [[ -d ${CHRUBY_LOC}/chruby ]]; then
    source ${CHRUBY_LOC}/chruby/chruby.sh
    source ${CHRUBY_LOC}/chruby/auto.sh
    chruby ${RUBY_VER}
  fi
elif [[ -n ${LINUX} ]]; then
  if [[ -n ${NOBLE} ]] || [[ -n ${RESOLUTE} ]]; then
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      _rbenv_bin="${_OVERRIDE_RBENV_BINARY:-/home/linuxbrew/.linuxbrew/bin/rbenv}"
      if [[ -f ${_rbenv_bin} ]]; then
        eval "$(${_rbenv_bin} init - --no-rehash zsh)"
      fi
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
#
# Guarded on an interactive shell. keychain starts an ssh-agent that daemonizes,
# reparents to init, and keeps every fd it inherited — including the caller's
# stdout. Sourcing this file non-interactively therefore leaks an agent holding
# whatever pipe the caller was writing to. tests/zshrc.d/unit.bats sources it
# exactly that way to reach the rbenv branch, so on any machine with keychain
# installed the leaked agents pinned the bats output pipe open and `make test`
# ran every test and then hung forever waiting on an EOF that could not arrive.
# Measured 2026-08-16 on the Linux workstation: 16 agents on the suite's pipe,
# 161 accumulated since 2026-07-28. The guard costs nothing in production —
# .zshrc.d is only sourced by interactive shells to begin with.
#
# _OVERRIDE_KEYCHAIN_BIN is a test seam. The keychain paths are absolute, so a
# PATH mock cannot shadow them (shell.md, "an absolute-path default silently
# defeats the stub") — without the seam a regression test here could only fail
# on a machine that has keychain installed, which is neither CI nor macOS.
if [[ -o interactive ]]; then
  if [[ ${MACOS} ]]; then
    if [[ ${RATNA} ]]; then
      _keychain="${_OVERRIDE_KEYCHAIN_BIN:-/usr/local/bin/keychain}"
    else
      _keychain="${_OVERRIDE_KEYCHAIN_BIN:-/opt/homebrew/bin/keychain}"
    fi
  elif [[ ${LINUX} ]]; then
    _keychain="${_OVERRIDE_KEYCHAIN_BIN:-/usr/bin/keychain}"
  fi

  if [[ ${MACOS} ]]; then
    if [[ ${RATNA} ]]; then
      eval `"${_keychain}" --eval id_rsa`
      # eval `"${_keychain}" --eval id_ed25519`
      eval `"${_keychain}" --eval home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
      # eval `"${_keychain}" --eval B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062`
    elif [[ ${LAPTOP} ]]; then
      # eval `"${_keychain}" --eval yubikey1`
      eval `"${_keychain}" --eval id_rsa`
      # eval `"${_keychain}" --eval id_ed25519`
      eval `"${_keychain}" --eval home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
      # eval `"${_keychain}" --eval B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062`
    elif [[ ${STUDIO} ]]; then
      # eval `"${_keychain}" --eval yubikey1`
      eval `"${_keychain}" --eval id_rsa`
      # eval `"${_keychain}" --eval id_ed25519`
      eval `"${_keychain}" --eval home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
      # eval `"${_keychain}" --eval B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062`
    elif [[ ${RECEPTION} ]]; then
      eval `"${_keychain}" --eval id_rsa`
      eval `"${_keychain}" --eval home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
    elif [[ ${OFFICE} ]]; then
      eval `"${_keychain}" --eval id_rsa`
      eval `"${_keychain}" --eval home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
    elif [[ ${HOMES} ]]; then
      eval `"${_keychain}" --eval id_rsa`
      eval `"${_keychain}" --eval any home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
    fi
  elif [[ ${LINUX} ]]; then
    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      eval `"${_keychain}" --eval id_rsa`
      # eval `"${_keychain}" --eval id_ed25519`
      eval `"${_keychain}" --eval home`
      eval `"${_keychain}" --eval github`
      eval `"${_keychain}" --eval gitlab`
      # eval `"${_keychain}" --eval B6DCFA4E5AFEA3AF35CE0A189A997C02283A9062`
    else
      eval `"${_keychain}" --eval id_rsa`
    fi
  fi
  unset _keychain
fi
