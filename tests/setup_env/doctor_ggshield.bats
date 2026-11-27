#!/usr/bin/env bats
# _doctor_check_ggshield: does ggshield resolve and hold a working key?

load '../helpers/common.bash'

setup() {
  _SYS_PATH="$(refusing_sudo_path /usr/bin:/bin)" || return 1
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  STUB="${REPO_ROOT}/tests/stubs/ggshield-stub"
  # Every test points the arm at the stub (or a scoped PATH holding it) so the
  # real ggshield and its network are unreachable.
  export GGSHIELD_BIN="${STUB}"
  unset GGSHIELD_FALLBACK_PATHS GITGUARDIAN_API_KEY
  export STUB_GGSHIELD_CALLS="${BATS_TEST_TMPDIR}/calls"
  OUT="${BATS_TEST_TMPDIR}/arm_out"
}

# run_arm -- NOT `run`: a subshell would lose the counters.
run_arm() {
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_WARN=0; _DOCTOR_FAILED=0
  _doctor_check_ggshield > "${OUT}" 2>&1
}

@test "doctor ggshield: rc 0 is one PASS naming the path" {
  STUB_GGSHIELD_EXIT=0 run_arm
  grep -qF "ggshield:" "${OUT}"
  grep -qF "${STUB}: authenticated" "${OUT}"
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
}

@test "doctor ggshield: GITGUARDIAN_API_KEY in the shell is named in the PASS" {
  GITGUARDIAN_API_KEY=x STUB_GGSHIELD_EXIT=0 run_arm
  grep -qF "${STUB}: authenticated (key from GITGUARDIAN_API_KEY in this shell)" "${OUT}"
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "doctor ggshield: rc 3 is a FAIL for no key" {
  STUB_GGSHIELD_EXIT=3 run_arm
  grep -qF "no API key — remedy: ggshield auth login" "${OUT}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor ggshield: rc 128 is a FAIL rejected or failed (rc 128)" {
  STUB_GGSHIELD_EXIT=128 run_arm
  grep -qF "API key rejected or check failed (rc 128) — remedy: ggshield auth login" "${OUT}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
}

@test "doctor ggshield: rc 2 is a FAIL" {
  STUB_GGSHIELD_EXIT=2 run_arm
  grep -qF "API key rejected or check failed (rc 2)" "${OUT}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
}

@test "doctor ggshield: rc 1 is a WARN could not reach" {
  STUB_GGSHIELD_EXIT=1 run_arm
  grep -qF "could not reach GitGuardian (rc 1)" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}

@test "doctor ggshield: rc 4 is a WARN could not reach" {
  STUB_GGSHIELD_EXIT=4 run_arm
  grep -qF "could not reach GitGuardian (rc 4)" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}

@test "doctor ggshield: a probe past the timeout is a WARN no answer" {
  if [[ -z "$(_doctor_resolve_timeout)" ]]; then skip "no timeout binary"; fi
  _DOCTOR_PROBE_TIMEOUT=1 STUB_GGSHIELD_SLEEP=5 run_arm
  grep -qF "could not verify the API key: no answer in 1s" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}

@test "doctor ggshield: not found anywhere is a FAIL" {
  unset GGSHIELD_BIN
  export GGSHIELD_FALLBACK_PATHS="/nonexistent/ggshield"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_WARN=0; _DOCTOR_FAILED=0
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  PATH="${BATS_TEST_TMPDIR}/empty" _doctor_check_ggshield > "${OUT}" 2>&1
  grep -qF "not installed — the pre-commit secret scan cannot run — remedy: brew install ggshield" "${OUT}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ ! -e "${STUB_GGSHIELD_CALLS}" ]
}

@test "doctor ggshield: a non-executable GGSHIELD_BIN is a FAIL and nothing runs" {
  : > "${BATS_TEST_TMPDIR}/not-exec"
  export GGSHIELD_BIN="${BATS_TEST_TMPDIR}/not-exec"
  run_arm
  grep -qF "GGSHIELD_BIN=${BATS_TEST_TMPDIR}/not-exec is not executable" "${OUT}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ ! -e "${STUB_GGSHIELD_CALLS}" ]
}

@test "doctor ggshield: a GGSHIELD_BIN that is a directory is a FAIL" {
  mkdir -p "${BATS_TEST_TMPDIR}/adir"
  export GGSHIELD_BIN="${BATS_TEST_TMPDIR}/adir"
  run_arm
  grep -qF "GGSHIELD_BIN=${BATS_TEST_TMPDIR}/adir is not executable" "${OUT}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor ggshield: no timeout binary is a WARN and ggshield never runs" {
  export _TIMEOUT_FALLBACK_PATHS="/nonexistent/gtimeout"
  local _bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_bin}"
  ln -s "${STUB}" "${_bin}/ggshield"
  unset GGSHIELD_BIN
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_WARN=0; _DOCTOR_FAILED=0
  PATH="${_bin}" _doctor_check_ggshield > "${OUT}" 2>&1
  grep -qF "found; API key not verified (no timeout binary)" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ ! -e "${STUB_GGSHIELD_CALLS}" ]
}

@test "doctor ggshield: resolves through command -v when GGSHIELD_BIN is unset" {
  local _bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_bin}"
  ln -s "${STUB}" "${_bin}/ggshield"
  unset GGSHIELD_BIN
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_WARN=0; _DOCTOR_FAILED=0
  PATH="${_bin}:${_SYS_PATH}" _doctor_check_ggshield > "${OUT}" 2>&1
  grep -qF "${_bin}/ggshield: authenticated" "${OUT}"
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "doctor ggshield: resolves through GGSHIELD_FALLBACK_PATHS" {
  unset GGSHIELD_BIN
  export GGSHIELD_FALLBACK_PATHS="/nonexistent/a ${STUB}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_WARN=0; _DOCTOR_FAILED=0
  # Only what the stub needs on PATH: a machine with /usr/bin/ggshield cannot win.
  mkdir -p "${BATS_TEST_TMPDIR}/tonly"
  local _t _src
  for _t in timeout bash sleep; do
    _src="$(command -v "${_t}" || { [[ "${_t}" == timeout ]] && command -v gtimeout; })" || _src=""
    [ -n "${_src}" ] || { printf 'no %s on PATH for the scoped-PATH fixture\n' "${_t}" >&2; return 1; }
    ln -s "$(readlink -f "${_src}")" "${BATS_TEST_TMPDIR}/tonly/${_t}"
  done
  PATH="${BATS_TEST_TMPDIR}/tonly" _doctor_check_ggshield > "${OUT}" 2>&1
  grep -qF "${STUB}: authenticated" "${OUT}"
}

@test "doctor ggshield: the probe runs from the root directory" {
  mkdir -p "${BATS_TEST_TMPDIR}/elsewhere"
  cd "${BATS_TEST_TMPDIR}/elsewhere"
  run_arm
  [ "$(cut -d' ' -f2- "${STUB_GGSHIELD_CALLS}")" = "/" ]
}

@test "doctor ggshield: the probe runs and a fake key never reaches the output" {
  STUB_GGSHIELD_EXIT=0 run_arm
  [ -s "${STUB_GGSHIELD_CALLS}" ]
  ! command grep -qF "fake-key-AbCdEf123" "${OUT}"
}

@test "doctor ggshield: fallback list equals the pre-commit hook's" {
  local _h _p _l
  _h="$(sed -n 's/.*GGSHIELD_FALLBACK_PATHS:-\([^}]*\)}.*/\1/p' "${REPO_ROOT}/lib/helpers.sh" | head -1)"
  _p="$(sed -n 's/.*GGSHIELD_FALLBACK_PATHS:-\([^}]*\)}.*/\1/p' "${REPO_ROOT}/scripts/pre-commit-hook.sh" | head -1)"
  [ -n "${_h}" ]
  [ "${_h}" = "${_p}" ]
  [ "$(printf '%s\n' "${_h}" | wc -w)" -eq 3 ]
  for _l in ${_h}; do
    [[ "${_l}" == /* ]]
  done
}

@test "doctor ggshield: run_doctor calls the arm on the line after _doctor_check_git_hooks" {
  local _body _l
  _body="$(declare -f run_doctor | sed 's/^ *//')"
  _l="$(printf '%s\n' "${_body}" | grep -n '^_doctor_check_git_hooks;$' | head -1 | cut -d: -f1)"
  [ -n "${_l}" ]
  [ "$(printf '%s\n' "${_body}" | sed -n "$(( _l + 1 ))p")" = "_doctor_check_ggshield;" ]
  local _src="${REPO_ROOT}/lib/helpers.sh"
  _l="$(grep -n '^  _doctor_check_git_hooks$' "${_src}" | head -1 | cut -d: -f1)"
  [ -n "${_l}" ]
  [ "$(sed -n "$(( _l + 1 ))p" "${_src}")" = "  _doctor_check_ggshield" ]
}

@test "doctor ggshield: headings sit between Git hooksPath and the versions section" {
  local _fn
  for _fn in $(declare -F | awk '{print $3}' | command grep '^_doctor_check_'); do
    eval "${_fn}() { :; }"
  done
  _doctor_check_hooks_path() { printf '\nGit hooksPath:\n'; }
  _doctor_check_git_hooks() { printf '\nGit hooks:\n'; }
  _doctor_check_ggshield() { printf '\nggshield:\n'; }
  _doctor_check_versions() { printf '\nVersions:\n'; }
  run run_doctor
  local _o="${output}"
  local _a _b _c _d
  _a="$(printf '%s\n' "${_o}" | grep -n 'Git hooksPath:' | head -1 | cut -d: -f1)"
  _b="$(printf '%s\n' "${_o}" | grep -n 'Git hooks:' | head -1 | cut -d: -f1)"
  _c="$(printf '%s\n' "${_o}" | grep -n 'ggshield:' | head -1 | cut -d: -f1)"
  _d="$(printf '%s\n' "${_o}" | grep -n 'Versions:' | head -1 | cut -d: -f1)"
  [ -n "${_a}" ] && [ -n "${_d}" ]
  [ "${_a}" -lt "${_b}" ]
  [ "${_b}" -lt "${_c}" ]
  [ "${_c}" -lt "${_d}" ]
}

# scan_doctor_subprocess_lines <file>... -- prints file:line for every non-comment
# line that runs the setup script in doctor mode without a non-empty GGSHIELD_BIN=
# value on it.
scan_doctor_subprocess_lines() {
  awk '
    /^[[:space:]]*#/ || /^@test/ { next }
    /setup_env\.sh"?[[:space:]]+-t[[:space:]]+"?doctor"?/ && !/GGSHIELD_BIN="?[^ "]/ { print FILENAME ":" FNR }
  ' "$@"
}

@test "doctor ggshield: the scanner reports a doctor subprocess line without GGSHIELD_BIN" {
  local _f="${BATS_TEST_TMPDIR}/fixture.bats"
  # The "-t" and "doctor" words are kept apart so this file's own lines stay
  # clear of the scanner under test.
  local _cmd='bash "${x}/setup_env.sh" -t'
  printf '%s\n' "  run ${_cmd} doctor" \
    "  GGSHIELD_BIN=/s run ${_cmd} doctor" \
    "  # run ${_cmd} doctor" \
    "  GGSHIELD_BIN= run ${_cmd} doctor" \
    "  run ${_cmd} \"doctor\"" \
    "  run ${_cmd}  doctor" > "${_f}"
  [ "$(scan_doctor_subprocess_lines "${_f}")" = "${_f}:1
${_f}:4
${_f}:5
${_f}:6" ]
}

@test "doctor ggshield: every tracked doctor subprocess test sets GGSHIELD_BIN" {
  local -a _files
  mapfile -t _files < <(cd "${REPO_ROOT}" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git ls-files 'tests/*.bats')
  [ "${#_files[@]}" -gt 0 ]
  local _bad
  _bad="$(cd "${REPO_ROOT}" && scan_doctor_subprocess_lines "${_files[@]}")"
  [ -z "${_bad}" ] || { printf 'unguarded doctor subprocess: %s\n' "${_bad}" >&2; false; }
}
