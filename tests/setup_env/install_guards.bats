#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_BATS_VER="${BATS_VER}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
  rm -rf "/tmp/bats-core-${BATS_VER}" "/tmp/bats.tar.gz"
}

# ── brew_formula_installed ───────────────────────────────────────────────────

@test "brew_formula_installed returns 0 when formula is listed" {
  export MOCK_BREW_LIST_FORMULA="git wget"
  run brew_formula_installed git
  [ "$status" -eq 0 ]
}

@test "brew_formula_installed returns 1 when formula is not listed" {
  export MOCK_BREW_LIST_FORMULA="wget"
  run brew_formula_installed git
  [ "$status" -eq 1 ]
}

@test "brew_formula_installed uses full-name flag for tap-qualified formulas" {
  export MOCK_BREW_LIST_FORMULA="hashicorp/tap/vault"
  run brew_formula_installed hashicorp/tap/vault
  [ "$status" -eq 0 ]
  grep -q "brew list --formula --full-name" "${MOCK_CALLS_FILE}"
}

# ── brew_cask_installed ──────────────────────────────────────────────────────

@test "brew_cask_installed returns 0 when cask is listed" {
  export MOCK_BREW_LIST_CASK="docker firefox"
  run brew_cask_installed docker
  [ "$status" -eq 0 ]
}

@test "brew_cask_installed returns 1 when cask is not listed" {
  export MOCK_BREW_LIST_CASK="firefox"
  run brew_cask_installed docker
  [ "$status" -eq 1 ]
}

# ── brew_install_formula ─────────────────────────────────────────────────────

@test "brew_install_formula calls brew install when formula is absent" {
  export MOCK_BREW_LIST_FORMULA=""
  run brew_install_formula git
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

@test "brew_install_formula does not call brew install when formula is present" {
  export MOCK_BREW_LIST_FORMULA="git"
  run brew_install_formula git
  [ "$status" -eq 0 ]
  ! grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

# ── brew_tap_if_missing ──────────────────────────────────────────────────────

@test "brew_tap_if_missing calls brew tap when tap is absent" {
  export MOCK_BREW_TAPS=""
  run brew_tap_if_missing hashicorp/tap
  [ "$status" -eq 0 ]
  grep -q "brew tap hashicorp/tap" "${MOCK_CALLS_FILE}"
}

@test "brew_tap_if_missing does not call brew tap when tap is present" {
  export MOCK_BREW_TAPS="hashicorp/tap"
  run brew_tap_if_missing hashicorp/tap
  [ "$status" -eq 0 ]
  # Only one call: the listing call, not a tap add call
  count=$(grep -c "brew tap" "${MOCK_CALLS_FILE}")
  [ "$count" -eq 1 ]
  grep -q "brew tap$" "${MOCK_CALLS_FILE}"
}

# ── install_bats ─────────────────────────────────────────────────────────────

@test "install_bats skips install when bats is already present" {
  unset MOCK_WHICH_MISSING  # which finds bats normally
  export UBUNTU=1
  run install_bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "apt-get" "${MOCK_CALLS_FILE}"
}

@test "install_bats on Ubuntu calls apt-get install when bats is absent" {
  export MOCK_WHICH_MISSING=bats
  export UBUNTU=1
  unset REDHAT CENTOS FEDORA
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
}

@test "install_bats on RHEL downloads bats-core tarball from GitHub" {
  export MOCK_WHICH_MISSING=bats
  export REDHAT=1
  unset UBUNTU CENTOS FEDORA
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "curl.*bats-core.*${BATS_VER}.*tar.gz" "${MOCK_CALLS_FILE}"
}

@test "install_bats returns 1 on unsupported platform" {
  export MOCK_WHICH_MISSING=bats
  unset UBUNTU REDHAT CENTOS FEDORA
  run install_bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported platform"* ]]
}

# ── ensure_not_root ──────────────────────────────────────────────────────────

@test "ensure_not_root returns 0 when not root" {
  export MOCK_ID_U=1000
  run ensure_not_root
  [ "$status" -eq 0 ]
}

@test "ensure_not_root returns 1 and prints message when root" {
  export MOCK_ID_U=0
  run ensure_not_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot run as root"* ]]
}

# ── brew_tap_installed ───────────────────────────────────────────────────────

@test "brew_tap_installed returns 0 when tap is listed" {
  export MOCK_ID_U=1000
  export MOCK_BREW_TAPS="hashicorp/tap homebrew/cask-versions"
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 0 ]
}

@test "brew_tap_installed returns 1 when tap is not listed" {
  export MOCK_ID_U=1000
  export MOCK_BREW_TAPS=""
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 1 ]
}

# ── brew_install_cask ────────────────────────────────────────────────────────

@test "brew_install_cask calls brew install --cask when cask is absent" {
  export MOCK_ID_U=1000
  export MOCK_BREW_LIST_CASK=""
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  grep -q "brew install --cask --force --overwrite docker" "${MOCK_CALLS_FILE}"
}

@test "brew_install_cask does not call brew install when cask is present" {
  export MOCK_ID_U=1000
  export MOCK_BREW_LIST_CASK="docker"
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  ! grep -q "brew install --cask" "${MOCK_CALLS_FILE}"
}

# ── rhel_installed_package ───────────────────────────────────────────────────

@test "rhel_installed_package returns 1 when yum is not available" {
  # Source without mocks in PATH so command -v yum fails on macOS
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${clean_path}'
    source '${REPO_ROOT}/setup_env.sh'
    rhel_installed_package zsh
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"yum command not found"* ]]
}

@test "rhel_installed_package returns 0 when yum reports package installed" {
  export MOCK_YUM_LIST_EXIT=0
  run rhel_installed_package zsh
  [ "$status" -eq 0 ]
}

@test "rhel_installed_package returns 1 when yum reports package not installed" {
  export MOCK_YUM_LIST_EXIT=1
  run rhel_installed_package zsh
  [ "$status" -eq 1 ]
}
