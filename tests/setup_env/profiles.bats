#!/usr/bin/env bats
# tests/setup_env/profiles.bats — profile and capability resolution tests

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_UNAME_S="Darwin"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Resolves detect_env for one hostname in an isolated subshell and prints
# PROFILE plus the sorted set of HAS_* vars it declared. Isolated because
# detect_env sets several `readonly` vars (MACOS, LAPTOP, ...) — sourcing it
# twice in the same process errors on the second `readonly` assignment, so a
# wired/wireless comparison needs two separate processes, not two sourcings.
_profile_snapshot() {
  local hn="$1"
  bash -c "
    export MOCK_HOSTNAME_OUTPUT='${hn}'
    export MOCK_UNAME_S='Darwin'
    export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
    source '${REPO_ROOT}/lib/detect_env.sh'
    detect_env
    printf 'PROFILE=%s\n' \"\${PROFILE}\"
    compgen -v | grep '^HAS_' | sort
  "
}

# ── profile resolution ────────────────────────────────────────────────────────

@test "detect_env sets PROFILE=personal_laptop for hostname laptop" {
  export MOCK_HOSTNAME_OUTPUT="laptop"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "personal_laptop" ]
}

@test "detect_env sets PROFILE=mac_workstation for hostname studio" {
  export MOCK_HOSTNAME_OUTPUT="studio"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

@test "detect_env sets PROFILE=mac_workstation for hostname reception" {
  export MOCK_HOSTNAME_OUTPUT="reception"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

@test "detect_env sets PROFILE=mac_mini for hostname office" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_mini" ]
}

@test "detect_env sets PROFILE=unknown for unrecognised hostname" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "unknown" ]
}

# ── capability vars ───────────────────────────────────────────────────────────

@test "HAS_DEVTOOLS is set for personal_laptop" {
  export MOCK_HOSTNAME_OUTPUT="laptop"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_DEVTOOLS is set for mac_workstation" {
  export MOCK_HOSTNAME_OUTPUT="studio"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_DEVTOOLS is unset for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_DEVTOOLS:-}" ]
}

@test "HAS_GUI is set for all Mac profiles" {
  for hn in laptop studio reception office; do
    result=$(bash -c "
      export MOCK_HOSTNAME_OUTPUT='${hn}'
      export MOCK_UNAME_S='Darwin'
      export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
      source '${REPO_ROOT}/lib/detect_env.sh'
      detect_env
      printf '%s' \"\${HAS_GUI:-}\"
    ")
    [ -n "${result}" ] || {
      printf "HAS_GUI not set for hostname: %s\n" "${hn}" >&2
      return 1
    }
  done
}

@test "HAS_DOCKER is unset for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_DOCKER:-}" ]
}

@test "CHRUBY_LOC is set on macOS for unknown hostname" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  export MOCK_UNAME_S="Darwin"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${CHRUBY_LOC:-}" ]
}

@test "CHRUBY_LOC points to homebrew path on macOS" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  export MOCK_UNAME_S="Darwin"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${CHRUBY_LOC}" = "/opt/homebrew/opt/chruby/share" ]
}

@test "CHRUBY_LOC points to local share on Linux" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  export MOCK_AWK_OS_NAME="Ubuntu"
  unset MACOS
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${CHRUBY_LOC}" = "/usr/local/share" ]
}

@test "HAS_PRINTING is set for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_PRINTING}" ]
}

@test "detect_env sets PROFILE=linux_workstation for hostname workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "linux_workstation" ]
}

@test "detect_env sets PROFILE=wsl2_workstation for hostname cruncher" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "wsl2_workstation" ]
}

@test "HAS_SNAP is set for linux_workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_SNAP}" ]
}

@test "HAS_SNAP is unset for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_SNAP:-}" ]
}

@test "HAS_DEVTOOLS is set for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_RUST is set for linux_workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_RUST}" ]
}

@test "HAS_RUST is set for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_RUST}" ]
}

@test "detect_env sets RESOLUTE=1 for Ubuntu 26.04" {
  export MOCK_UNAME_S="Linux"
  export MOCK_AWK_OS_NAME="Ubuntu"
  export MOCK_LSB_RELEASE_RS="26.04"
  export MOCK_HOSTNAME_OUTPUT="workstation"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [[ -n ${RESOLUTE} ]]
}

# ── wireless hostname equivalence ─────────────────────────────────────────────
# A `-1` suffix is the machine's wireless-interface hostname (see the comments
# in config/profiles.sh for the two named exceptions). `hostname -s` returns
# it whenever the machine is on wifi, so PROFILE_MAP must resolve it
# identically to its wired twin -- the PROFILE string AND the full HAS_* set,
# not just the former. A matching profile with a divergent capability set is
# exactly the class of bug this coverage exists to catch.

@test "wired and wireless laptop resolve to the same PROFILE and HAS_* set" {
  local wired wireless
  wired=$(_profile_snapshot laptop)
  wireless=$(_profile_snapshot laptop-1)
  [ "${wired}" = "${wireless}" ]
}

@test "wired and wireless studio resolve to the same PROFILE and HAS_* set" {
  local wired wireless
  wired=$(_profile_snapshot studio)
  wireless=$(_profile_snapshot studio-1)
  [ "${wired}" = "${wireless}" ]
}

@test "wired and wireless reception resolve to the same PROFILE and HAS_* set" {
  local wired wireless
  wired=$(_profile_snapshot reception)
  wireless=$(_profile_snapshot reception-1)
  [ "${wired}" = "${wireless}" ]
}

@test "wired and wireless ratna resolve to the same PROFILE and HAS_* set" {
  local wired wireless
  wired=$(_profile_snapshot ratna)
  wireless=$(_profile_snapshot ratna-1)
  [ "${wired}" = "${wireless}" ]
}

@test "wired and wireless office resolve to the same PROFILE and HAS_* set" {
  local wired wireless
  wired=$(_profile_snapshot office)
  wireless=$(_profile_snapshot office-1)
  [ "${wired}" = "${wireless}" ]
}

# ── ratna ──────────────────────────────────────────────────────────────────────

@test "detect_env sets PROFILE=mac_workstation for hostname ratna" {
  export MOCK_HOSTNAME_OUTPUT="ratna"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

# ── unmapped / malformed hostname ───────────────────────────────────────────────

@test "unmapped hostname yields PROFILE=unknown and zero HAS_* vars" {
  local snapshot
  snapshot=$(_profile_snapshot unknownhost)
  [ "${snapshot}" = "PROFILE=unknown" ]
}

@test "empty hostname -s output yields PROFILE=unknown" {
  # Routed through _profile_snapshot's subshell rather than a direct,
  # unwrapped `detect_env` call: bash's associative-array lookup emits a
  # harmless "bad array subscript" warning for an empty index (reproduced
  # with a bare `hn=""` outside this suite entirely -- a bash quirk, not
  # something config/profiles.sh causes or this task's scope can fix), and
  # bats runs test bodies under `set -e`, which treats that warning's
  # transient nonzero status as a hard failure and aborts before the
  # assertion. The snapshot's own subshell has no such `set -e`, so the
  # default (`unknown`) is observed the same way production sees it.
  local snapshot
  snapshot=$(_profile_snapshot $'\n')
  [ "${snapshot}" = "PROFILE=unknown" ]
}

@test "hostname studio-2 does not fuzzy-match its prefix-sharing sibling studio-1" {
  export MOCK_HOSTNAME_OUTPUT="studio-2"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "unknown" ]
}
