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

# F2 fix round: install_cargo_tools prints one "cargo tools: <crate> <ver>
# ok" line per satisfied pin, and _update_write_detail_from_err keeps only
# tail -10 of the merged output -- with several "ok" lines after an early
# failure, that failure's own line can fall out of the retained window
# before the operator reads it. This test exercises the REAL
# install_cargo_tools (via the shared tests/mocks/cargo, not a stub) with
# two crates absent and six present at their pin, so it also regression-
# guards lib/developer.sh's fix directly: the fix appends a final "cargo
# tools: failed: <names>" summary line, guaranteed by position to be the
# newest line in the file and therefore always inside the tail -10 window
# regardless of how many "ok" lines came before it -- removing that line
# (or the fix that produces it) turns this test red even though today's
# 8-pin CARGO_TOOLS array is too short to trigger the truncation itself.
@test "run_update's cargo-tools detail file names both failed crates when several others succeed" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(cat <<'LIST'
cargo-insta v1.47.2:
    cargo-insta
cargo-machete v0.9.2:
    cargo-machete
cargo-mutants v27.0.0:
    cargo-mutants
cargo-semver-checks v0.47.0:
    cargo-semver-checks
cargo-tarpaulin v0.35.2:
    cargo-tarpaulin
cargo-zigbuild v0.22.3:
    cargo-zigbuild
LIST
)"
  # cargo-audit and cargo-deny are absent from the list above, so both
  # trigger a real `cargo install --locked` call through the mock, which
  # fails every install call uniformly via MOCK_CARGO_INSTALL_EXIT.
  export MOCK_CARGO_INSTALL_EXIT=3
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "WARN" ]
  [ -f "${_DOTFILES_RUN_TMPDIR}/detail_cargo-tools" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/detail_cargo-tools")" == *"cargo tools: failed: cargo-audit cargo-deny"* ]]
}

@test "run_update skips cargo-tools ('cargo not found') when install_cargo_tools returns 1 -- no resolvable toolchain is an absence, not a failure" {
  # F1 fix round: a fresh mac has no resolvable cargo (rustup is keg-only
  # and nothing in the macOS install path runs `rustup default`), so this
  # is reachable on real hardware, not just a test fixture. FAIL here would
  # make every future `-t update` on that box exit 1 forever. update_rust
  # already treats the identical condition as a skip ("rustup not found;
  # skipping Rust update"; return 0) -- this test now pins the same
  # behaviour, replacing the prior version that pinned FAIL and therefore
  # encoded the behaviour under question.
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() {
    printf 'cargo not found\n' >&2
    return 1
  }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "SKIP" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_cargo-tools")" = "cargo not found" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" != "FAIL" ]
}

@test "run_update marks cargo-tools WARN, not SKIP or FAIL, when install_cargo_tools returns 2 -- distinct from the rc-1 absence case" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export HAS_RUST=1
  install_cargo_tools() {
    printf 'cargo tools: cargo-tarpaulin install failed\n' >&2
    return 2
  }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" = "WARN" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" != "SKIP" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_cargo-tools")" != "FAIL" ]
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

@test "run_setup_or_developer calls install_cargo_tools AFTER install_macos_packages, not before" {
  # F4 (spec review, low): nothing previously pinned the ordering, and the
  # platform install is what provides cargo (rustup/cargo land via the
  # Brewfile) -- moving the call before install_macos_packages passed all
  # other tests, so only an explicit order log catches a regression. Same
  # order.log + sed -n '1p'/'2p' style as the existing
  # "run_setup_user calls install_git_hooks_all_repos after
  # setup_claude_plugins" test in tests/setup_env/workflows.bats.
  local _log="${BATS_TEST_TMPDIR}/order.log"
  : > "${_log}"
  install_macos_packages() { printf 'macos\n' >> "${_log}"; return 0; }
  install_cargo_tools() { printf 'cargo-tools\n' >> "${_log}"; return 0; }
  run run_setup_or_developer
  [ "$(sed -n '1p' "${_log}")" = "macos" ]
  [ "$(sed -n '2p' "${_log}")" = "cargo-tools" ]
}
