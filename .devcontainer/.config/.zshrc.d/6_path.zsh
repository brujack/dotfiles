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
