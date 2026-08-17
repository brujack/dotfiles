# choose which env we are running on
[ "$(uname -s)" = "Darwin" ] && export MACOS=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1

if [[ ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && export UBUNTU=1
fi

if [[ -n ${UBUNTU} ]]; then
  UBUNTU_VERSION=$(lsb_release -rs)
  [[ ${UBUNTU_VERSION} = "24.04" ]] && { [[ -n "${NOBLE+x}" ]] || readonly NOBLE=1; }
  [[ ${UBUNTU_VERSION} = "26.04" ]] && { [[ -n "${RESOLUTE+x}" ]] || readonly RESOLUTE=1; }
fi

[[ $(uname -r) =~ microsoft ]] && export WINDOWS=1
source "${${(%):-%x}:A:h}/../../config/profiles.zsh"
