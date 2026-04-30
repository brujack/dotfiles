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
  unset MOCK_BREW_LEAVES
  unset MOCK_BREW_LIST_FORMULA
  unset MOCK_BREW_LIST_CASK
  unset MOCK_BREW_TAPS
  unset MOCK_WHICH_MISSING
  unset MACOS
  unset HAS_DEVTOOLS
  unset HAS_K8S
  unset HAS_DOCKER
  unset HAS_RUST
}

# ── skip gates ────────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: SKIP on Linux (MACOS unset)" {
  # MACOS is already unset in setup(); brew is available (no MOCK_WHICH_MISSING)
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "not applicable on Linux" "${_UPDATE_TMPDIR}/result_brew-drift"
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: SKIP when brew not available" {
  export MACOS=1
  export MOCK_WHICH_MISSING=brew
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "brew not available" "${_UPDATE_TMPDIR}/result_brew-drift"
}

@test "_update_check_brewfile_drift: SKIP when Brewfile not found" {
  export MACOS=1
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/nonexistent_brewfile"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "Brewfile not found" "${_UPDATE_TMPDIR}/result_brew-drift"
}

# ── formula drift ─────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: OK when formulae and taps match" {
  export MACOS=1
  printf 'brew "bat"\nbrew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="bat git"
  export MOCK_BREW_LIST_FORMULA="bat git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  grep -q "formulae clean" "${_UPDATE_TMPDIR}/result_brew-drift"
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK when tap formula in Brewfile matches full-name from brew list" {
  export MACOS=1
  printf 'brew "teamookla/speedtest/speedtest"\ntap "teamookla/speedtest"\n' \
    > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  # brew list --formula --full-name returns tap-qualified name; brew leaves also returns full name
  export MOCK_BREW_LEAVES="teamookla/speedtest/speedtest"
  export MOCK_BREW_LIST_FORMULA="teamookla/speedtest/speedtest"
  export MOCK_BREW_TAPS="teamookla/speedtest"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK when formula is dep of another — not flagged untracked" {
  export MACOS=1
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  # brew leaves returns only top-level installs; openssl/zstd are transitive deps
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git openssl zstd"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK when Brewfile has no brew/tap/cask lines" {
  export MACOS=1
  printf "# comment only\n" > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES=""
  export MOCK_BREW_LIST_FORMULA=""
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
}

@test "_update_check_brewfile_drift: WARN when formula installed but not in Brewfile" {
  export MACOS=1
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git jq"
  export MOCK_BREW_LIST_FORMULA="git jq"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "jq" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when formula in Brewfile but not installed" {
  export MACOS=1
  printf 'brew "git"\nbrew "missing-tool"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "missing-tool" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── tap drift ─────────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: OK when only homebrew auto-taps installed (not untracked)" {
  export MACOS=1
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  # homebrew/bundle, homebrew/cask, homebrew/core, homebrew/services are auto-taps
  # always present — must be filtered, not reported as untracked
  export MOCK_BREW_TAPS="homebrew/bundle homebrew/cask homebrew/core homebrew/services"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: WARN when tap installed but not in Brewfile" {
  export MACOS=1
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS="homebrew/cask-fonts"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked taps" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "tap: homebrew/cask-fonts" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when tap in Brewfile but not installed" {
  export MACOS=1
  printf 'brew "git"\ntap "teamookla/speedtest"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing taps" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "tap: teamookla/speedtest" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── cask drift (macOS only) ───────────────────────────────────────────────────

@test "_update_check_brewfile_drift: WARN when cask installed but not in Brewfile (macOS)" {
  export MACOS=1
  printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK="visual-studio-code warp"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked casks" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "cask: warp" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when cask in Brewfile but not installed (macOS)" {
  export MACOS=1
  printf 'brew "git"\ncask "missing-app"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK=""
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing casks" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "cask: missing-app" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── Linux: casks not checked ──────────────────────────────────────────────────

@test "_update_check_brewfile_drift: SKIP on Linux — no detail file written" {
  # Entire check skipped on Linux; brew and Brewfile presence are irrelevant
  unset MACOS
  printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

# ── mixed drift ───────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: WARN with all drift types in detail file" {
  export MACOS=1
  printf 'brew "git"\ncask "visual-studio-code"\ntap "teamookla/speedtest"\n' \
    > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  # jq: untracked leaf formula; git: clean
  export MOCK_BREW_LEAVES="git jq"
  export MOCK_BREW_LIST_FORMULA="git jq"
  # warp: untracked cask; visual-studio-code: missing cask
  export MOCK_BREW_LIST_CASK="warp"
  # homebrew/cask-fonts: untracked tap; teamookla/speedtest: missing tap
  export MOCK_BREW_TAPS="homebrew/cask-fonts"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "jq" "${_UPDATE_TMPDIR}/detail_brew-drift"
  grep -q "cask: warp" "${_UPDATE_TMPDIR}/detail_brew-drift"
  grep -q "tap: homebrew/cask-fonts" "${_UPDATE_TMPDIR}/detail_brew-drift"
  grep -q "cask: visual-studio-code" "${_UPDATE_TMPDIR}/detail_brew-drift"
  grep -q "tap: teamookla/speedtest" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── capability-filtered drift ─────────────────────────────────────────────────

@test "_update_check_brewfile_drift: OK when tagged formula excluded because capability unset" {
  export MACOS=1
  # postgresql tagged [HAS_DEVTOOLS]; git is untagged
  printf 'brew "git"\nbrew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DEVTOOLS
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: WARN when tagged formula included because capability set" {
  export MACOS=1
  printf 'brew "git"\nbrew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export HAS_DEVTOOLS=1
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "postgresql@14" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: OK when tagged cask excluded because capability unset" {
  export MACOS=1
  printf 'brew "git"\ncask "docker"  # [HAS_DOCKER]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DOCKER
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK=""
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: WARN when tagged cask included because capability set" {
  export MACOS=1
  printf 'brew "git"\ncask "docker"  # [HAS_DOCKER]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export HAS_DOCKER=1
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK=""
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "cask: docker" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: OK when tagged tap excluded because capability unset" {
  export MACOS=1
  printf 'brew "git"\ntap "datawire/blackbird"  # [HAS_K8S]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_K8S
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK untagged entries still checked regardless of capabilities" {
  export MACOS=1
  # git is untagged — always in expected set; not installed → WARN
  printf 'brew "git"\nbrew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DEVTOOLS
  export MOCK_BREW_LEAVES=""
  export MOCK_BREW_LIST_FORMULA=""
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "git" "${_UPDATE_TMPDIR}/detail_brew-drift"
  # postgresql excluded by tag — must NOT appear in missing list
  ! grep -q "postgresql" "${_UPDATE_TMPDIR}/detail_brew-drift"
}
