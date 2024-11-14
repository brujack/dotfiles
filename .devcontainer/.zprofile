# pyenv setup
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "laptop-1" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "studio-1" ]] && export STUDIO=1
[[ $(hostname -s) = "reception" ]] && export RECEPTION=1
[[ $(hostname -s) = "reception-1" ]] && export RECEPTION=1
[[ $(hostname -s) = "office" ]] && export OFFICE=1
[[ $(hostname -s) = "office-1" ]] && export OFFICE=1
[[ $(hostname -s) = "homes" ]] && export HOMES=1
[[ $(hostname -s) = "homes-1" ]] && export HOMES=1
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
eval "$(pyenv init --path)"

# rbenv setup
[ "$(uname -s)" = "Darwin" ] && export MACOS=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1

if [[ ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && export UBUNTU=1
  [[ ${LINUX_TYPE} = "CentOS Linux" ]] && export CENTOS=1
  [[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && export REDHAT=1
  [[ ${LINUX_TYPE} = "Fedora" ]] && export FEDORA=1
fi

if [[ -n ${UBUNTU} ]]; then
  UBUNTU_VERSION=$(lsb_release -rs)
  [[ ${UBUNTU_VERSION} = "18.04" ]] && readonly BIONIC=1
  [[ ${UBUNTU_VERSION} = "20.04" ]] && readonly FOCAL=1
  [[ ${UBUNTU_VERSION} = "22.04" ]] && readonly JAMMY=1
  [[ ${UBUNTU_VERSION} = "24.04" ]] && readonly NOBLE=1
  [[ ${UBUNTU_VERSION} = "6" ]] && readonly FOCAL=1 # elementary os
fi

if [[ ${LINUX} ]]; then
  if [[ -n ${NOBLE }]]; then
    command -v /home/linuxbrew/.linuxbrew/bin/rbenv && eval "$(rbenv init - --no-rehash zsh)"
  fi
fi
