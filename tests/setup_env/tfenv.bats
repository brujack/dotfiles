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
#
# TERRAFORM_VER and _TFENV_REPO_URL are deliberately set to values that
# differ from lib/constants.sh's real defaults (1.15.6 and the real tfutils
# URL). A test that asserts on the real default cannot tell "the seam was
# read" from "the value was hardcoded and happened to match" -- fixed
# 2026-09-17 after review found both seams unpinned this way.

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
  export TERRAFORM_VER="9.9.9"
  export _TFENV_REPO_URL="file:///sentinel/tfenv.git"
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
  # Restore in case a test left the link dir read-only (F2's sudo-routing
  # test) -- bats' own tmpdir cleanup removes entries via the PARENT
  # directory's permissions, not the child's, so this isn't load-bearing for
  # cleanup itself, but leaving a read-only directory behind is still worth
  # not doing.
  chmod u+w "${_TFENV_LINK_DIR:-}" 2> /dev/null || true
  rm -f "${MOCK_CALLS_FILE:-}" "${TFENV_CALLS_FILE:-}"
}

# Seeds ${_TFENV_ROOT}/bin/{tfenv,terraform} as real, harmless scripts, so
# the symlink and version steps have something concrete to point at without
# a real git clone. tfenv itself is a recording fixture: it appends its argv
# to TFENV_CALLS_FILE and exits according to its subcommand, so install and
# use can be driven to fail independently:
#
#   MOCK_TFENV_INSTALL_EXIT  -- exit code for `tfenv install ...` only
#   MOCK_TFENV_USE_EXIT      -- exit code for `tfenv use ...` only
#   MOCK_TFENV_EXIT          -- fallback for both, and for any other
#                               subcommand; default 0
#
# $1: with_version -- "yes" writes a version file (skips the install/use
#     branch), "no" leaves it absent (takes it).
_seed_tfenv_root() {
  local _with_version="$1"
  mkdir -p "${_TFENV_ROOT}/bin"
  cat > "${_TFENV_ROOT}/bin/tfenv" <<'FIXTURE'
#!/usr/bin/env bash
printf "tfenv %s\n" "$*" >> "${TFENV_CALLS_FILE:-/tmp/tfenv_calls}"
case "$1" in
  install) exit "${MOCK_TFENV_INSTALL_EXIT:-${MOCK_TFENV_EXIT:-0}}" ;;
  use)     exit "${MOCK_TFENV_USE_EXIT:-${MOCK_TFENV_EXIT:-0}}" ;;
  *)       exit "${MOCK_TFENV_EXIT:-0}" ;;
esac
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

@test "_install_ubuntu_tfenv: absent root clones tfenv from the configured URL" {
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  grep -q "^git clone ${_TFENV_REPO_URL} ${_TFENV_ROOT}\$" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfenv: clone failure warns and returns 0" {
  export MOCK_GIT_CLONE_EXIT=1
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [[ "$output" == *"tfenv clone"*"failed"* ]]
}

@test "_install_ubuntu_tfenv: an existing root is not re-cloned" {
  _seed_tfenv_root "yes"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  refute_grep "^git clone" "${MOCK_CALLS_FILE}"
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
  refute_grep "^ln " "${MOCK_CALLS_FILE}"
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
  refute_grep "^ln .*${_TFENV_LINK_DIR}/tfenv" "${MOCK_CALLS_FILE}"
}

# ── sudo routing ─────────────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: a writable link dir never invokes sudo" {
  _seed_tfenv_root "yes"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  refute_grep "^sudo " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfenv: a non-writable link dir routes symlinking through sudo" {
  _seed_tfenv_root "yes"
  chmod 0555 "${_TFENV_LINK_DIR}"

  # A recording-only sudo shim, deliberately NOT tests/mocks/sudo -- that
  # mock execs the real command when it resolves on PATH, which here would
  # attempt a genuine write into a directory this test just made read-only
  # (tdd.md E2: a test's failing path must be inert).
  local _sudo_shim="${BATS_TEST_TMPDIR}/sudo-shim"
  mkdir -p "${_sudo_shim}"
  cat > "${_sudo_shim}/sudo" <<EOF
#!/usr/bin/env bash
printf "sudo %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
exit 0
EOF
  chmod +x "${_sudo_shim}/sudo"

  PATH="${_sudo_shim}:${PATH}" run _install_ubuntu_tfenv
  chmod 0755 "${_TFENV_LINK_DIR}"
  [ "$status" -eq 0 ]
  grep -qF "sudo ln -s" "${MOCK_CALLS_FILE}"
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
  [ "$(sed -n '1p' "${TFENV_CALLS_FILE}")" = "tfenv install ${TERRAFORM_VER}" ]
  [ "$(sed -n '2p' "${TFENV_CALLS_FILE}")" = "tfenv use ${TERRAFORM_VER}" ]
}

@test "_install_ubuntu_tfenv: tfenv install failure warns, returns 0, and use is never attempted" {
  _seed_tfenv_root "no"
  export MOCK_TFENV_INSTALL_EXIT=1
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [[ "$output" == *"tfenv install"*"failed"* ]]
  [ "$(wc -l < "${TFENV_CALLS_FILE}")" -eq 1 ]
  refute_grep "^tfenv use" "${TFENV_CALLS_FILE}"
}

@test "_install_ubuntu_tfenv: tfenv use failure warns and returns 0 rather than propagating" {
  _seed_tfenv_root "no"
  export MOCK_TFENV_USE_EXIT=1
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [[ "$output" == *"tfenv use"*"failed"* ]]
  [ "$(sed -n '1p' "${TFENV_CALLS_FILE}")" = "tfenv install ${TERRAFORM_VER}" ]
  [ "$(sed -n '2p' "${TFENV_CALLS_FILE}")" = "tfenv use ${TERRAFORM_VER}" ]
}

@test "_install_ubuntu_tfenv: a failing symlink warns and returns 0 rather than propagating" {
  _seed_tfenv_root "yes"
  export MOCK_LN_EXIT=1
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  [[ "$output" == *"linking"*"failed"* ]]
}

# ── containment ──────────────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: no ln or sudo call ever names the real default link dir" {
  _seed_tfenv_root "no"
  run _install_ubuntu_tfenv
  [ "$status" -eq 0 ]
  refute_grep "/usr/local/bin" "${MOCK_CALLS_FILE}"
}
