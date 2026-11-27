#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Suite-level HOME isolation: tests/helpers/suite_isolation.bash via the
# setup_suite.bash hook in each test directory. Every nested bats run below
# targets a fixture directory under BATS_TEST_TMPDIR.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HELPER="${REPO_ROOT}/tests/helpers/suite_isolation.bash"
  FX="${BATS_TEST_TMPDIR}/fx"
  OUT="${BATS_TEST_TMPDIR}/out.env"
  REC="${BATS_TEST_TMPDIR}/rec"
}

# mkfx <fixture-test-body> [helper-path]: fixture dir with a hook and a.bats.
mkfx() {
  local _body="${1}" _helper="${2:-${HELPER}}"
  mkdir -p "${FX}"
  printf 'source "%s"\n' "${_helper}" > "${FX}/setup_suite.bash"
  printf '#!/usr/bin/env bats\n@test "probe" {\n%s\n}\n' "${_body}" > "${FX}/a.bats"
}

_uv_ver() {
  local _v
  _v="$(sed -n 's/^UV_VER="\(.*\)"$/\1/p' "${REPO_ROOT}/lib/constants.sh")"
  # A pattern broken the same way here and in the helper must not pass silently.
  [[ "${_v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "${_v}"
}

@test "every test directory has a setup_suite.bash that sources the helper" {
  local _dir
  while IFS= read -r _dir; do
    [[ -f "${REPO_ROOT}/${_dir}/setup_suite.bash" && ! -L "${REPO_ROOT}/${_dir}/setup_suite.bash" ]] \
      || { printf 'missing hook: %s\n' "${_dir}" >&2; return 1; }
    command grep -q 'suite_isolation.bash' "${REPO_ROOT}/${_dir}/setup_suite.bash" \
      || { printf 'missing hook: %s\n' "${_dir}" >&2; return 1; }
  done < <(while IFS= read -r _f; do dirname "${_f}"; done < "${REPO_ROOT}/tests/bats-files.txt" | LC_ALL=C sort -u)
}

@test "HOME of this test lies under a bats-sentinel directory" {
  [[ "${HOME}" == */bats-sentinel.*/home ]]
}

@test "setup_suite exports the suite ledger the root-path guard scans" {
  mkfx '[ -n "${_SUITE_MOCK_CALLS_FILE}" ] && [ "${_SUITE_MOCK_CALLS_FILE}" = "${MOCK_CALLS_FILE}" ] && printf "%s\n" "${_SUITE_MOCK_CALLS_FILE}" > "${OUT}"'
  run env -u MOCK_CALLS_FILE -u _SUITE_MOCK_CALLS_FILE OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  [[ "$(< "${OUT}")" == */bats-sentinel.*/mock_calls ]]
  # A caller's ledger is the suite ledger too.
  run env -u _SUITE_MOCK_CALLS_FILE MOCK_CALLS_FILE=/caller/calls OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  [ "$(< "${OUT}")" = "/caller/calls" ]
}

@test "setup_suite exports the R2 values" {
  mkfx 'env > "${OUT}"; for _d in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME PARALLEL_HOME; do [ -d "${!_d}" ] && printf "dir-ok:%s\n" "${_d}" >> "${OUT}"; done'
  run env -u MOCK_CALLS_FILE OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  local _h _s
  _h="$(sed -n 's/^HOME=//p' "${OUT}")"
  [[ "${_h}" == */bats-sentinel.*/home ]]
  _s="${_h%/home}"
  command grep -qx "HOME=${_s}/home" "${OUT}"
  command grep -qx "ZDOTDIR=${_s}/home" "${OUT}"
  command grep -qx "TMPPREFIX=${_s}/zsh" "${OUT}"
  command grep -qx "PARALLEL_HOME=${_s}/parallel" "${OUT}"
  command grep -qx "XDG_CONFIG_HOME=${_s}/xdg/config" "${OUT}"
  command grep -qx "XDG_CACHE_HOME=${_s}/xdg/cache" "${OUT}"
  command grep -qx "XDG_DATA_HOME=${_s}/xdg/data" "${OUT}"
  command grep -qx "XDG_STATE_HOME=${_s}/xdg/state" "${OUT}"
  command grep -qx "GIT_CONFIG_GLOBAL=/dev/null" "${OUT}"
  command grep -qx "GIT_CONFIG_SYSTEM=/dev/null" "${OUT}"
  command grep -qx "MOCK_CALLS_FILE=${_s}/mock_calls" "${OUT}"
  if command grep -q '^_BATS_SENTINEL=' "${OUT}"; then return 1; fi
  local _n
  for _n in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME PARALLEL_HOME; do
    command grep -qx "dir-ok:${_n}" "${OUT}"
  done
}

@test "a caller's MOCK_CALLS_FILE survives" {
  mkfx 'env > "${OUT}"'
  run env MOCK_CALLS_FILE=/caller/calls OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  command grep -qx 'MOCK_CALLS_FILE=/caller/calls' "${OUT}"
}

@test "PINNED_UV_BIN comes from the pre-swap HOME" {
  local _fake="${BATS_TEST_TMPDIR}/fakehome" _v _uv
  _v="$(_uv_ver)"
  _uv="${_fake}/.local/share/dotfiles/pinned/uv-${_v}/uv"
  mkdir -p "${_uv%/*}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_uv}"
  chmod +x "${_uv}"
  mkfx 'env > "${OUT}"'
  run env -u PINNED_UV_BIN HOME="${_fake}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  command grep -qx "PINNED_UV_BIN=${_uv}" "${OUT}"
  run env PINNED_UV_BIN=/caller/uv HOME="${_fake}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  command grep -qx 'PINNED_UV_BIN=/caller/uv' "${OUT}"
}

@test "PINNED_UV_BIN stays unset when the real HOME has no pinned uv" {
  local _fake="${BATS_TEST_TMPDIR}/emptyhome"
  mkdir -p "${_fake}"
  mkfx 'env > "${OUT}"'
  run env -u PINNED_UV_BIN HOME="${_fake}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  if command grep -q '^PINNED_UV_BIN=' "${OUT}"; then return 1; fi
}

@test "an unreadable constants file prints the message and still isolates" {
  local _t="${BATS_TEST_TMPDIR}/t"
  mkdir -p "${_t}/tests/helpers"
  cp "${HELPER}" "${_t}/tests/helpers/suite_isolation.bash"
  mkfx '[[ "${HOME}" == */bats-sentinel.*/home ]]' "${_t}/tests/helpers/suite_isolation.bash"
  run bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cannot read UV_VER from"* ]]
}

@test "the sentinel exists during the run and is gone after" {
  mkfx '[ -d "${HOME%/home}" ]; printf "%s" "${HOME%/home}" > "${REC}"'
  run env REC="${REC}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  [ -n "$(cat "${REC}")" ]
  [ ! -e "$(cat "${REC}")" ]
}

@test "mktemp failure stops the suite" {
  local _mark="${BATS_TEST_TMPDIR}/ran"
  mkfx 'touch "${MARK}"'
  run env MARK="${_mark}" _BATS_SENTINEL_TMP_ROOT="${BATS_TEST_TMPDIR}/missing" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 1 ]
  # setup_suite must stop the run: the fixture test never executes.
  [ ! -e "${_mark}" ]
  [[ "${output}" == *"not ok 1 setup_suite"* ]]
  [[ "${output}" == *"bats isolation: cannot create sentinel under"* ]]
}

@test "guard refuses an empty sentinel" {
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  _BATS_SENTINEL=""
  run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: no sentinel to check"* ]]
}

@test "guard refuses a non-sentinel directory" {
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  mkdir -p "${BATS_TEST_TMPDIR}/canary"
  printf 'x' > "${BATS_TEST_TMPDIR}/canary/file"
  _BATS_SENTINEL="${BATS_TEST_TMPDIR}/canary"
  run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: no sentinel to check"* ]]
  [ -f "${BATS_TEST_TMPDIR}/canary/file" ]
}

@test "a nested failing setup never deletes an inherited sentinel" {
  # Pins the outcome: a failed $(mktemp) assignment empties the variable anyway,
  # so the inherited value must be neither used nor deleted. The plant is a
  # valid sentinel path (basename bats-sentinel.*), so only the unset protects it.
  local _plant="${BATS_TEST_TMPDIR}/bats-sentinel.keep"
  mkdir -p "${_plant}/home"
  mkfx ':'
  run env _BATS_SENTINEL="${_plant}" _BATS_SENTINEL_TMP_ROOT="${BATS_TEST_TMPDIR}/missing" \
    bats "${FX}/a.bats" < /dev/null
  [ -d "${_plant}" ]
  [[ "${output}" == *"cannot create sentinel under"* ]]
  [[ "${output}" == *"no sentinel to check"* ]]
}

@test "an inherited exported _BATS_SENTINEL does not leak into tests" {
  local _plant="${BATS_TEST_TMPDIR}/bats-sentinel.inherit"
  mkdir -p "${_plant}/home"
  mkfx 'env > "${OUT}"'
  run env _BATS_SENTINEL="${_plant}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  # `!` does not trip errexit mid-test, so branch explicitly.
  if command grep -q '^_BATS_SENTINEL=' "${OUT}"; then return 1; fi
  [ -d "${_plant}" ]
}

@test "guard refuses a sentinel-named path that does not exist" {
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  _BATS_SENTINEL="${BATS_TEST_TMPDIR}/bats-sentinel.gone"
  run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: no sentinel to check"* ]]
}

@test "a failed removal is reported even when rm exits 0" {
  local _s="${BATS_TEST_TMPDIR}/bats-sentinel.rmfail" _shim="${BATS_TEST_TMPDIR}/shim"
  mkdir -p "${_s}/home/x" "${_shim}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_shim}/rm"
  chmod +x "${_shim}/rm"
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  _BATS_SENTINEL="${_s}"
  PATH="${_shim}:${PATH}" run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: cannot remove"* ]]
  [[ "${output}" == *"chmod -R u+w"* ]]
  /bin/rm -rf "${_s}"
}

@test "sudo resolves to the refusing stub when a test loads no mocks" {
  # No load_mocks here, so this is the path release_binary.bats and
  # pinned_uv.bats take: the real /usr/bin/sudo must be unreachable.
  [[ "$(command -v sudo)" == */bats-sentinel.*/nosudo/sudo ]]
  run sudo touch "${BATS_TEST_TMPDIR}/must-not-exist"
  [ "${status}" -eq 97 ]
  [[ "${output}" == *"REAL SUDO BLOCKED"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/must-not-exist" ]
}

# Tests that replace PATH with system directories build it with
# refusing_sudo_path; the path it builds must still resolve sudo to the stub.
@test "refusing_sudo_path: a system-only PATH still resolves sudo to the refusing stub" {
  source "${REPO_ROOT}/tests/helpers/common.bash"
  local _sys
  _sys="$(refusing_sudo_path /usr/bin:/bin:/usr/sbin:/sbin)" || return 1
  [[ "$(PATH="${_sys}" command -v sudo)" == */bats-sentinel.*/nosudo/sudo ]]
  run env PATH="${_sys}" sudo touch "${BATS_TEST_TMPDIR}/must-not-exist"
  [ "${status}" -eq 97 ]
  [ ! -e "${BATS_TEST_TMPDIR}/must-not-exist" ]
}

@test "refusing_sudo_path: fails closed when the stub is missing" {
  source "${REPO_ROOT}/tests/helpers/common.bash"
  _BATS_NOSUDO_DIR="${BATS_TEST_TMPDIR}/absent" run refusing_sudo_path /usr/bin
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"no refusing sudo stub"* ]]
}

# Lines of the given files that either set PATH to a value with a /usr/bin or
# /bin element without going through refusing_sudo_path, or build PATH from
# refusing_sudo_path in a form that loses its fail-closed status. Single-line
# assignments only. Returns 0 with the findings on stdout, 1 when there are none,
# 2 when a file cannot be read (a scan that read nothing must not read as clean).
#
# Raw reset exemptions, each limited to the PATH value itself (a word starting at
# `PATH=` and ending at the first blank, `;`, `|` or `&`), so a `$PATH` printed
# elsewhere on the line exempts nothing:
#  - the value holds ${PATH}/$PATH (it keeps the stub), tests/mocks (holds the
#    sudo mock) or $(refusing_sudo_path ...);
#  - `PATH=<value> command -v ...` is a lookup and runs nothing.
# Fail-open forms: a command substitution's status is dropped by a prefix
# assignment (`PATH="$(f)" cmd`), by `env PATH="$(f)"` and by export/local/readonly,
# so a missing stub leaves PATH empty; assign to a variable on its own line first.
_unguarded_path_resets() {
  local _f _raw _open _rc=1
  local _exempt='PATH=[^[:space:];|&]*(\$\{?PATH\}?|tests/mocks|\$\(refusing_sudo_path)|PATH=[^[:space:]]+[[:space:]]+command -v '
  local _open_forms='PATH="\$\(refusing_sudo_path[^)]*\)"[[:space:]]+[^[:space:]|&;#]|(^|[[:space:]])env[[:space:]].*PATH="?\$\(refusing_sudo_path|(export|local|readonly|declare)[[:space:]]+PATH=.*\$\(refusing_sudo_path'
  for _f in "$@"; do
    [[ -r ${_f} ]] || { printf '_unguarded_path_resets: cannot read %s\n' "${_f}" >&2; return 2; }
  done
  # grep rc 1 here means "no line", which is the clean answer; unreadable input
  # was ruled out above.
  _raw="$(command grep -nE 'PATH=' "$@" \
    | command grep -E "[=:\"']/(usr/)?bin([:\"'[:space:]]|\$)" \
    | command grep -vE "${_exempt}")" || true
  _open="$(command grep -nE "${_open_forms}" "$@")" || true
  if [[ -n ${_raw} ]]; then printf '%s\n' "${_raw}"; _rc=0; fi
  if [[ -n ${_open} ]]; then printf '%s\n' "${_open}"; _rc=0; fi
  return "${_rc}"
}

@test "the PATH-reset guard flags every unguarded form and passes the allowed ones" {
  local _f="${BATS_TEST_TMPDIR}/seed.bats"
  cat > "${_f}" << 'SEED'
  export PATH="${X}:/usr/bin:/bin"
  PATH="/bin:/usr/bin"
  PATH='/usr/bin:/bin'
  run env PATH=/usr/bin:/bin bash -c true
  run env PATH="/bin" bash -c true
  PATH=/usr/bin
  _ok="$(PATH="$(refusing_sudo_path /usr/bin:/bin)" cmd)"
  PATH="/usr/bin:${PATH}" cmd
  PATH="${HOME}/mocks/tests/mocks:/usr/bin" cmd
  PATH="/usr/bin:/bin"; echo "$PATH"
  PATH=/usr/bin:/bin echo "${PATH}"
  PATH=/usr/bin:/bin command -v git
  _p="$(PATH="/usr/bin:/bin" command -v "${_c}")"
  PATH="${d}:$(refusing_sudo_path /usr/bin:/bin)"
  run env PATH="$(refusing_sudo_path /usr/bin:/bin)" cmd
  PATH="$(refusing_sudo_path /usr/bin:/bin)" X=y run cmd
  export PATH="$(refusing_sudo_path /usr/bin:/bin)"
  local PATH="$(refusing_sudo_path /usr/bin:/bin)"
  _s="$(refusing_sudo_path /usr/bin:/bin)" || return 1
  PATH="${_s}" run cmd
SEED
  run _unguarded_path_resets "${_f}"
  [ "${status}" -eq 0 ]
  # Raw resets: 1-6, then the $PATH-printed-elsewhere lines 10 and 11. Fail-open
  # forms: 7 (prefix assignment in a substitution), 15 (env), 16 (prefix), 17
  # (export) and 18 (local).
  [ "${#lines[@]}" -eq 13 ]
  local _n _got
  _got=" $(printf '%s ' "${lines[@]%%:*}") "
  for _n in 1 2 3 4 5 6 7 10 11 15 16 17 18; do
    [[ "${_got}" == *" ${_n} "* ]] || { printf 'not flagged: line %s\n' "${_n}" >&2; return 1; }
  done
  for _n in 8 9 12 13 14 19 20; do
    [[ "${_got}" != *" ${_n} "* ]] || { printf 'wrongly flagged: line %s\n' "${_n}" >&2; return 1; }
  done
}

@test "the PATH-reset guard fails on an unreadable file instead of reading clean" {
  run _unguarded_path_resets "${BATS_TEST_TMPDIR}/does-not-exist.bats"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"cannot read"* ]]
}

@test "no tracked bats file resets PATH without refusing_sudo_path or builds it fail-open" {
  # A raw reset drops the refusing stub; refusing_sudo_path is the only route.
  # This file is skipped: its seed cases above are deliberate violations.
  local -a _files=()
  local _f
  while IFS= read -r -d '' _f; do
    [[ ${_f} == tests/suite_isolation.bats ]] || _files+=("${REPO_ROOT}/${_f}")
  done < <(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}" ls-files -z '*.bats')
  # An empty list would pass vacuously.
  [ "${#_files[@]}" -gt 100 ]
  run _unguarded_path_resets "${_files[@]}"
  [ "${status}" -eq 1 ] || { printf '%s\n' "${output}" >&2; return 1; }
}

# ── root-path guard wiring ────────────────────────────────────────────────────
# assert_no_real_root_paths (tests/helpers/common.bash) judges a test only when
# its file's teardown() calls it, so each file that calls load_mocks must.

# The lines of <file>'s teardown() body, without comment and blank lines.
_teardown_body() {
  awk '/^teardown\(\) *\{/ { in_body = 1; next } in_body && /^\}/ { exit } in_body' "$1" \
    | command grep -vE '^[[:space:]]*(#|$)'
}

# True when <file> calls load_mocks as a command: at the start of a line or after
# `&&`, `||`, `;`, `then`, `do`, `if`, `run`, `!` or `{`, and not on a comment
# line. A mention in a comment, a test name or a quoted string is not a call.
_calls_load_mocks() {
  command grep -vE '^[[:space:]]*#' "$1" \
    | command grep -qE '(^|&&|\|\||;|\<then|\<do|\<if|\<run|!|\{)[[:space:]]*load_mocks([[:space:];&|)]|$)'
}

# True when <file>'s teardown() calls assert_no_real_root_paths in a form that
# fails the test. bats ignores a failing command in teardown unless it is the
# last one, so the call sits at the body's top level (two-space indent) as
#   (a) `assert_no_real_root_paths || return 1`,
#   (b) `assert_no_real_root_paths || _root_paths=1` with a later
#       `return "${_root_paths}"`, or
#   (c) a bare call that is the last statement of the body.
# `|| true`, a quoted mention, a call nested in a conditional and a redefinition
# of the function in the file all fail. Redefinition and nesting are matched by
# shape, not parsed; the fixtures below pin each.
_teardown_guard_effective() {
  local _f="$1" _line _i _guard_at=-1 _form=""
  local -a _body=()
  ! command grep -qE '^[[:space:]]*(function[[:space:]]+)?assert_no_real_root_paths[[:space:]]*(\(\))?[[:space:]]*\{' "${_f}" || return 1
  mapfile -t _body < <(_teardown_body "${_f}")
  for _i in "${!_body[@]}"; do
    _line="${_body[${_i}]}"
    case "${_line}" in
      '  assert_no_real_root_paths || return 1') _guard_at="${_i}"; _form=a ;;
      '  assert_no_real_root_paths || _root_paths=1') _guard_at="${_i}"; _form=b ;;
      '  assert_no_real_root_paths') _guard_at="${_i}"; _form=c ;;
    esac
  done
  case "${_form}" in
    a) return 0 ;;
    c) (( _guard_at == ${#_body[@]} - 1 )) ;;
    b)
      for (( _i = _guard_at + 1; _i < ${#_body[@]}; _i++ )); do
        [[ ${_body[${_i}]} == '  return "${_root_paths}"' ]] && return 0
      done
      return 1 ;;
    *) return 1 ;;
  esac
}

# Print each given file that calls load_mocks but whose teardown() lacks an
# effective guard.
_files_missing_root_guard() {
  local _f
  for _f in "$@"; do
    [[ -r ${_f} ]] || { printf '_files_missing_root_guard: cannot read %s\n' "${_f}" >&2; return 2; }
    _calls_load_mocks "${_f}" || continue
    _teardown_guard_effective "${_f}" || printf '%s\n' "${_f}"
  done
}

# A fixture file: setup calls load_mocks, teardown holds the given body lines.
_wiring_fixture() {
  local _name="$1"
  shift
  { printf 'setup() {\n  load_mocks\n}\nteardown() {\n'; printf '%s\n' "$@"; printf '}\n'; } \
    > "${BATS_TEST_TMPDIR}/wiring/${_name}.bats"
}

@test "the root-guard wiring check passes the three effective forms and flags every other shape" {
  local _d="${BATS_TEST_TMPDIR}/wiring" _n
  mkdir -p "${_d}"
  # Effective.
  _wiring_fixture good_a '  assert_no_real_root_paths || return 1' '  rm -f x'
  _wiring_fixture good_b '  local _root_paths=0' '  assert_no_real_root_paths || _root_paths=1' '  rm -f x' '  return "${_root_paths}"'
  _wiring_fixture good_c '  rm -f x' '  # trailing comment' '  assert_no_real_root_paths' ''
  # Ineffective.
  _wiring_fixture bare_not_last '  assert_no_real_root_paths' '  rm -f x'
  _wiring_fixture or_true '  assert_no_real_root_paths || true'
  _wiring_fixture quoted '  : "assert_no_real_root_paths"'
  _wiring_fixture comment_only '  # assert_no_real_root_paths || return 1' '  :'
  _wiring_fixture nested '  if false; then' '    assert_no_real_root_paths || return 1' '  fi'
  _wiring_fixture b_without_return '  local _root_paths=0' '  assert_no_real_root_paths || _root_paths=1' '  rm -f x'
  _wiring_fixture teardown_without '  rm -f x'
  _wiring_fixture redefined '  assert_no_real_root_paths || return 1'
  printf 'assert_no_real_root_paths() { return 0; }\n' >> "${_d}/redefined.bats"
  printf 'setup() {\n  load_mocks\n}\n' > "${_d}/no_teardown.bats"
  printf 'setup() {\n  load_mocks\n}\nteardown() {\n  :\n}\n@test "x" {\n  assert_no_real_root_paths\n}\n' > "${_d}/in_test_body.bats"
  printf '# load_mocks is not called here\nsetup() {\n  :\n}\n' > "${_d}/mention_only.bats"
  run _files_missing_root_guard "${_d}"/*.bats
  [ "${status}" -eq 0 ]
  for _n in bare_not_last or_true quoted comment_only nested b_without_return teardown_without redefined no_teardown in_test_body; do
    [[ "${output}" == *"/${_n}.bats"* ]] || { printf 'not flagged: %s\n' "${_n}" >&2; return 1; }
  done
  for _n in good_a good_b good_c mention_only; do
    [[ "${output}" != *"/${_n}.bats"* ]] || { printf 'wrongly flagged: %s\n' "${_n}" >&2; return 1; }
  done
  [ "${#lines[@]}" -eq 10 ]
  run _files_missing_root_guard "${_d}/absent.bats"
  [ "${status}" -eq 2 ]
}

@test "the load_mocks detector matches every command position and ignores comments and strings" {
  local _d="${BATS_TEST_TMPDIR}/detect" _n
  mkdir -p "${_d}"
  printf 'setup() {\n  load_mocks\n}\n' > "${_d}/plain.bats"
  printf 'setup() {\n  load_mocks;\n}\n' > "${_d}/semicolon.bats"
  printf 'setup() {\n  if load_mocks; then :; fi\n}\n' > "${_d}/if_form.bats"
  printf 'setup() {\n  true && load_mocks\n}\n' > "${_d}/and_form.bats"
  printf 'setup() {\n  false || load_mocks\n}\n' > "${_d}/or_form.bats"
  printf 'setup() {\n  run load_mocks\n}\n' > "${_d}/run_form.bats"
  printf 'setup() {\n  # load_mocks\n  :\n}\n' > "${_d}/comment.bats"
  printf '@test "load_mocks writes nothing" {\n  :\n}\n' > "${_d}/test_name.bats"
  printf 'setup() {\n  printf "%%s\\n" "call load_mocks here"\n}\n' > "${_d}/quoted.bats"
  for _n in plain semicolon if_form and_form or_form run_form; do
    _calls_load_mocks "${_d}/${_n}.bats" || { printf 'missed: %s\n' "${_n}" >&2; return 1; }
  done
  for _n in comment test_name quoted; do
    ! _calls_load_mocks "${_d}/${_n}.bats" || { printf 'wrongly matched: %s\n' "${_n}" >&2; return 1; }
  done
}

# bats_only_seams.bats proves production paths win outside bats, so its recorder
# functions (a non-exec sudo, apt and keyring writers) name /etc, /usr/local and
# /usr/share/keyrings by design on every test; the guard cannot apply there.
# This file is skipped too: its fixture strings spell out load_mocks calls and it
# never calls load_mocks itself.
@test "every bats file that calls load_mocks guards its teardown against real root paths" {
  local -a _files=()
  local _f
  while IFS= read -r -d '' _f; do
    [[ ${_f} == tests/setup_env/bats_only_seams.bats || ${_f} == tests/suite_isolation.bats ]] \
      || _files+=("${REPO_ROOT}/${_f}")
  done < <(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}" ls-files -z '*.bats')
  [ "${#_files[@]}" -gt 100 ]
  run _files_missing_root_guard "${_files[@]}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ] || { printf 'teardown lacks assert_no_real_root_paths:\n%s\n' "${output}" >&2; return 1; }
}

# bats ignores a failing command in teardown() unless it is the last one, so the
# wiring must be `|| return 1` (or the last statement). Run it for real.
@test "a teardown wired with assert_no_real_root_paths fails the test that recorded a root path" {
  mkdir -p "${FX}"
  printf 'source "%s"\n' "${HELPER}" > "${FX}/setup_suite.bash"
  cat > "${FX}/a.bats" << FIXTURE
setup() {
  source "${REPO_ROOT}/tests/helpers/common.bash"
  export MOCK_CALLS_FILE="\${BATS_TEST_TMPDIR}/mock_calls"
}
teardown() {
  assert_no_real_root_paths || return 1
  : cleanup that follows the guard
}
@test "clean" { printf 'ls /tmp\n' > "\${MOCK_CALLS_FILE}"; }
@test "dirty" { printf 'sudo rm -f /etc/x\n' > "\${MOCK_CALLS_FILE}"; }
FIXTURE
  run bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ok 1 clean"* ]]
  [[ "${output}" == *"not ok 2 dirty"* ]]
}

@test "a bare guard call that is not the last statement of teardown does not fail the test" {
  mkdir -p "${FX}"
  printf 'source "%s"\n' "${HELPER}" > "${FX}/setup_suite.bash"
  cat > "${FX}/a.bats" << FIXTURE
setup() {
  source "${REPO_ROOT}/tests/helpers/common.bash"
  export MOCK_CALLS_FILE="\${BATS_TEST_TMPDIR}/mock_calls"
}
teardown() {
  assert_no_real_root_paths
  :
}
@test "dirty" { printf 'sudo rm -f /etc/x\n' > "\${MOCK_CALLS_FILE}"; }
FIXTURE
  run bats "${FX}/a.bats" < /dev/null
  # This is why every wiring line ends in `|| return 1`: without it the hit is lost.
  [ "${status}" -eq 0 ]
}
