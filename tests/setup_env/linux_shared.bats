#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Writes a differentiated `apt` stub that answers per-subcommand (`update`
# vs `install`) so update-fails/install-succeeds and the reverse can be
# tested in isolation. tests/mocks/apt applies one exit code to every
# invocation regardless of args, which cannot express that split — and it
# is out of scope for this task to edit that shared mock. Prints the stub's
# directory so the caller can prepend it to PATH.
_apt_stub_path() {
  local _update_exit="$1" _install_exit="$2"
  local _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/apt" << EOF
#!${_bash_bin}
printf 'apt %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
case "\$1" in
  update) exit ${_update_exit} ;;
  install) exit ${_install_exit} ;;
esac
exit 0
EOF
  chmod +x "${_dir}/apt"
  printf '%s' "${_dir}"
}

# ── update_system_packages — Noble path ─────────────────────────────────────

@test "update_system_packages: calls nala full-upgrade" {
  export UBUNTU=1
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: skips snap when snap is unavailable" {
  export UBUNTU=1

  # Override the seam rather than editing PATH. On Ubuntu 24.04 — what
  # ubuntu-latest runs — snap is /usr/bin/snap, so stripping "the directory
  # containing snap" strips bash, grep, sed, awk and mktemp with it. That
  # passed on macOS and failed in CI.
  _snap_available() { return 1; }

  run update_system_packages
  [ "$status" -eq 0 ]
  # Pin the apt half as having run, so the snap absence is the gate firing
  # rather than the whole function short-circuiting.
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
  refute_grep "snap refresh" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: runs snap even when apt fails" {
  export UBUNTU=1
  export MOCK_APT_EXIT=1
  run update_system_packages
  [ "$status" -eq 1 ]
  grep -q "snap refresh" "${MOCK_CALLS_FILE}"
}

# ── update_apt_packages ──────────────────────────────────────────────────────

@test "update_apt_packages: propagates a failing apt update" {
  export UBUNTU=1
  export MOCK_APT_EXIT=1
  run update_apt_packages
  [ "$status" -eq 1 ]
  [[ "$output" != *"Updated apt packages"* ]]
}

@test "update_apt_packages: propagates a failing nala full-upgrade" {
  export UBUNTU=1
  export MOCK_NALA_EXIT=1
  run update_apt_packages
  [ "$status" -eq 1 ]
  [[ "$output" != *"Updated apt packages"* ]]
}

@test "update_apt_packages: succeeds and does not call snap" {
  export UBUNTU=1
  run update_apt_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated apt packages"* ]]
  refute_grep "snap" "${MOCK_CALLS_FILE}"
}

# ── update_snap_packages ─────────────────────────────────────────────────────

@test "update_snap_packages: propagates a failing snap refresh" {
  export UBUNTU=1
  export MOCK_SNAP_EXIT=1
  run update_snap_packages
  [ "$status" -eq 1 ]
  [[ "$output" != *"Updated snap packages"* ]]
}

@test "update_snap_packages: succeeds and does not call apt" {
  export UBUNTU=1
  run update_snap_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated snap packages"* ]]
  refute_grep "apt " "${MOCK_CALLS_FILE}"
}

# ── shared dpkg-query mock — legacy list form ───────────────────────────────
# lib/package_capture.sh's _list_apt_packages calls `dpkg-query -W -f
# '${Package}\t${Version}\n'` with -f and its format string as SEPARATE
# tokens. tests/setup_env/package_capture.bats never exercises the shared
# mock -- it builds its own curated-PATH dpkg-query stand-in -- so this is
# the only place in the suite that drives a real production caller of the
# two-separate-token legacy form through tests/mocks/dpkg-query itself.

@test "shared dpkg-query mock: _list_apt_packages parses the two-token legacy form" {
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/package_capture.sh"
  local _dpkg_output
  _dpkg_output="$(printf 'git\t1.0')"
  export MOCK_DPKG_OUTPUT="${_dpkg_output}"
  run _list_apt_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name": "git"'* ]]
  [[ "$output" == *'"version": "1.0"'* ]]
}

# ── install_zsh_linux ────────────────────────────────────────────────────────

@test "install_zsh_linux: skips when zsh and zsh-doc are both installed" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_zsh=ii
  export MOCK_DPKG_STATUS_zsh_doc=ii
  run install_zsh_linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_grep "apt install" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: installs when zsh-doc is absent" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_zsh=ii
  unset MOCK_DPKG_STATUS_zsh_doc
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: installs when zsh is in rc state" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_zsh=rc
  # zsh-doc must read as installed here — otherwise its absence alone would
  # explain the guard failing, and the test would say nothing about `rc`.
  export MOCK_DPKG_STATUS_zsh_doc=ii
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: propagates a failing apt install" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc
  export MOCK_APT_EXIT=1
  run install_zsh_linux
  [ "$status" -eq 1 ]
  [[ "$output" != *"Installed zsh"* ]]
}

@test "install_zsh_linux: warns but continues when apt update fails" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc
  local _stub_dir _old_path
  _stub_dir="$(_apt_stub_path 1 0)"
  _old_path="${PATH}"
  export PATH="${_stub_dir}:${PATH}"
  run install_zsh_linux
  export PATH="${_old_path}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt update failed"* ]]
  [[ "$output" == *"Installed zsh"* ]]
}

@test "install_zsh_linux: does not run dist-upgrade" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc
  run install_zsh_linux
  [ "$status" -eq 0 ]
  # Pin the install path as the reason dist-upgrade is absent. Without this,
  # the guard short-circuiting produces the same absence and the assertion
  # passes while proving nothing -- confirmed by mutation.
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
  refute_grep "dist-upgrade" "${MOCK_CALLS_FILE}"
}

# ── install_git_linux ────────────────────────────────────────────────────────

@test "install_git_linux: skips when git is already installed" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_git=ii
  run install_git_linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_grep "apt install" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: installs when git is absent" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: installs when git is in rc state" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_git=rc
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: propagates a failing apt install" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  export MOCK_APT_EXIT=1
  run install_git_linux
  [ "$status" -eq 1 ]
  [[ "$output" != *"Installed git"* ]]
}

@test "install_git_linux: warns but continues when PPA add fails" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  export MOCK_ADD_APT_REPO_EXIT=1
  run install_git_linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"PPA add failed"* ]]
  [[ "$output" == *"Installed git"* ]]
}

@test "install_git_linux: does not run dist-upgrade" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  run install_git_linux
  [ "$status" -eq 0 ]
  # See the zsh sibling: the install path must be pinned, or a short-circuiting
  # guard satisfies the absence assertion on its own.
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
  refute_grep "dist-upgrade" "${MOCK_CALLS_FILE}"
}
