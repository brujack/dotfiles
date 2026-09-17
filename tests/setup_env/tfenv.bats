#!/usr/bin/env bats
# Tests for _install_ubuntu_tfenv (lib/linux_ubuntu.sh).
#
# terraform on the Mac and on `workstation` comes from tfenv:
# /usr/local/bin/terraform is a symlink into ~/.tfenv/bin. The whole point of
# this function is that it must never overwrite an existing binary or
# version choice with something else -- an earlier design that installed a
# static terraform binary would have silently replaced that symlink and
# orphaned tfenv underneath it. Every test below points _TFENV_ROOT and
# _TFENV_LINK_DIR at BATS_TEST_TMPDIR so nothing here can touch a real
# /usr/local/bin, ~/.tfenv, or perform a real git clone -- load_mocks puts
# tests/mocks/git (a mkdir-only clone stub) and tests/mocks/ln (a
# call-logging pass-through to the real /bin/ln) ahead of the real
# binaries on PATH.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"

  # Defence in depth on top of the seams below: DRY_RUN is not read by
  # _install_ubuntu_tfenv itself, but this suite manipulates PATH via
  # load_mocks, so set it anyway per the destructive-failing-path discipline
  # (tdd.md E2) other suites in this repo follow.
  export DRY_RUN=1

  export HAS_DEVTOOLS=1
  export TERRAFORM_VER="1.15.6"
  export _TFENV_ROOT="${BATS_TEST_TMPDIR}/tfenv-root"
  export _TFENV_LINK_DIR="${BATS_TEST_TMPDIR}/links"
  mkdir -p "${_TFENV_LINK_DIR}"

  # tfenv's own call log, written by the recording fixture _seed_tfenv_root
  # installs at ${_TFENV_ROOT}/bin/tfenv -- kept separate from
  # MOCK_CALLS_FILE (git/ln/sudo) so install/use ordering assertions don't
  # have to filter out unrelated lines.
  export TFENV_CALLS_FILE="${BATS_TEST_TMPDIR}/tfenv_calls"
  : > "${TFENV_CALLS_FILE}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}" "${TFENV_CALLS_FILE:-}"
}

# Seeds ${_TFENV_ROOT}/bin/{tfenv,terraform} as real, harmless scripts, so
# the symlink and version steps have something concrete to point at without
# a real git clone. tfenv itself is a recording fixture: it appends its argv
# to TFENV_CALLS_FILE and exits 0 (or MOCK_TFENV_EXIT), so install/use can be
# asserted on without invoking the real tfenv or reaching the network.
#
# $1: with_version -- "yes" writes a version file (skips the install/use
#     branch), "no" leaves it absent (takes it).
_seed_tfenv_root() {
  local _with_version="$1"
  mkdir -p "${_TFENV_ROOT}/bin"
  cat > "${_TFENV_ROOT}/bin/tfenv" <<'FIXTURE'
#!/usr/bin/env bash
printf "tfenv %s\n" "$*" >> "${TFENV_CALLS_FILE:-/tmp/tfenv_calls}"
exit "${MOCK_TFENV_EXIT:-0}"
FIXTURE
  chmod +x "${_TFENV_ROOT}/bin/tfenv"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_TFENV_ROOT}/bin/terraform"
  chmod +x "${_TFENV_ROOT}/bin/terraform"
  if [[ "${_with_version}" == "yes" ]]; then
    printf '1.14.9\n' > "${_TFENV_ROOT}/version"
  fi
}

# ── HAS_DEVTOOLS gate ────────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: no-op and no clone reached when HAS_DEVTOOLS is unset" {
  unset HAS_DEVTOOLS
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ -z "$(cat "${MOCK_CALLS_FILE}")" ]
  [ ! -e "${_TFENV_ROOT}" ]
}

# ── absent root: clone ───────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: absent root clones tfenv" {
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  grep -q "^git clone https://github.com/tfutils/tfenv.git ${_TFENV_ROOT}\$" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfenv: clone failure warns and returns 0" {
  export MOCK_GIT_CLONE_EXIT=1
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [[ "$output" == *"tfenv clone"*"failed"* ]]
}

# ── symlink management ──────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: absent link paths get symlinked into tfenv/bin" {
  _seed_tfenv_root "yes"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ -L "${_TFENV_LINK_DIR}/tfenv" ]
  [ -L "${_TFENV_LINK_DIR}/terraform" ]
  [ "$(readlink "${_TFENV_LINK_DIR}/tfenv")" = "${_TFENV_ROOT}/bin/tfenv" ]
  [ "$(readlink "${_TFENV_LINK_DIR}/terraform")" = "${_TFENV_ROOT}/bin/terraform" ]
}

@test "_install_ubuntu_tfenv: an existing correct symlink is left untouched" {
  _seed_tfenv_root "yes"
  ln -s "${_TFENV_ROOT}/bin/tfenv" "${_TFENV_LINK_DIR}/tfenv"
  ln -s "${_TFENV_ROOT}/bin/terraform" "${_TFENV_LINK_DIR}/terraform"
  : > "${MOCK_CALLS_FILE}"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ "$(readlink "${_TFENV_LINK_DIR}/tfenv")" = "${_TFENV_ROOT}/bin/tfenv" ]
  # `! grep -q ...` at the top of a bats test body is exempt from bats' set -e
  # abort semantics (a `!`-negated command never triggers errexit), so a
  # matching grep would silently NOT fail the test. `run` + an explicit
  # status check is the safe idiom this repo already uses elsewhere.
  run grep -q "^ln " "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_tfenv: a regular file at the link path is left untouched and warned" {
  _seed_tfenv_root "yes"
  printf 'sentinel-do-not-touch\n' > "${_TFENV_LINK_DIR}/tfenv"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ ! -L "${_TFENV_LINK_DIR}/tfenv" ]
  [ "$(cat "${_TFENV_LINK_DIR}/tfenv")" = "sentinel-do-not-touch" ]
  [[ "$output" == *"${_TFENV_LINK_DIR}/tfenv"* ]]
}

@test "_install_ubuntu_tfenv: a symlink pointing elsewhere is left untouched and warned" {
  _seed_tfenv_root "yes"
  ln -s "/nonexistent/other/tfenv" "${_TFENV_LINK_DIR}/tfenv"
  : > "${MOCK_CALLS_FILE}"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ "$(readlink "${_TFENV_LINK_DIR}/tfenv")" = "/nonexistent/other/tfenv" ]
  [[ "$output" == *"${_TFENV_LINK_DIR}/tfenv"* ]]
  run grep -q "^ln .*${_TFENV_LINK_DIR}/tfenv" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

# ── version management ──────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: an existing version file skips install and use" {
  _seed_tfenv_root "yes"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ -z "$(cat "${TFENV_CALLS_FILE}")" ]
}

@test "_install_ubuntu_tfenv: a missing version file installs then uses TERRAFORM_VER" {
  _seed_tfenv_root "no"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "${TFENV_CALLS_FILE}")" = "tfenv install 1.15.6" ]
  [ "$(sed -n '2p' "${TFENV_CALLS_FILE}")" = "tfenv use 1.15.6" ]
}

# ── containment ──────────────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: no ln or sudo call ever names a path outside BATS_TEST_TMPDIR" {
  _seed_tfenv_root "no"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  # Wrapped in `run bash -c` (rather than a bare `! cmd1 | cmd2` at the test
  # top level) for the same set -e exemption reason as the two tests above,
  # plus tdd.md pitfall D: a bare pipeline's status is its LAST command's, so
  # a bare `!` here would silently swallow the first grep's exit status too.
  run bash -c "grep -E '^(ln|sudo) ' '${MOCK_CALLS_FILE}' | grep -v '${BATS_TEST_TMPDIR}'"
  [ "$status" -ne 0 ]
}
