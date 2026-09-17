#!/usr/bin/env bats
# Coverage for wiring install_cargo_tools into run_setup_or_developer and the
# run_update "cargo-tools" section (plan Task 7). See
# docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md Part 3.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  # load_setup_env sources real detect_env(), which sets HAS_AWS=1 and
  # HAS_RUST=1 for real on this box's actual profile (mac_workstation) --
  # nothing about that is a test fixture. Unset both here, at setup() scope
  # rather than per-test (tdd.md pitfall E2), so every test controls
  # HAS_RUST explicitly instead of inheriting the operator's real machine.
  unset HAS_AWS HAS_RUST
  # Same PYENV_ROOT isolation as tests/setup_env/workflows.bats -- run_update
  # reaches the pyenv-shims section too, and this box has a real ~/.pyenv.
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
  # Nothing in this file manipulates PATH, so load_mocks' PATH prepend
  # already keeps ensure_state_ledger's git clone/pull on the mock. DRY_RUN=1
  # is defense in depth per the dispatch warning regardless.
  export DRY_RUN=1
}

teardown() {
  :
}

# ── run_update: cargo-tools section ────────────────────────────────────────

@test "run_update records a non-SKIP cargo-tools status under --brew-only" {
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() { return 0; }
  run_update
  [ -f "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" != "SKIP" ]
}

@test "run_update skips cargo-tools under --pip-only" {
  export UPDATE_PIP=1
  unset UPDATE_BREW UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() { return 0; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "SKIP" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_cargo-tools")" = "flag not set" ]
}

@test "run_update skips cargo-tools with its reason when HAS_RUST is unset" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  unset HAS_RUST
  install_cargo_tools() { return 0; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "SKIP" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_cargo-tools")" = "HAS_RUST not set" ]
  # the regression this test exists for -- an unset HAS_RUST must never
  # render [OK]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" != "OK" ]
}

@test "run_update marks cargo-tools WARN with detail when install_cargo_tools returns 2" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() {
    printf 'cargo tools: cargo-tarpaulin install failed\n' >&2
    return 2
  }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "WARN" ]
  [ -f "${_DOTFILES_RUN_TMPDIR}/detail_cargo-tools" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/detail_cargo-tools")" == *"cargo-tarpaulin"* ]]
}

@test "run_update marks cargo-tools FAIL when install_cargo_tools returns 1" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() {
    printf 'cargo not found\n' >&2
    return 1
  }
  # run_update's overall status is 1 when any section FAILs (_update_summary
  # returns $(( _fail > 0 ))), so this needs `run` -- a bare call would abort
  # the test body under bats' own set -e semantics. `run` forks a subshell,
  # so exports made inside run_update (including _DOTFILES_RUN_TMPDIR) don't
  # survive back into this test body -- assert on the printed summary row
  # instead of reading status_cargo-tools, same as the git-hooks FAIL test.
  run run_update
  [[ "$output" == *"[FAIL] cargo-tools"* ]]
}

@test "run_update marks cargo-tools OK when install_cargo_tools returns 0" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() { return 0; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "OK" ]
}

# ── run_setup_or_developer: calls install_cargo_tools ─────────────────────

@test "run_setup_or_developer calls install_cargo_tools" {
  install_macos_packages() { return 0; }
  local _marker="${BATS_TEST_TMPDIR}/cargo_tools.ran"
  install_cargo_tools() { touch "${_marker}"; return 0; }
  run run_setup_or_developer
  [ -f "${_marker}" ]
}

@test "run_setup_or_developer does not abort when install_cargo_tools fails" {
  install_macos_packages() { return 0; }
  install_cargo_tools() { return 1; }
  run run_setup_or_developer
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo tools incomplete"* ]]
}
