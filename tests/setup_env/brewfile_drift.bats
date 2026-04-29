#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export _UPDATE_TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset MACOS
  unset MOCK_WHICH_MISSING
}

teardown() {
  unset _OVERRIDE_BREWFILE_PATH
  unset MOCK_BREW_LIST_FORMULA
  unset MOCK_BREW_LIST_CASK
  unset MOCK_BREW_TAPS
  unset MOCK_WHICH_MISSING
  unset MACOS
}

# ── skip gates ────────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: SKIP when brew not available" {
  export MOCK_WHICH_MISSING=brew
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "brew not available" "${_UPDATE_TMPDIR}/result_brew-drift"
}

@test "_update_check_brewfile_drift: SKIP when Brewfile not found" {
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/nonexistent_brewfile"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "Brewfile not found" "${_UPDATE_TMPDIR}/result_brew-drift"
}

# ── formula drift ─────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: OK when formulae and taps match" {
  printf 'brew "bat"\nbrew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="bat git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  grep -q "formulae clean" "${_UPDATE_TMPDIR}/result_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when formula installed but not in Brewfile" {
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git jq"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "jq" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when formula in Brewfile but not installed" {
  printf 'brew "git"\nbrew "missing-tool"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "missing-tool" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── tap drift ─────────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: WARN when tap installed but not in Brewfile" {
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS="homebrew/cask-fonts"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked taps" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "tap: homebrew/cask-fonts" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when tap in Brewfile but not installed" {
  printf 'brew "git"\ntap "teamookla/speedtest"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing taps" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "tap: teamookla/speedtest" "${_UPDATE_TMPDIR}/detail_brew-drift"
}
