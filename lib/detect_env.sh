#!/usr/bin/env bash
# lib/detect_env.sh — OS/version detection and hostname-based role vars

detect_env() {
  # choose which env we are running on
  [[ $(uname -s) = "Darwin" ]] && readonly MACOS=1
  [[ $(uname -s) = "Linux" ]] && readonly LINUX=1

  if [[ -n ${LINUX} ]]; then
    LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
    [[ ${LINUX_TYPE} = "Ubuntu" ]] && readonly UBUNTU=1
  fi

  if [[ -n ${UBUNTU} ]]; then
    UBUNTU_VERSION=$(lsb_release -rs)
    [[ ${UBUNTU_VERSION} = "24.04" ]] && readonly NOBLE=1
  fi

  [[ $(uname -r) =~ microsoft ]] && readonly WINDOWS=1

  # Profile resolution
  source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"
  local hn
  hn=$(hostname -s)
  PROFILE="${PROFILE_MAP[${hn}]:-unknown}"
  for cap in ${PROFILE_CAPS[${PROFILE}]:-}; do
    declare -g "HAS_$(printf '%s' "${cap}" | tr '[:lower:]' '[:upper:]')=1"
  done

  # Legacy hostname var aliases (kept until all call sites updated to use HAS_* vars)
  [[ "${hn}" == "laptop" ]]      && readonly LAPTOP=1
  [[ "${hn}" == "studio" ]]      && readonly STUDIO=1
  [[ "${hn}" == "reception" ]]   && readonly RECEPTION=1
  [[ "${hn}" == "office" ]]      && readonly OFFICE=1
  [[ "${hn}" == "home-1" ]]      && readonly HOMES=1
  # setup variables based off of environment
  if [[ -n ${MACOS} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share"
  elif [[ -n ${LINUX} ]]; then
    CHRUBY_LOC="/usr/local/share"
  fi
}
