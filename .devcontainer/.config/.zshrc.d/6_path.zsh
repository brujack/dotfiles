typeset -U path
# for /usr/local includes
path+=('/usr/local/bin')
path+=('/usr/local/sbin')

# adding in home bin/scripts path
if [[ -d ${HOME}/bin ]]; then
  path+=("${HOME}/bin")
fi
if [[ -d ${HOME}/scripts ]]; then
  path+=("${HOME}/scripts")
fi

if [[ ${MACOS} ]]; then
  if [[ -d /opt/homebrew/bin ]]; then
    path+=('/opt/homebrew/bin')
  fi
  if [[ -d /opt/homebrew/sbin ]]; then
    path+=('/opt/homebrew/sbin')
  fi
fi

if [[ ${LINUX} ]]; then
  path+=('/opt/local/bin')
  path+=('/opt/local/sbin')
  if [[ -d ${HOME}/.linuxbrew/bin ]]; then
    path+=("${HOME}/.linuxbrew/bin")
  fi
  if [[ -d ${HOME}/.local/bin ]]; then
    path+=("${HOME}/.local/bin")
  fi
  if [[ ${UBUNTU} ]]; then
    if [[ -d /usr/lib/go-${GO_VER}/bin ]]; then
      path+=("/usr/lib/go-${GO_VER}/bin")
    fi
    path+=('/snap/bin')
  fi
  if [[ ${REDHAT} ]]; then
    path+=('/usr/sbin')
    if [[ -d /usr/local/go/bin ]]; then
      path+=('/usr/local/go/bin')
    fi
  fi
fi
# for fzf not installed via a package
if [[ -d ${HOME}/.fzf ]]; then
  path+=("${HOME}/.fzf/bin")
fi
export PATH
