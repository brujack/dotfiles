#!/usr/bin/env bats
# Tests for lib/helpers.sh's _doctor_check_brew_links and the load_mocks brew
# defaults it depends on (_BREW_BIN, _BREW_FALLBACK_PATHS).
# Spec: docs/superpowers/specs/2026-10-20-doctor-brew-links-design.md

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
}

@test "load_mocks: _BREW_BIN is an executable stub under BATS_TEST_TMPDIR" {
  [[ -x "${_BREW_BIN}" ]]
  [[ "${_BREW_BIN}" == "${BATS_TEST_TMPDIR}"/* ]]
}

@test "load_mocks: the _BREW_BIN stub exits 0, prints nothing, logs argv under BATS_TEST_TMPDIR" {
  run "${_BREW_BIN}" doctor x
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  grep -qx 'doctor x' "${BATS_TEST_TMPDIR}/brew-calls"
}

@test "load_mocks: _BREW_FALLBACK_PATHS names only a missing path under BATS_TEST_TMPDIR" {
  [ "${_BREW_FALLBACK_PATHS}" = "${BATS_TEST_TMPDIR}/no-brew" ]
  [[ ! -e "${_BREW_FALLBACK_PATHS}" ]]
}

@test "load_mocks: _BREW_BIN and _BREW_FALLBACK_PATHS are exported" {
  run bash -c 'printf "%s|%s" "${_BREW_BIN}" "${_BREW_FALLBACK_PATHS}"'
  [ "${status}" -eq 0 ]
  [ -n "${_BREW_BIN}" ]
  [ -n "${_BREW_FALLBACK_PATHS}" ]
  [ "${output}" = "${_BREW_BIN}|${_BREW_FALLBACK_PATHS}" ]
}

# ── _doctor_check_brew_links ─────────────────────────────────────────────────
#
# Per-test brew stubs live under BATS_TEST_TMPDIR. Stubs use an absolute
# shebang and bash builtins only, so they still run when a test scopes PATH to
# a directory holding nothing but the tools that test needs.

_FIX_BROKEN="tests/fixtures/brew/doctor-broken-symlinks.txt"
_FIX_UNLINKED="tests/fixtures/brew/doctor-unlinked-kegs.txt"
_PROBE_ARGV="doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only"

# The real sleep: load_mocks puts a mock `sleep` first on PATH, which returns
# at once and would defeat every timing test.
_real_sleep() {
  local _c
  for _c in /bin/sleep /usr/bin/sleep; do
    if [[ -x "${_c}" ]]; then
      printf '%s' "${_c}"
      return 0
    fi
  done
  skip "no real 'sleep' binary at /bin or /usr/bin"
}

# _write_brew_stub <path> <rc> [<output-file> [<sleep-seconds>]]
# Logs argv (one line, "$*") to ${BATS_TEST_TMPDIR}/brew-calls, prints the
# output file's text, optionally sleeps, then exits <rc>.
_write_brew_stub() {
  local _path="$1" _rc="$2" _file="${3:-}" _sleep="${4:-}" _sleep_bin=""
  [[ -z "${_sleep}" ]] || _sleep_bin="$(_real_sleep)"
  mkdir -p "$(dirname "${_path}")"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >> "%s/brew-calls"\n' "${BATS_TEST_TMPDIR}"
    [[ -z "${_file}" ]] || printf 'printf "%%s\\n" "$(<"%s")"\n' "${_file}"
    [[ -z "${_sleep}" ]] || printf '"%s" %s\n' "${_sleep_bin}" "${_sleep}"
    printf 'exit %s\n' "${_rc}"
  } > "${_path}"
  chmod +x "${_path}"
}

# Fixture text plus N synthetic entries, so the header wording stays captured.
# _numbered_fixture <fixture> <prefix> <n> <out>: replaces the fixture's single
# indented entry line with N lines "  <prefix>pK".
_numbered_fixture() {
  local _fix="$1" _prefix="$2" _n="$3" _out="$4" _line _i
  : > "${_out}"
  while IFS= read -r _line; do
    if [[ "${_line}" == "  "* ]]; then
      for (( _i = 1; _i <= _n; _i++ )); do
        printf '  %sp%s\n' "${_prefix}" "${_i}" >> "${_out}"
      done
    else
      printf '%s\n' "${_line}" >> "${_out}"
    fi
  done < "${REPO_ROOT}/${_fix}"
}

# Calls the check with errexit off, as production runs it (bats runs a test body
# under set -e, and a status-1 `command -v` inside the check would abort it).
# Records the check's own status in _CHECK_RC.
_invoke_check() {
  set +e
  _doctor_check_brew_links
  _CHECK_RC=$?
  set -e
}

_reset_counters() {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _DOCTOR_WARN=0
}

# Runs the check in this shell (counters survive) with stdout in ${_OUT_FILE}.
_run_check() {
  _OUT_FILE="${BATS_TEST_TMPDIR}/check-out"
  _reset_counters
  _invoke_check > "${_OUT_FILE}"
  [ "${_CHECK_RC}" -eq 0 ]
  _OUT="$(<"${_OUT_FILE}")"
}

# A PATH directory holding only sleep (and optionally the real timeout).
_make_bin_dir() {
  _BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_BIN_DIR}"
  ln -s "$(_real_sleep)" "${_BIN_DIR}/sleep"
}

@test "brew links: no brew anywhere prints the skip line and changes no counter" {
  _make_bin_dir
  unset _BREW_BIN
  export _BREW_FALLBACK_PATHS="${BATS_TEST_TMPDIR}/no-brew"
  _OUT_FILE="${BATS_TEST_TMPDIR}/check-out"
  _reset_counters
  PATH="${_BIN_DIR}" _invoke_check > "${_OUT_FILE}"
  [[ "$(<"${_OUT_FILE}")" == *"Homebrew links:"* ]]
  [[ "$(<"${_OUT_FILE}")" == *"  brew not found — skipped"* ]]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}

@test "brew links: command -v brew wins over the fallback list" {
  _make_bin_dir
  unset _BREW_BIN
  _write_brew_stub "${_BIN_DIR}/brew" 0
  _write_brew_stub "${BATS_TEST_TMPDIR}/fb/brew" 0
  rm -f "${BATS_TEST_TMPDIR}/brew-calls"
  # The fallback stub logs to the same file, so give it a distinguishing marker.
  printf '#!/bin/bash\nprintf "fallback\\n" >> "%s/brew-calls"\nexit 0\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/fb/brew"
  export _BREW_FALLBACK_PATHS="${BATS_TEST_TMPDIR}/fb/brew"
  _reset_counters
  PATH="${_BIN_DIR}" _invoke_check > /dev/null
  grep -qx "${_PROBE_ARGV}" "${BATS_TEST_TMPDIR}/brew-calls"
  ! command grep -q fallback "${BATS_TEST_TMPDIR}/brew-calls"
}

@test "brew links: fallback path is used when brew is not on PATH" {
  _make_bin_dir
  unset _BREW_BIN
  _write_brew_stub "${BATS_TEST_TMPDIR}/fb/brew" 0
  export _BREW_FALLBACK_PATHS="${BATS_TEST_TMPDIR}/missing/brew ${BATS_TEST_TMPDIR}/fb/brew"
  rm -f "${BATS_TEST_TMPDIR}/brew-calls"
  _reset_counters
  PATH="${_BIN_DIR}" _invoke_check > /dev/null
  grep -qx "${_PROBE_ARGV}" "${BATS_TEST_TMPDIR}/brew-calls"
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "brew links: a non-executable _BREW_BIN warns, names it, and never probes or falls through" {
  : > "${BATS_TEST_TMPDIR}/not-exec"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/not-exec"
  rm -f "${BATS_TEST_TMPDIR}/brew-calls"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [[ "${_OUT}" == *"[WARN]"*"brew links"*"${BATS_TEST_TMPDIR}/not-exec"* ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/brew-calls" ]]
}

@test "brew links: rc 0 gives one PASS and the exact probe argv" {
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 0
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  rm -f "${BATS_TEST_TMPDIR}/brew-calls"
  _run_check
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [ "$(wc -l < "${BATS_TEST_TMPDIR}/brew-calls")" -eq 1 ]
  [ "$(<"${BATS_TEST_TMPDIR}/brew-calls")" = "${_PROBE_ARGV}" ]
  [[ "${_OUT}" == *"[PASS]"*"brew links"* ]]
}

@test "brew links: probe sets HOMEBREW_NO_AUTO_UPDATE=1 and leaves HOMEBREW_NO_INSTALL_FROM_API unset, stdin is /dev/null" {
  printf '#!/bin/bash\nprintf "%%s|%%s|%%s\\n" "${HOMEBREW_NO_AUTO_UPDATE-unset}" "${HOMEBREW_NO_INSTALL_FROM_API-unset}" "$(cat | wc -c | tr -d " ")" > "%s/env-seen"\nexit 0\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/brew"
  chmod +x "${BATS_TEST_TMPDIR}/brew"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  unset HOMEBREW_NO_INSTALL_FROM_API HOMEBREW_NO_AUTO_UPDATE
  _run_check < <(printf 'not-empty')
  [ "$(<"${BATS_TEST_TMPDIR}/env-seen")" = "1|unset|0" ]
}

@test "brew links: broken-symlinks fixture gives one single-line WARN with the path and the remedy" {
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${REPO_ROOT}/${_FIX_BROKEN}"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "$(command grep -c '\[WARN\]' "${_OUT_FILE}")" -eq 1 ]
  [[ "${_OUT}" == *"broken symlinks: 1 (/opt/homebrew/opt/zz-doctor-probe)"* ]]
  [[ "${_OUT}" == *"— run: brew cleanup --prune-prefix"* ]]
}

@test "brew links: unlinked-kegs fixture gives one single-line WARN with the keg and brew link" {
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${REPO_ROOT}/${_FIX_UNLINKED}"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "$(command grep -c '\[WARN\]' "${_OUT_FILE}")" -eq 1 ]
  [[ "${_OUT}" == *"unlinked kegs: 1 (tree)"* ]]
  [[ "${_OUT}" == *"— run: brew link tree"* ]]
}

@test "brew links: both fixtures concatenated give exactly 2 WARN lines" {
  cat "${REPO_ROOT}/${_FIX_BROKEN}" "${REPO_ROOT}/${_FIX_UNLINKED}" > "${BATS_TEST_TMPDIR}/both.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/both.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 2 ]
  [ "$(command grep -c '\[WARN\]' "${_OUT_FILE}")" -eq 2 ]
  [[ "${_OUT}" == *"broken symlinks: 1"* ]]
  [[ "${_OUT}" == *"unlinked kegs: 1"* ]]
}

@test "brew links: progress lines before the findings do not change the WARN" {
  {
    printf '==> Downloading Homebrew API data\n'
    printf '✔︎ JSON API packages.arm64_tahoe.jws.json\n'
    cat "${REPO_ROOT}/${_FIX_UNLINKED}"
  } > "${BATS_TEST_TMPDIR}/progress.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/progress.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [[ "${_OUT}" == *"unlinked kegs: 1 (tree) — run: brew link tree"* ]]
  [[ "${_OUT}" != *"✔"* ]]
  [[ "${_OUT}" != *"==>"* ]]
}

@test "brew links: unrecognised rc 1 output warns with the first Warning: line and never passes" {
  printf '==> Downloading Homebrew API data\nWarning: Something new\nmore text\n' > "${BATS_TEST_TMPDIR}/odd.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/odd.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [[ "${_OUT}" == *"brew doctor rc 1: Warning: Something new"* ]]
}

@test "brew links: rc 1 with no Warning:/Error: line uses the first non-progress non-empty line" {
  printf '\n==> Downloading Homebrew API data\nsomething odd\nsecond\n' > "${BATS_TEST_TMPDIR}/odd.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/odd.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [[ "${_OUT}" == *"brew doctor rc 1: something odd"* ]]
  [[ "${_OUT}" != *"second"* ]]
}

@test "brew links: rc 3 warns with the last non-progress non-empty line" {
  printf 'first\nlast real line\n==> trailing progress\n\n' > "${BATS_TEST_TMPDIR}/odd.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 3 "${BATS_TEST_TMPDIR}/odd.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [[ "${_OUT}" == *"brew doctor rc 3: last real line"* ]]
}

@test "brew links: a hung brew under a resolved timeout warns 'did not finish'" {
  local _real_timeout
  _real_timeout="$(command -v timeout 2>/dev/null || true)"
  [[ -n "${_real_timeout}" ]] || skip "no 'timeout' binary on PATH -- cannot exercise the bound"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 0 "" 5
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  export _DOCTOR_BREW_TIMEOUT=1
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [[ "${_OUT}" == *"brew doctor did not finish in 1s"* ]]
}

@test "brew links: no timeout resolvable runs the probe unbounded, PASS and no rc 127" {
  _make_bin_dir
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 0
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  export _TIMEOUT_FALLBACK_PATHS="${BATS_TEST_TMPDIR}/no-timeout"
  _OUT_FILE="${BATS_TEST_TMPDIR}/check-out"
  _reset_counters
  PATH="${_BIN_DIR}" _invoke_check > "${_OUT_FILE}"
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  ! command grep -q 'rc 127' "${_OUT_FILE}"
}

@test "brew links: timeout found via the fallback list is called with the bound" {
  local _real_timeout
  _real_timeout="$(command -v timeout 2>/dev/null || true)"
  [[ -n "${_real_timeout}" ]] || skip "no 'timeout' binary on PATH -- cannot wrap the real one"
  _make_bin_dir
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/timeout-calls"\nexec "%s" "$@"\n' "${BATS_TEST_TMPDIR}" "${_real_timeout}" > "${BATS_TEST_TMPDIR}/gtimeout"
  chmod +x "${BATS_TEST_TMPDIR}/gtimeout"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 0
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  export _TIMEOUT_FALLBACK_PATHS="${BATS_TEST_TMPDIR}/missing/gtimeout ${BATS_TEST_TMPDIR}/gtimeout"
  unset _DOCTOR_BREW_TIMEOUT
  _reset_counters
  PATH="${_BIN_DIR}" _invoke_check > /dev/null
  [ "$(<"${BATS_TEST_TMPDIR}/timeout-calls")" = "60" ]
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "brew links: exactly 10 broken-symlink names are shown with no 'more' suffix" {
  _numbered_fixture "${_FIX_BROKEN}" "/x/" 10 "${BATS_TEST_TMPDIR}/ten.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/ten.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [[ "${_OUT}" == *"broken symlinks: 10 (/x/p1, "*", /x/p10) — run:"* ]]
  [[ "${_OUT}" != *"more"* ]]
}

@test "brew links: 12 broken symlinks show 10 names and '… 2 more'" {
  _numbered_fixture "${_FIX_BROKEN}" "/x/" 12 "${BATS_TEST_TMPDIR}/twelve.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/twelve.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [[ "${_OUT}" == *"broken symlinks: 12 (/x/p1, "*", /x/p10, … 2 more) — run:"* ]]
  [[ "${_OUT}" != *"/x/p11"* ]]
}

@test "brew links: 12 unlinked kegs show 10 names, '… 2 more', and brew link names all 12" {
  _numbered_fixture "${_FIX_UNLINKED}" "" 12 "${BATS_TEST_TMPDIR}/kegs.txt"
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 1 "${BATS_TEST_TMPDIR}/kegs.txt"
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _run_check
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [[ "${_OUT}" == *"unlinked kegs: 12 (p1, "*", p10, … 2 more) — run: brew link p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12"* ]]
}

@test "brew links: no outcome calls doctor_fail" {
  local _rc
  for _rc in 0 1 2 3 127; do
    _write_brew_stub "${BATS_TEST_TMPDIR}/brew" "${_rc}" "${REPO_ROOT}/${_FIX_BROKEN}"
    export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
    _run_check
    [ "${_DOCTOR_FAIL}" -eq 0 ]
    [ "${_DOCTOR_FAILED}" -eq 0 ]
  done
}

@test "brew links: the check returns 0 on a WARN outcome" {
  _write_brew_stub "${BATS_TEST_TMPDIR}/brew" 3
  export _BREW_BIN="${BATS_TEST_TMPDIR}/brew"
  _reset_counters
  _invoke_check > /dev/null
  [ "${_CHECK_RC}" -eq 0 ]
}

@test "brew links: run_doctor calls _doctor_check_brew_links right after _doctor_check_gnu_coreutils" {
  local _order="${BATS_TEST_TMPDIR}/order"
  : > "${_order}"
  local _fn
  for _fn in $(declare -F | awk '{print $3}' | command grep '^_doctor_check_'); do
    eval "${_fn}() { printf '%s\n' '${_fn}' >> '${_order}'; }"
  done
  run_doctor > /dev/null 2>&1 || true
  [ "$(command grep -n -A1 '^_doctor_check_gnu_coreutils$' "${_order}" | tail -1 | cut -d- -f2)" = "_doctor_check_brew_links" ]
}
