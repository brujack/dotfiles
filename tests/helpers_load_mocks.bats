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
  run _ai_config_tracked_items "${_OVERRIDE_AI_CONFIG_DIR}" .cursor
  [ "${status}" -eq 0 ]
  [ "${output}" = "rules" ]
}

# _git_clean <args...> -- git with the repo-pinning variables stripped.
_git_clean() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git "$@"
}

# _guard_scan <root> -- scan the tracked bats files under <root> for direct calls
# to run_setup_user / setup_dotfile_symlinks. Prints "CALLER <file>" for each file
# with a call, and "FLAGGED <file>" when that file neither sets LOAD_MOCKS_AI_CONFIG=1
# nor assigns _OVERRIDE_AI_CONFIG_DIR at the start of a statement.
# A call is in command position: after line start, `;` `&&` `||` `|` `(` `$(` `!`
# `{` or the keywords if/elif/then/else/do/while/until, optionally behind VAR=value
# assignments and `run` with flags.
# Out of scope: `run bash setup_env.sh -t setup_user` (no direct call), and the
# command-position wrappers backtick, `command X` and `time X`.
_guard_scan() {
  local _root="$1" _file _sep _assign _run _name _call _optin
  _sep='(^|[;&|(!{]|(^|[[:space:]])(if|elif|then|else|do|while|until))'
  _assign='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
  _run='(run([[:space:]]+-[^[:space:]]+)*[[:space:]]+)?'
  _name='(run_setup_user|setup_dotfile_symlinks)([[:space:];&|)]|$)'
  _call="${_sep}[[:space:]]*${_assign}${_run}${_name}"
  _optin='^[[:space:]]*(export[[:space:]]+|local[[:space:]]+)?(LOAD_MOCKS_AI_CONFIG=1|_OVERRIDE_AI_CONFIG_DIR=)'
  while IFS= read -r _file; do
    # drop comments and @test titles before matching
    if command grep -vE '^[[:space:]]*(#|@test)' "${_root}/${_file}" | command grep -qE "${_call}"; then
      printf 'CALLER %s\n' "${_file}"
      command grep -qE "${_optin}" "${_root}/${_file}" || printf 'FLAGGED %s\n' "${_file}"
    fi
  done < <(_git_clean -C "${_root}" ls-files '*.bats' | LC_ALL=C sort)
}

@test "every bats file calling run_setup_user or setup_dotfile_symlinks opts in or overrides the ai-config dir" {
  # A per-test stub redefinition is deliberately not an exemption: workflows.bats
  # stubs setup_dotfile_symlinks in one test but its other tests need the fixture.
  local _out _flagged _callers _file
  # Skip this file: its probe strings are call forms by design, and it would
  # otherwise pass only because the opt-in test below exports the variable.
  _out="$(cd "${REPO_ROOT}" && _guard_scan "${REPO_ROOT}" | command grep -vx -e 'CALLER tests/helpers_load_mocks.bats' -e 'FLAGGED tests/helpers_load_mocks.bats')"
  _flagged="$(printf '%s\n' "${_out}" | command grep '^FLAGGED ' || true)"
  if [[ -n ${_flagged} ]]; then
    while IFS= read -r _file; do
      printf '%s: calls run_setup_user/setup_dotfile_symlinks without LOAD_MOCKS_AI_CONFIG=1 or _OVERRIDE_AI_CONFIG_DIR\n' "${_file#FLAGGED }" >&2
    done <<< "${_flagged}"
    return 1
  fi
  # positive control: the caller set is exactly the three known files
  _callers="$(printf '%s\n' "${_out}" | command grep '^CALLER ' | LC_ALL=C sort)"
  [ "${_callers}" = "$(printf 'CALLER tests/setup_env/extracted_functions.bats\nCALLER tests/setup_env/install_guards.bats\nCALLER tests/setup_env/workflows.bats')" ]
}

@test "static guard scan flags every call form and ignores comments and titles" {
  local _repo="${BATS_TEST_TMPDIR}/guard-probe" _f _out _i=0
  local -a _forms=(
    '  run run_setup_user'
    '  run -1 run_setup_user'
    '  run --separate-stderr run_setup_user'
    '  MACOS=1 run run_setup_user'
    '  PATH=/x:$PATH run_setup_user'
    '  DRY_RUN=1 run setup_dotfile_symlinks'
    '  true && run_setup_user'
    '  _o="$(setup_dotfile_symlinks 2>&1)"'
    '  run_setup_user;'
    '  if run_setup_user; then :; fi'
    '  elif run_setup_user; then :'
    '  else run_setup_user'
    '  while run_setup_user; do :; done'
    '  for i in 1; do run_setup_user'
    '  { run_setup_user; }'
    '  setup_dotfile_symlinks'
  )
  local -a _inert=(
    '  declare -f run_setup_user'
    '  # run_setup_user'
    '  # if run_setup_user; then'
    '@test "run_setup_user does a thing" {'
    '@test "a; run_setup_user; b" {'
    '  setup_dotfile_symlinks() { return 1; }'
  )
  mkdir -p "${_repo}"
  _git_clean -C "${_repo}" init -q
  for _f in "${_forms[@]}"; do
    _i=$((_i + 1))
    printf '%s\n' "${_f}" > "${_repo}/form${_i}.bats"
  done
  _i=0
  for _f in "${_inert[@]}"; do
    _i=$((_i + 1))
    printf '%s\n' "${_f}" > "${_repo}/inert${_i}.bats"
  done
  # a comment-only override must not count as an opt-in
  printf '%s\n' '  # export _OVERRIDE_AI_CONFIG_DIR=x' '  run_setup_user' > "${_repo}/commented_override.bats"
  # real overrides do count
  printf '%s\n' '  export _OVERRIDE_AI_CONFIG_DIR=x' '  run_setup_user' > "${_repo}/real_override.bats"
  printf '%s\n' '  export LOAD_MOCKS_AI_CONFIG=1' '  run_setup_user' > "${_repo}/real_optin.bats"
  _git_clean -C "${_repo}" add -- .
  _out="$(_guard_scan "${_repo}")"
  for ((_i = 1; _i <= ${#_forms[@]}; _i++)); do
    printf '%s\n' "${_out}" | command grep -qx "FLAGGED form${_i}.bats" || { printf 'not flagged: %s\n' "${_forms[_i-1]}" >&2; return 1; }
  done
  printf '%s\n' "${_out}" | command grep -qx 'FLAGGED commented_override.bats'
  # bats does not fail on a mid-test `!`, so test the negatives explicitly
  if printf '%s\n' "${_out}" | command grep -qE '^FLAGGED (inert|real_)'; then
    printf '%s\n' "${_out}" >&2
    return 1
  fi
  # inert forms are not even callers
  if printf '%s\n' "${_out}" | command grep -q '^CALLER inert'; then
    printf '%s\n' "${_out}" >&2
    return 1
  fi
}
