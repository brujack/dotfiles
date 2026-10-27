#!/usr/bin/env bats

# -t update sections that do nothing must read SKIP with a reason, never OK: an OK
# row for a section that never ran says the machine is current when nothing checked.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  # detect_env exports the real profile's HAS_* flags; each test sets its own.
  unset HAS_AWS HAS_RUST
  unset PYENV_ROOT
  export _OVERRIDE_PYENV_ROOT="${BATS_TEST_TMPDIR}/pyenv"
  export HOME="${BATS_TEST_TMPDIR}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  export TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MACOS=1
  unset LINUX UBUNTU
  export DRY_RUN=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  CALLS="${BATS_TEST_TMPDIR}/fn_calls"
  : > "${CALLS}"
  # Recording stubs: the section under test must not call these when it skips.
  update_aws_cli() { printf 'update_aws_cli\n' >> "${CALLS}"; return 0; }
  update_rust() { printf 'update_rust\n' >> "${CALLS}"; return 0; }
}

_status() { cat "${_DOTFILES_RUN_TMPDIR}/status_$1"; }
_result() { cat "${_DOTFILES_RUN_TMPDIR}/result_$1"; }

# ── mas ──────────────────────────────────────────────────────────────────────

@test "test_bug_update_noop_skip: mas on Linux is SKIP, not OK, and mas is never called" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export UPDATE_MAS=1
  run_update
  [ "$(_status mas)" = "SKIP" ]
  [ "$(_result mas)" = "not macOS" ]
  [ "$(grep -c '^mas ' "${MOCK_CALLS_FILE}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: mas on macOS still runs and reads OK" {
  export UPDATE_MAS=1
  run_update
  [ "$(_status mas)" = "OK" ]
  grep -q '^mas upgrade' "${MOCK_CALLS_FILE}"
}

# ── aws ──────────────────────────────────────────────────────────────────────

@test "test_bug_update_noop_skip: aws with HAS_AWS unset is SKIP and update_aws_cli is not called" {
  run_update
  [ "$(_status aws)" = "SKIP" ]
  [ "$(_result aws)" = "HAS_AWS not set" ]
  [ "$(grep -c '^update_aws_cli$' "${CALLS}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: aws on neither macOS nor Linux is SKIP" {
  export HAS_AWS=1
  unset MACOS LINUX UBUNTU
  run_update
  [ "$(_status aws)" = "SKIP" ]
  [ "$(_result aws)" = "not applicable" ]
  [ "$(grep -c '^update_aws_cli$' "${CALLS}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: aws with HAS_AWS on macOS runs update_aws_cli" {
  export HAS_AWS=1
  run_update
  [ "$(_status aws)" = "OK" ]
  [ "$(grep -c '^update_aws_cli$' "${CALLS}")" -eq 1 ]
}

# ── rust ─────────────────────────────────────────────────────────────────────

@test "test_bug_update_noop_skip: rust with HAS_RUST unset is SKIP and update_rust is not called" {
  run_update
  [ "$(_status rust)" = "SKIP" ]
  [ "$(_result rust)" = "HAS_RUST not set" ]
  [ "$(grep -c '^update_rust$' "${CALLS}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: rust on neither macOS nor Ubuntu is SKIP" {
  export HAS_RUST=1
  unset MACOS UBUNTU
  export LINUX=1
  run_update
  [ "$(_status rust)" = "SKIP" ]
  [ "$(_result rust)" = "not applicable" ]
  [ "$(grep -c '^update_rust$' "${CALLS}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: rust with no resolvable rustup is SKIP" {
  export HAS_RUST=1
  _resolve_rustup() { return 1; }
  run_update
  [ "$(_status rust)" = "SKIP" ]
  [ "$(_result rust)" = "rustup not found" ]
  [ "$(grep -c '^update_rust$' "${CALLS}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: rust with a rustup runs update_rust and reads OK" {
  export HAS_RUST=1
  _resolve_rustup() { printf '/fake/rustup\n'; }
  run_update
  [ "$(_status rust)" = "OK" ]
  [ "$(grep -c '^update_rust$' "${CALLS}")" -eq 1 ]
}

# ── terraform-skill ──────────────────────────────────────────────────────────

@test "test_bug_update_noop_skip: terraform-skill over a path that is not a git checkout is SKIP" {
  mkdir -p "${HOME}/.cursor/skills/terraform-skill"
  export UPDATE_CLAUDE=1
  run_update
  [ "$(_status terraform-skill)" = "SKIP" ]
  [ "$(_result terraform-skill)" = "not a git checkout — reinstall to enable updates" ]
  [ "$(grep -cE '^git .*terraform-skill' "${MOCK_CALLS_FILE}")" -eq 0 ]
}

@test "test_bug_update_noop_skip: terraform-skill checkout is pulled and reads OK" {
  mkdir -p "${HOME}/.cursor/skills/terraform-skill/.git"
  export UPDATE_CLAUDE=1
  run_update
  [ "$(_status terraform-skill)" = "OK" ]
  grep -qE '^git -C .*terraform-skill pull --ff-only' "${MOCK_CALLS_FILE}"
}
