#!/usr/bin/env bats
#
# load_mocks used to prepend tests/mocks to PATH before its own chmod/cp calls,
# so those resolved to the logging mocks and appended lines to MOCK_CALLS_FILE,
# which defaults to the shared /tmp/mock_calls. Every test calling load_mocks
# leaked into that one file. The prepend must be load_mocks' last statement.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "${BATS_TEST_DIRNAME}/helpers/common.bash"
  # load_mocks' last cp resolves to tests/mocks/cp once tests/mocks leads PATH,
  # and that mock logs to the shared /tmp/mock_calls unless this is set.
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
}

@test "load_mocks writes no mock log and leaves tests/mocks first on PATH" {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/calls"
  : > "${MOCK_CALLS_FILE}"
  load_mocks
  if [[ -s ${MOCK_CALLS_FILE} ]]; then
    cat "${MOCK_CALLS_FILE}" >&2
    return 1
  fi
  [ "${PATH%%:*}" = "${REPO_ROOT}/tests/mocks" ]
}

@test "load_mocks: the five stub seams point at tracked, executable files under tests/stubs" {
  local _pair _var _name _first
  load_mocks
  for _pair in _BREW_AZ_BIN:brew-az _BREW_BIN:brew-stub _SYSCTL_BIN:sysctl-stub \
    _SYSTEMCTL_BIN:systemctl-stub _FINDMNT_BIN:findmnt-stub; do
    _var="${_pair%%:*}"
    _name="${_pair#*:}"
    [ "${!_var}" = "${REPO_ROOT}/tests/stubs/${_name}" ]
    [[ -x ${!_var} ]]
    IFS= read -r _first < "${!_var}"
    [ "${_first}" = "#!/usr/bin/env bash" ]
  done
}

@test "load_mocks: the call-recording stubs append to MOCK_CALLS_FILE" {
  local _var _name
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/calls"
  : > "${MOCK_CALLS_FILE}"
  for _var in _BREW_AZ_BIN _SYSCTL_BIN _SYSTEMCTL_BIN _FINDMNT_BIN; do
    run "${!_var}" probe-arg
    [ "${status}" -eq 0 ]
  done
  for _name in brew-az sysctl systemctl findmnt; do
    grep -qx "${_name} probe-arg" "${MOCK_CALLS_FILE}"
  done
}

@test "load_mocks: the brew stub logs argv to BATS_TEST_TMPDIR/brew-calls and prints nothing" {
  load_mocks
  run "${_BREW_BIN}" x y
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "$(cat "${BATS_TEST_TMPDIR}/brew-calls")" = "x y" ]
}

@test "load_mocks: execs no cat or chmod and exactly one mkdir" {
  # The ai-config fixture is built only under LOAD_MOCKS_AI_CONFIG=1 and would
  # add its own mkdir, so with the opt-in unset load_mocks' one mkdir is the count.
  unset LOAD_MOCKS_AI_CONFIG
  local _shim="${BATS_TEST_TMPDIR}/execshim" _c _real
  mkdir -p "${_shim}"
  for _c in mkdir cat chmod; do
    _real="$(command -v "${_c}")"
    printf '#!/usr/bin/env bash\nprintf "%s\\n" >> "%s"\nexec "%s" "$@"\n' \
      "${_c}" "${BATS_TEST_TMPDIR}/execlog" "${_real}" > "${_shim}/${_c}"
    chmod +x "${_shim}/${_c}"
  done
  : > "${BATS_TEST_TMPDIR}/execlog"
  PATH="${_shim}:${PATH}"
  load_mocks
  [ "$(grep -c '^cat$' "${BATS_TEST_TMPDIR}/execlog")" -eq 0 ]
  [ "$(grep -c '^chmod$' "${BATS_TEST_TMPDIR}/execlog")" -eq 0 ]
  [ "$(grep -c '^mkdir$' "${BATS_TEST_TMPDIR}/execlog")" -eq 1 ]
}

@test "load_mocks: _AI_CONFIG_GIT is the real git for every placement of tests/mocks on PATH" {
  local _m="${REPO_ROOT}/tests/mocks" _shape _expected _got
  _expected="$(PATH=/usr/bin:/bin command -v git)"
  for _shape in "${_m}:/usr/bin:/bin" "/usr/bin:${_m}:/bin" "/usr/bin:/bin:${_m}" \
    "${_m}:${_m}:/usr/bin:/bin" ":/usr/bin:${_m}:/bin" "/usr/bin:${_m}:/bin:"; do
    _got="$(PATH="${_shape}"; load_mocks && printf '%s' "${_AI_CONFIG_GIT}")"
    if [[ ${_got} != "${_expected}" ]]; then
      printf 'shape %s gave %s, want %s\n' "${_shape}" "${_got}" "${_expected}" >&2
      return 1
    fi
  done
}

@test "load_mocks: returns 1 with a message when tests/mocks is the only PATH entry" {
  local _out _rc=0
  _out="$(PATH="${REPO_ROOT}/tests/mocks" load_mocks 2>&1)" || _rc=$?
  [ "${_rc}" -eq 1 ]
  [[ ${_out} == *"load_mocks: no real git outside tests/mocks on PATH"* ]]
}

@test "load_mocks: without LOAD_MOCKS_AI_CONFIG the ai-config dir is a missing, self-describing path" {
  unset LOAD_MOCKS_AI_CONFIG
  load_mocks
  [ "${_OVERRIDE_AI_CONFIG_DIR}" = "${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1" ]
  [ ! -e "${_OVERRIDE_AI_CONFIG_DIR}" ]
}

@test "load_mocks: with LOAD_MOCKS_AI_CONFIG=1 the ai-config dir is a tracked fixture under BATS_TEST_TMPDIR" {
  export LOAD_MOCKS_AI_CONFIG=1
  load_setup_env
  load_mocks
  [[ ${_OVERRIDE_AI_CONFIG_DIR} == "${BATS_TEST_TMPDIR}/"* ]]
  run _ai_config_tracked_items "${_OVERRIDE_AI_CONFIG_DIR}" .claude
  [ "${status}" -eq 0 ]
  [ "${output}" = "settings.json" ]
}

@test "every bats file calling run_setup_user or setup_dotfile_symlinks opts in or overrides the ai-config dir" {
  # A per-test stub redefinition is deliberately not an exemption: workflows.bats
  # stubs setup_dotfile_symlinks in one test but its other tests need the fixture.
  local _file _bad=0 _callers=() _lines
  while IFS= read -r _file; do
    _lines="$(grep -E '^[[:space:]]*(run[[:space:]]+)?(run_setup_user|setup_dotfile_symlinks)([[:space:]]|$)' "${REPO_ROOT}/${_file}" || true)"
    [[ -n ${_lines} ]] || continue
    _callers+=("${_file}")
    if ! grep -qE '^[[:space:]]*(export[[:space:]]+)?LOAD_MOCKS_AI_CONFIG=1|_OVERRIDE_AI_CONFIG_DIR=' "${REPO_ROOT}/${_file}"; then
      printf '%s: calls run_setup_user/setup_dotfile_symlinks without LOAD_MOCKS_AI_CONFIG=1\n' "${_file}" >&2
      _bad=1
    fi
  done < <(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}" ls-files 'tests/*.bats' | LC_ALL=C sort)
  # positive control: the scan finds the known caller
  [ "${#_callers[@]}" -gt 0 ]
  printf '%s\n' "${_callers[@]}" | grep -qx 'tests/setup_env/workflows.bats'
  [ "${_bad}" -eq 0 ]
}
