GO_VER="1.26"
RUBY_VER="4.0.5"
GITREPOS="${HOME}/git-repos"

# Homebrew prefix, not hostname, answers "is this an ARM mac": the blocks
# below used to enumerate five hostnames (RATNA carried a separate arm for
# Intel), so a new Intel mac meant editing every site that asked the
# question. _OVERRIDE_HOMEBREW_PREFIX_ARM / _OVERRIDE_HOMEBREW_PREFIX_INTEL
# are test seams, same convention as _OVERRIDE_GNUBIN_ARM/_OVERRIDE_GNUBIN_INTEL
# in 6_path.zsh -- production leaves them unset and reads the real prefixes.
#
# One pair for the whole file, one meaning: the seam IS the Homebrew prefix
# (/opt/homebrew, /usr/local), and every consumer below -- CHRUBY_LOC,
# FZF_BASE, and the keychain binary path further down -- derives its path
# from it rather than treating it as a bare existence probe with its own
# hardcoded literal. Two different meanings for the same override variable
# used to coexist here (an "/usr/local/opt" existence probe with a literal
# output vs. a "/usr/local" path prefix an output was built from); a test
# that set the seam once would have exercised two different contracts and
# looked consistent doing it. Unset once, at the very end of the file after
# the interactive keychain block -- not here -- since that block also reads
# these two vars and runs later.
_homebrew_prefix_arm="${_OVERRIDE_HOMEBREW_PREFIX_ARM:-/opt/homebrew}"
_homebrew_prefix_intel="${_OVERRIDE_HOMEBREW_PREFIX_INTEL:-/usr/local}"

if [[ ${MACOS} ]]; then
  if [[ -d ${_homebrew_prefix_arm} ]]; then
    CHRUBY_LOC="${_homebrew_prefix_arm}/opt/chruby/share/"
  elif [[ -d ${_homebrew_prefix_intel} ]]; then
    CHRUBY_LOC="${_homebrew_prefix_intel}/opt/chruby/share"
  fi
fi
if [[ ${LINUX} ]]; then
  CHRUBY_LOC="/usr/local/share"
fi

# for fzf
if [[ -d ${_homebrew_prefix_arm} ]]; then
  export FZF_BASE="${_homebrew_prefix_arm}/bin/fzf"
fi
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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
    if [[ ${HAS_DEVTOOLS} ]]; then
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
#
# Seven per-host arms collapsed to a capability test plus one shared key
# list. All six mac arms loaded the same four keys (id_rsa, home, github,
# gitlab) -- home-1's arm read `--eval any home` instead of `--eval home`,
# but keychain has no `any` flag, so that was reading "any" as a (nonexistent)
# key name rather than a deliberate fifth key; dropped as a typo. The Linux
# split (WORKSTATION||CRUNCHER vs. everything else) was just "a known dev
# profile or not", which HAS_DEVTOOLS now expresses directly against
# config/profiles.sh's table -- today only linux_workstation/wsl2_workstation
# (i.e. WORKSTATION/CRUNCHER) carry it, so this is behaviour-preserving for
# every currently-mapped host.
#
# Third, recorded rather than gated: the old MACOS chain had no final
# `else`, so a mac whose hostname misses every legacy var (a guest, or one
# not yet added to config/profiles.sh's PROFILE_MAP) invoked keychain zero
# times. The collapsed arm has no per-host branch left to be absent from, so
# such a mac now loads the four standard keys too. Gating this back off
# would mean re-adding an "is this a known profile" branch -- exactly the
# per-host testing this collapse removed -- for a direction (a new mac gets
# its keys instead of silently none) that is arguably the more correct
# behaviour anyway. See tests/zshrc.d/unit.bats, "keychain now loads keys on
# an unmapped mac too".
#
# The binary-path selection used to test RATNA (Intel) vs. everything else
# (ARM) by hostname. It now derives from the same _homebrew_prefix_arm /
# _homebrew_prefix_intel pair the CHRUBY_LOC/FZF_BASE section above already
# computed -- one prefix pair for the whole file, reused here rather than
# recomputed with a second default, so there is exactly one meaning for the
# override seam, not two.
if [[ -o interactive ]]; then
  if [[ ${MACOS} ]]; then
    if [[ -d ${_homebrew_prefix_arm} ]]; then
      _keychain="${_OVERRIDE_KEYCHAIN_BIN:-${_homebrew_prefix_arm}/bin/keychain}"
    elif [[ -d ${_homebrew_prefix_intel} ]]; then
      _keychain="${_OVERRIDE_KEYCHAIN_BIN:-${_homebrew_prefix_intel}/bin/keychain}"
    fi
    _keychain_keys=(id_rsa home github gitlab)
  elif [[ ${LINUX} ]]; then
    _keychain="${_OVERRIDE_KEYCHAIN_BIN:-/usr/bin/keychain}"
    if [[ ${HAS_DEVTOOLS} ]]; then
      _keychain_keys=(id_rsa home github gitlab)
    else
      _keychain_keys=(id_rsa)
    fi
  fi

  if [[ -n ${_keychain} ]]; then
    for _keychain_key in "${_keychain_keys[@]}"; do
      eval `"${_keychain}" --eval ${_keychain_key}`
    done
  fi
  unset _keychain _keychain_keys _keychain_key
fi

# _homebrew_prefix_arm/_homebrew_prefix_intel are read by both the
# CHRUBY_LOC/FZF_BASE block near the top of this file and the keychain block
# just above -- unset once, here, after both have run, rather than
# immediately after the first use. The interactive guard around the keychain
# block does not gate this: on a non-interactive source the keychain `if`
# body never runs, but this line is not inside it, so the vars are still
# reclaimed on every source, interactive or not.
unset _homebrew_prefix_arm _homebrew_prefix_intel
