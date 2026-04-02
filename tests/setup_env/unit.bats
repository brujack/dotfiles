#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ── quiet_which ─────────────────────────────────────────────────────────────

@test "quiet_which returns 0 for a command that exists" {
  run quiet_which bash
  [ "$status" -eq 0 ]
}

@test "quiet_which returns 1 for a command that does not exist" {
  run quiet_which __no_such_command_xyz__
  [ "$status" -eq 1 ]
}

@test "quiet_which produces no output" {
  run quiet_which bash
  [ -z "$output" ]
}

# ── app_dir_exists ───────────────────────────────────────────────────────────

@test "app_dir_exists returns 0 when directory exists" {
  run app_dir_exists "${TMPDIR_TEST}"
  [ "$status" -eq 0 ]
}

@test "app_dir_exists returns 1 when directory does not exist" {
  run app_dir_exists "${TMPDIR_TEST}/nonexistent"
  [ "$status" -eq 1 ]
}

@test "app_dir_exists handles paths with escaped spaces" {
  local dir_with_space="${TMPDIR_TEST}/my app"
  mkdir -p "${dir_with_space}"
  run app_dir_exists "${TMPDIR_TEST}/my\\ app"
  [ "$status" -eq 0 ]
}

# ── process_args ────────────────────────────────────────────────────────────

@test "process_args sets SETUP_USER for -t setup_user" {
  process_args -t setup_user
  [ "${SETUP_USER}" -eq 1 ]
}

@test "process_args sets SETUP for -t setup" {
  process_args -t setup
  [ "${SETUP}" -eq 1 ]
}

@test "process_args sets DEVELOPER for -t developer" {
  process_args -t developer
  [ "${DEVELOPER}" -eq 1 ]
}

@test "process_args sets ANSIBLE for -t ansible" {
  process_args -t ansible
  [ "${ANSIBLE}" -eq 1 ]
}

@test "process_args sets UPDATE for -t update" {
  process_args -t update
  [ "${UPDATE}" -eq 1 ]
}

@test "process_args sets WORK for -w" {
  process_args -t setup -w
  [ "${WORK}" -eq 1 ]
}

# ── version constants ────────────────────────────────────────────────────────

@test "BATS_VER is set and non-empty" {
  [ -n "${BATS_VER}" ]
}

@test "GO_VER is set and non-empty" {
  [ -n "${GO_VER}" ]
}

@test "PYTHON_VER is set and non-empty" {
  [ -n "${PYTHON_VER}" ]
}

@test "RUBY_VER is set and non-empty" {
  [ -n "${RUBY_VER}" ]
}

@test "TERRAFORM_VER matches semver pattern" {
  [[ "${TERRAFORM_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "BATS_VER matches semver pattern" {
  [[ "${BATS_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── usage ────────────────────────────────────────────────────────────────────

@test "usage prints help text and exits 0" {
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"setup_user"* ]]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"developer"* ]]
  [[ "$output" == *"ansible"* ]]
  [[ "$output" == *"update"* ]]
}

# ── prerequisite check ────────────────────────────────────────────────────────

@test "setup_env.sh exits 1 with error when brew is not found" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
}

@test "setup_env.sh prereq error message points to bootstrap_mac.sh" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bootstrap_mac.sh"* ]]
}

@test "setup_env.sh contains bash version prerequisite check" {
  run grep -q 'BASH_VERSINFO' "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 0 ]
}

# ── lib/ source tests ─────────────────────────────────────────────────────────

@test "lib/constants.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/helpers.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/detect_env.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/detect_env.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/macos.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/macos.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/linux.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/linux.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/developer.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/developer.sh'"
  [ "$status" -eq 0 ]
}

# ── logging helpers ───────────────────────────────────────────────────────────
@test "log_info output contains [INFO] prefix" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_info 'test message'"
  [[ "${output}" == *"[INFO]"* ]]
}

@test "log_info output contains the message" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_info 'hello world'"
  [[ "${output}" == *"hello world"* ]]
}

@test "log_warn output contains [WARN] prefix" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_warn 'test warning' 2>&1"
  [[ "${output}" == *"[WARN]"* ]]
}

@test "log_error output contains [ERROR] prefix" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_error 'test error' 2>&1"
  [[ "${output}" == *"[ERROR]"* ]]
}
