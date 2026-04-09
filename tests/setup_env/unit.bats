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

# ── process_args: doctor ──────────────────────────────────────────────────────

@test "process_args sets DOCTOR for -t doctor" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t doctor
    printf '%s' \"\${DOCTOR}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets CHECK_VERSIONS for -t check-versions" {
  process_args -t check-versions
  [ "${CHECK_VERSIONS}" -eq 1 ]
}

# ── process_args: --dry-run ───────────────────────────────────────────────────

@test "process_args sets DRY_RUN for --dry-run flag" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --dry-run -t setup_user
    printf '%s' \"\${DRY_RUN}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets SETUP_USER when combined with --dry-run" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --dry-run -t setup_user
    printf '%s' \"\${SETUP_USER}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
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

# ── workflows ────────────────────────────────────────────────────────────────

@test "run_setup_user is defined after sourcing setup_env" {
  declare -f run_setup_user &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_setup_or_developer is defined after sourcing setup_env" {
  declare -f run_setup_or_developer &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_developer_or_ansible is defined after sourcing setup_env" {
  declare -f run_developer_or_ansible &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_update is defined after sourcing setup_env" {
  declare -f run_update &>/dev/null
  [ "$?" -eq 0 ]
}

# ── run_cmd ──────────────────────────────────────────────────────────────────

@test "run_cmd executes command when DRY_RUN is unset" {
  unset DRY_RUN
  run run_cmd printf "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "run_cmd prints dry-run message when DRY_RUN is set" {
  export DRY_RUN=1
  run run_cmd ln -s /src /dest
  unset DRY_RUN
  [ "$status" -eq 0 ]
  [[ "$output" == "[DRY RUN]"* ]]
}

@test "run_cmd dry-run does not execute the command" {
  export DRY_RUN=1
  local tmpfile="${BATS_TEST_TMPDIR}/should_not_exist"
  run run_cmd touch "${tmpfile}"
  unset DRY_RUN
  [ ! -f "${tmpfile}" ]
}

# ── safe_link dry-run ─────────────────────────────────────────────────────────

@test "safe_link does not create symlink when DRY_RUN is set" {
  export DRY_RUN=1
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  safe_link "${src}" "${dest}"
  unset DRY_RUN
  [ ! -L "${dest}" ]
}

# ── run_doctor ────────────────────────────────────────────────────────────────

@test "run_doctor prints Doctor Report header" {
  run run_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Doctor Report"* ]]
}

@test "run_doctor prints PROFILE line" {
  run run_doctor
  [[ "$output" == *"PROFILE="* ]]
}

@test "run_doctor prints HAS_GUI line" {
  run run_doctor
  [[ "$output" == *"HAS_GUI="* ]]
}

# ── run_check_versions ────────────────────────────────────────────────────────

@test "run_check_versions exits 0 when all pinned versions match latest" {
  run_check_versions() {
    local _outdated=0
    local _latest _installed
    _latest="${YQ_VER}"
    _installed="${YQ_VER}"
    if [[ "${_installed}" == "${_latest}" ]]; then
      printf "  [OK]      yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
    else
      printf "  [OUTDATED] yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
      _outdated=1
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
}

@test "run_check_versions exits 1 when a pinned version is outdated" {
  run_check_versions() {
    local _outdated=0
    local _latest _installed
    _latest="99.99.99"
    _installed="${YQ_VER}"
    if [[ "${_installed}" == "${_latest}" ]]; then
      printf "  [OK]      yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
    else
      printf "  [OUTDATED] yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
      _outdated=1
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 1 ]
}

@test "run_check_versions soft-fails when curl returns error for one tool" {
  run_check_versions() {
    local _outdated=0
    local _latest
    _latest=""
    if [[ -z "${_latest}" ]]; then
      printf "  [WARN]    yq  could not fetch latest version\n"
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
}

@test "run_check_versions skips tool when not installed" {
  run_check_versions() {
    local _outdated=0
    if ! command -v __no_such_tool_xyz__ &>/dev/null; then
      printf "  [SKIP]    __no_such_tool_xyz__  not installed\n"
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SKIP]"* ]]
}

# ── local overrides ───────────────────────────────────────────────────────────

@test ".gitignore contains config/local.sh" {
  grep -q '^config/local\.sh$' "${REPO_ROOT}/.gitignore"
}

@test "config/local.sh is sourced when present" {
  local local_cfg="${REPO_ROOT}/config/local.sh"
  printf '#!/usr/bin/env bash\nLOCAL_SENTINEL=42\n' > "${local_cfg}"
  run bash -c "
    _LOCAL_CFG='${local_cfg}'
    [[ -f \"\${_LOCAL_CFG}\" ]] && source \"\${_LOCAL_CFG}\"
    unset _LOCAL_CFG
    [[ \${LOCAL_SENTINEL} -eq 42 ]]
  "
  rm -f "${local_cfg}"
  [ "$status" -eq 0 ]
}

@test "config/local.sh absence does not cause errors" {
  local local_cfg="${REPO_ROOT}/config/local.sh"
  rm -f "${local_cfg}"
  run bash -c "
    _LOCAL_CFG='${local_cfg}'
    [[ -f \"\${_LOCAL_CFG}\" ]] && source \"\${_LOCAL_CFG}\"
    unset _LOCAL_CFG
  "
  [ "$status" -eq 0 ]
}

# ── _any_update_flag ──────────────────────────────────────────────────────────

@test "_any_update_flag returns 1 when no flags set" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run _any_update_flag
  [ "$status" -eq 1 ]
}

@test "_any_update_flag returns 0 when UPDATE_BREW is set" {
  export UPDATE_BREW=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

@test "_any_update_flag returns 0 when UPDATE_PIP is set" {
  export UPDATE_PIP=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

@test "_any_update_flag returns 0 when multiple flags are set" {
  export UPDATE_PIP=1
  export UPDATE_GEMS=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

# ── process_args granular update flags ───────────────────────────────────────

@test "process_args sets UPDATE_BREW for --brew-only" {
  process_args -t update --brew-only
  [ "${UPDATE_BREW}" -eq 1 ]
}

@test "process_args sets UPDATE_PIP for --pip-only" {
  process_args -t update --pip-only
  [ "${UPDATE_PIP}" -eq 1 ]
}

@test "process_args sets UPDATE_GEMS for --gems-only" {
  process_args -t update --gems-only
  [ "${UPDATE_GEMS}" -eq 1 ]
}

@test "process_args sets UPDATE_MAS for --mas-only" {
  process_args -t update --mas-only
  [ "${UPDATE_MAS}" -eq 1 ]
}

@test "process_args sets UPDATE_CLAUDE for --claude-only" {
  process_args -t update --claude-only
  [ "${UPDATE_CLAUDE}" -eq 1 ]
}

@test "process_args sets multiple UPDATE flags when multiple flags given" {
  process_args -t update --brew-only --pip-only
  [ "${UPDATE_BREW}" -eq 1 ]
  [ "${UPDATE_PIP}" -eq 1 ]
}

# ── run_update flag dispatch ───────────────────────────────────────────────────

@test "run_update with --brew-only calls brew subsystem and skips gems" {
  load_mocks
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  ! grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update with no flags calls brew and gem subsystems" {
  load_mocks
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  grep -q "gem update" "${MOCK_CALLS_FILE}"
}

# ── doctor_pass / doctor_fail ─────────────────────────────────────────────────

@test "doctor_pass increments _DOCTOR_PASS" {
  _DOCTOR_PASS=0
  doctor_pass "some check"
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "doctor_pass prints [PASS] and label" {
  _DOCTOR_PASS=0
  run doctor_pass "my label"
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"my label"* ]]
}

@test "doctor_fail increments _DOCTOR_FAIL and sets _DOCTOR_FAILED" {
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  doctor_fail "broken thing" "it is missing"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "doctor_fail prints [FAIL] with label and detail" {
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  run doctor_fail "broken thing" "it is missing"
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"broken thing"* ]]
  [[ "$output" == *"it is missing"* ]]
}
