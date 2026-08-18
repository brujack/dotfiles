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
  # HAS_* vars). Resolves via the same PROFILE_LEGACY lookup config/profiles.zsh
  # uses -- same table, same eight variables, same wired/wireless mapping --
  # so a wireless twin (`<name>-1`) sets the same legacy variable as its wired
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
  # shellcheck disable=SC2034 # Read cross-file, which the linter cannot see. This list names EVERY read site -- add one when a site is added, remove one when removed, and treat an omission as seriously as a stale entry: a list that stops naming a live reader reads as "nothing uses these" and is how the variables get deleted. Sites: .config/.zshrc.d/2_functions.zsh, 5_general.zsh (gcloud completion arms at :131/:135 only -- its keychain block reads none of these), 7_final.zsh, .zprofile. One directive covers the whole lookup below (SC1124: a directive cannot sit on a case-arm line -- kept as the reason a single directive sits above the block, now that the case that made it load-bearing is gone).
  local legacy
  legacy="${PROFILE_LEGACY[${hn}]:-}"
  [[ -n ${legacy} ]] && readonly "${legacy}=1"
  # setup variables based off of environment
  # shellcheck disable=SC2034 # read by .config/.zshrc.d/5_general.zsh (chruby sourcing) and lib/helpers.sh:run_doctor
  if [[ -n ${MACOS} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share"
  elif [[ -n ${LINUX} ]]; then
    CHRUBY_LOC="/usr/local/share"
  fi
}
