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

if [[ -n ${UBUNTU} ]]; then
  UBUNTU_VERSION=$(lsb_release -rs)
  [[ ${UBUNTU_VERSION} = "18.04" ]] && readonly BIONIC=1
  [[ ${UBUNTU_VERSION} = "20.04" ]] && readonly FOCAL=1
  [[ ${UBUNTU_VERSION} = "22.04" ]] && readonly JAMMY=1
  [[ ${UBUNTU_VERSION} = "24.04" ]] && readonly NOBLE=1
  [[ ${UBUNTU_VERSION} = "6" ]] && readonly FOCAL=1 # elementary os
fi

[[ $(uname -r) =~ microsoft ]] && export WINDOWS=1
[[ $(hostname -s) = "ratna" ]] && export RATNA=1
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "laptop-1" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "studio-1" ]] && export STUDIO=1
[[ $(hostname -s) = "workstation" ]] && export WORKSTATION=1
[[ $(hostname -s) = "cruncher" ]] && export CRUNCHER=1
[[ $(hostname -s) = "reception" ]] && export RECEPTION=1
[[ $(hostname -s) = "home-1" ]] && export HOMES=1
