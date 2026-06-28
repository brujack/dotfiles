#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}"
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

@test "_update_check_brewfile_drift: Linux SKIP when brew not available" {
  unset MACOS
  export MOCK_WHICH_MISSING=brew
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "brew not available" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: Linux OK when formulae and taps match (no cask check)" {
  unset MACOS
  printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  grep -q "formulae clean" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  ! grep -q "casks clean" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: SKIP when brew not available" {
  export MACOS=1
  export MOCK_WHICH_MISSING=brew
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "brew not available" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
}

@test "_update_check_brewfile_drift: SKIP when Brewfile not found" {
  export MACOS=1
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/nonexistent_brewfile"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "Brewfile not found" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  grep -q "formulae clean" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked formulae" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "jq" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing formulae" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "missing-tool" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked taps" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "tap: homebrew/cask-fonts" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing taps" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "tap: teamookla/speedtest" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked casks" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "cask: warp" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing casks" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "cask: missing-app" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
}

# ── Linux: casks not checked ──────────────────────────────────────────────────

@test "_update_check_brewfile_drift: Linux WARN for formula drift (cask entries ignored)" {
  # On Linux: formula/tap drift detected; cask entries in Brewfile are invisible
  unset MACOS
  printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LEAVES="git jq"
  export MOCK_BREW_LIST_FORMULA="git jq"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked formulae" "${_DOTFILES_RUN_TMPDIR}/result_brew-drift"
  grep -q "jq" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
  ! grep -q "cask" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "jq" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
  grep -q "cask: warp" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
  grep -q "tap: homebrew/cask-fonts" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
  grep -q "cask: visual-studio-code" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
  grep -q "tap: teamookla/speedtest" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK when tagged formula installed but capability unset — not untracked" {
  export MACOS=1
  # postgresql is tagged [HAS_DEVTOOLS] and IS installed — must not appear as untracked
  printf 'brew "git"\nbrew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DEVTOOLS
  export MOCK_BREW_LEAVES="git postgresql@14"
  export MOCK_BREW_LIST_FORMULA="git postgresql@14"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "postgresql@14" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK when tagged cask installed but capability unset — not untracked" {
  export MACOS=1
  printf 'brew "git"\ncask "docker"  # [HAS_DOCKER]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DOCKER
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK="docker"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "cask: docker" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
}

@test "_update_check_brewfile_drift: OK when tagged tap installed but capability unset — not untracked" {
  export MACOS=1
  printf 'brew "git"\ntap "datawire/blackbird"  # [HAS_K8S]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_K8S
  export MOCK_BREW_LEAVES="git"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS="datawire/blackbird"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "OK" ]
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift" ]
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
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "git" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
  # postgresql excluded by tag — must NOT appear in missing list
  ! grep -q "postgresql" "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
}

# ── _brewfile_extract_cap ─────────────────────────────────────────────────────

@test "_brewfile_extract_cap returns capability name from tagged line" {
  run _brewfile_extract_cap 'brew "lens"  # [HAS_K8S]'
  [ "$status" -eq 0 ]
  [ "$output" = "HAS_K8S" ]
}

@test "_brewfile_extract_cap returns empty when line has no tag" {
  run _brewfile_extract_cap 'brew "git"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_brewfile_extract_cap returns empty when tag is lowercase (not a valid cap)" {
  run _brewfile_extract_cap 'brew "foo"  # [lowercase]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_brewfile_extract_cap returns cap name containing digits" {
  run _brewfile_extract_cap 'brew "go"  # [HAS_GO119]'
  [ "$status" -eq 0 ]
  [ "$output" = "HAS_GO119" ]
}

@test "_brewfile_extract_cap returns empty for empty input" {
  run _brewfile_extract_cap ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── _brewfile_parse_section ───────────────────────────────────────────────────

@test "_brewfile_parse_section brew: includes untagged formula" {
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  run _brewfile_parse_section brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "_brewfile_parse_section brew: includes formula when capability is active" {
  printf 'brew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export HAS_DEVTOOLS=1
  run _brewfile_parse_section brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "postgresql@14" ]
}

@test "_brewfile_parse_section brew: excludes formula when capability is inactive" {
  printf 'brew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DEVTOOLS
  run _brewfile_parse_section brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_brewfile_parse_section brew: does not return cask entries" {
  printf 'brew "git"\ncask "docker"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  run _brewfile_parse_section brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
  [[ "$output" != *"docker"* ]]
}

@test "_brewfile_parse_section cask: includes untagged cask" {
  printf 'cask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  run _brewfile_parse_section cask "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "visual-studio-code" ]
}

@test "_brewfile_parse_section cask: excludes cask when capability is inactive" {
  printf 'cask "lens"  # [HAS_K8S]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_K8S
  run _brewfile_parse_section cask "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_brewfile_parse_section tap: includes untagged tap" {
  printf 'tap "homebrew/cask-fonts"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  run _brewfile_parse_section tap "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "homebrew/cask-fonts" ]
}

@test "_brewfile_parse_section tap: excludes tap when capability is inactive" {
  printf 'tap "datawire/blackbird"  # [HAS_K8S]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_K8S
  run _brewfile_parse_section tap "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── _brewfile_parse_inactive ──────────────────────────────────────────────────

@test "_brewfile_parse_inactive brew: returns formula when capability is inactive" {
  printf 'brew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_DEVTOOLS
  run _brewfile_parse_inactive brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "postgresql@14" ]
}

@test "_brewfile_parse_inactive brew: excludes formula when capability is active" {
  printf 'brew "postgresql@14"  # [HAS_DEVTOOLS]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export HAS_DEVTOOLS=1
  run _brewfile_parse_inactive brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_brewfile_parse_inactive brew: excludes untagged formula" {
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  run _brewfile_parse_inactive brew "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_brewfile_parse_inactive cask: returns cask when capability is inactive" {
  printf 'cask "lens"  # [HAS_K8S]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_K8S
  run _brewfile_parse_inactive cask "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "lens" ]
}

@test "_brewfile_parse_inactive tap: returns tap when capability is inactive" {
  printf 'tap "datawire/blackbird"  # [HAS_K8S]\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  unset HAS_K8S
  run _brewfile_parse_inactive tap "${BATS_TEST_TMPDIR}/Brewfile"
  [ "$status" -eq 0 ]
  [ "$output" = "datawire/blackbird" ]
}
