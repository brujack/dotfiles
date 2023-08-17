typeset -U path
# for /usr/local includes
if [[ -d /usr/local/bin ]]; then
  path+=('/usr/local/bin')
fi
if [[ -d /usr/local/sbin ]]; then
  path+=('/usr/local/sbin')
fi

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
  if [[ -d /opt/local/bin ]]; then
    path+=('/opt/local/bin')
  fi
  if [[ -d /opt/local/sbin ]]; then
    path+=('/opt/local/sbin')
  fi
  if [[ -d /home/linuxbrew/.linuxbrew/bin ]]; then
    path+=('/home/linuxbrew/.linuxbrew/bin')
  fi
  if [[ -d /home/linuxbrew/.linuxbrew/sbin ]]; then
    path+=('/home/linuxbrew/.linuxbrew/sbin')
  fi
  if [[ -d ${HOME}/.local/bin ]]; then
    path+=("${HOME}/.local/bin")
  fi
  if [[ ${UBUNTU} ]]; then
    if [[ -d /usr/local/go ]]; then
      path+=("/usr/local/go")
    fi
    if [[ -d /snap/bin ]]; then
      path+=('/snap/bin')
    fi
  fi
  if [[ ${REDHAT} ]]; then
    if [[ -d /usr/sbin ]]; then
      path+=('/usr/sbin')
    fi
    if [[ -d /usr/local/go/bin ]]; then
      path+=('/usr/local/go/bin')
    fi
  fi
fi
if [[ -d ${HOME}/.cargo/bin ]]; then
  path+=("${HOME}/.cargo/bin")
fi
# for fzf not installed via a package
if [[ -d ${HOME}/.fzf ]]; then
  path+=("${HOME}/.fzf/bin")
fi
export PATH
