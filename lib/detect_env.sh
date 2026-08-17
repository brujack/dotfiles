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
    # shellcheck disable=SC2034 # read by lib/linux_ubuntu.sh:_install_ubuntu_base_packages, lib/helpers.sh:_doctor_check_versions
    [[ ${UBUNTU_VERSION} = "24.04" ]] && readonly NOBLE=1
    # shellcheck disable=SC2034 # read by lib/linux_ubuntu.sh:_install_ubuntu_base_packages/_install_ubuntu_cloud_tools, lib/helpers.sh:run_doctor
    [[ ${UBUNTU_VERSION} = "26.04" ]] && readonly RESOLUTE=1
  fi

  # Profile resolution
  source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"
  local hn
  hn=$(hostname -s)
  # An empty hn indexes PROFILE_MAP with "" below, which bash reports as
  # "bad array subscript" to stderr (harmless -- the :-unknown fallback
  # still applies) but is silenced by giving it a key that is provably never
  # in the table instead.
  hn="${hn:-__unmapped__}"
  PROFILE="${PROFILE_MAP[${hn}]:-unknown}"
  for cap in ${PROFILE_CAPS[${PROFILE}]:-}; do
    declare -g "HAS_$(printf '%s' "${cap}" | tr '[:lower:]' '[:upper:]')=1"
  done

  # Legacy hostname var aliases (kept until all call sites updated to use
  # HAS_* vars). Mirrors config/profiles.zsh's own case statement exactly --
  # same table, same eight variables, same wired/wireless mapping -- so a
  # wireless twin (`<name>-1`) sets the same legacy variable as its wired
  # counterpart instead of losing its identity the moment it's off ethernet
  # (see config/profiles.sh's comment for the wireless-suffix convention and
  # its two named exceptions).
  #
  # `readonly` here, `export` in profiles.zsh, deliberately -- not a drift to
  # reconcile. detect_env runs once per bash process, so a `readonly`
  # reassignment never happens here. The zsh file is sourced twice per
  # login+interactive shell (.zprofile and 1_init.zsh); a `readonly` there
  # would make the second source return 126. See profiles.zsh's header
  # comment for the full rationale before "fixing" either side to match the
  # other.
  # shellcheck disable=SC2034 # read by .config/.zshrc.d/2_functions.zsh, 7_final.zsh, .zprofile -- one directive covers the whole case (SC1124: a directive cannot sit on a case-arm line). Not 5_general.zsh: its keychain block collapsed to a MACOS/LINUX/HAS_DEVTOOLS test and reads none of these.
  case "${hn}" in
  laptop | laptop-1) readonly LAPTOP=1 ;;
  studio | studio-1) readonly STUDIO=1 ;;
  reception | reception-1) readonly RECEPTION=1 ;;
  ratna | ratna-1) readonly RATNA=1 ;;
  office | office-1) readonly OFFICE=1 ;;
  home-1) readonly HOMES=1 ;;
  workstation) readonly WORKSTATION=1 ;;
  cruncher) readonly CRUNCHER=1 ;;
  esac
  # setup variables based off of environment
  # shellcheck disable=SC2034 # read by .config/.zshrc.d/5_general.zsh (chruby sourcing) and lib/helpers.sh:run_doctor
  if [[ -n ${MACOS} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share"
  elif [[ -n ${LINUX} ]]; then
    CHRUBY_LOC="/usr/local/share"
  fi
}
