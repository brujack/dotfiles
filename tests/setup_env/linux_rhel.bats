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

# ── install_centos_packages ──────────────────────────────────────────────────

@test "install_centos_packages: calls yum install git" {
  run install_centos_packages
  [ "$status" -eq 0 ]
  grep -q "yum install git" "${MOCK_CALLS_FILE}"
}

@test "install_centos_packages: calls yum install zsh" {
  run install_centos_packages
  [ "$status" -eq 0 ]
  grep -q "yum install zsh" "${MOCK_CALLS_FILE}"
}

# ── install_linux_packages ───────────────────────────────────────────────────

@test "install_linux_packages: clones tfenv when .tfenv does not exist" {
  run install_linux_packages
  [ "$status" -eq 0 ]
  grep -q "git clone.*tfenv" "${MOCK_CALLS_FILE}"
}

@test "install_linux_packages: skips git clone when .tfenv already exists" {
  mkdir -p "${HOME}/.tfenv/bin"
  touch "${HOME}/.tfenv/bin/tfenv"
  run install_linux_packages
  [ "$status" -eq 0 ]
  ! grep -q "git clone.*tfenv" "${MOCK_CALLS_FILE}"
}

@test "install_linux_packages: calls wget for tflint when zip does not exist" {
  run install_linux_packages
  [ "$status" -eq 0 ]
  grep -q "wget.*tflint" "${MOCK_CALLS_FILE}"
}

@test "install_linux_packages: skips wget for tflint when zip already exists" {
  touch "${HOME}/software_downloads/tflint_linux_amd64.zip"
  run install_linux_packages
  [ "$status" -eq 0 ]
  ! grep -q "wget.*tflint" "${MOCK_CALLS_FILE}"
}

@test "install_linux_packages: calls wget for tfsec when file does not exist" {
  run install_linux_packages
  [ "$status" -eq 0 ]
  grep -q "wget.*tfsec" "${MOCK_CALLS_FILE}"
}

@test "install_linux_packages: skips wget for tfsec when file already exists" {
  touch "${HOME}/software_downloads/tfsec-linux-amd64"
  run install_linux_packages
  [ "$status" -eq 0 ]
  ! grep -q "wget.*tfsec" "${MOCK_CALLS_FILE}"
}
