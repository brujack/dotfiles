#!/usr/bin/env bats
# Tests for scripts/root-writes.sh, the filesystem scan ci.yml runs around the
# bats suite to catch writes to real host roots (/etc /usr/local
# /usr/share/keyrings /opt). Every test scans fixture roots under
# BATS_TEST_TMPDIR through ROOT_WRITES_ROOTS; none touches a real root.
#
# No test runs the real sudo. ROOT_WRITES_SUDO always names a stub created
# below (an "ok" stub that drops -n and execs the rest, or a refusing one), and
# every PATH a test builds goes through refusing_sudo_path.
#
# Timing: -newer/-cnewer compare to the marker's mtime, and a kernel stamps a
# change with a coarse clock that can lag the wall clock by a few ms. _arm
# therefore dates the marker one whole second after the fixtures were built,
# then waits past it, so a change made afterwards is always strictly newer and
# a fixture is always strictly older.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  SCRIPT="${REPO_ROOT}/scripts/root-writes.sh"
  TMP="$(cd "${BATS_TEST_TMPDIR}" && pwd -P)"
  STUBS="${TMP}/stubs"
  mkdir -p "${STUBS}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${STUBS}/sudo-refuse"
  printf '#!/usr/bin/env bash\n[[ "$1" == -n ]] && shift\nexec "$@"\n' > "${STUBS}/sudo-ok"
  chmod +x "${STUBS}/sudo-refuse" "${STUBS}/sudo-ok"
  # A find that replays canned output, for statuses a real find cannot be made to return.
  mkdir -p "${STUBS}/findbin"
  cat > "${STUBS}/findbin/find" <<'FIND'
#!/usr/bin/env bash
cat "${FAKE_FIND_OUT}"
cat "${FAKE_FIND_ERR}" >&2
exit "${FAKE_FIND_RC}"
FIND
  chmod +x "${STUBS}/findbin/find"
  PATH="$(refusing_sudo_path "${PATH}")" || return 1
  export PATH
  export ROOT_WRITES_SUDO="${STUBS}/sudo-refuse"
  ROOT="${TMP}/root"
  MARKER="${TMP}/marker"
  mkdir -p "${ROOT}/d"
  : > "${ROOT}/a"
  : > "${ROOT}/d/b"
  : > "${ROOT}/d/c"
  export ROOT_WRITES_ROOTS="${ROOT}"
}

teardown() {
  # Cleanup only: tests chmod fixture directories to 000.
  chmod -R u+rwx "${BATS_TEST_TMPDIR}" 2> /dev/null || true
}

# _touch_epoch <epoch> <file> -- GNU date takes -d @N, BSD date takes -r N.
_touch_epoch() {
  local _t
  _t="$(date -d "@$1" +%Y%m%d%H%M.%S 2> /dev/null || date -r "$1" +%Y%m%d%H%M.%S)" || return 1
  touch -t "${_t}" "$2"
}

# _arm -- mark, then place the marker between the fixtures and what follows.
_arm() {
  local _s
  _s="$(date +%s)"
  bash "${SCRIPT}" mark "${MARKER}" || return 1
  _touch_epoch $((_s + 1)) "${MARKER}" || return 1
  sleep 1.2
}

_check() {
  run bash "${SCRIPT}" check "${MARKER}"
}

_has_line() {
  printf '%s\n' "${output}" | command grep -Fxq -- "$1"
}

# Wrapped negations: bats ignores a bare `!` (SC2314), a function's status counts.
_lacks_line() {
  ! _has_line "$1"
}

@test "mark creates the marker file" {
  run bash "${SCRIPT}" mark "${MARKER}"
  [ "${status}" -eq 0 ]
  [ -f "${MARKER}" ]
}

@test "mark exits 1 when the marker cannot be created" {
  run bash "${SCRIPT}" mark "${TMP}/no-such-dir/marker"
  [ "${status}" -eq 1 ]
}

@test "mark exits 1 without a marker argument" {
  run bash "${SCRIPT}" mark
  [ "${status}" -eq 1 ]
}

@test "check reports nothing and the visited count when nothing changed" {
  _arm
  _check
  [ "${status}" -eq 0 ]
  [ "${output}" = "root-writes: none (${ROOT} 4)" ]
}

@test "check reports a file created after the marker" {
  _arm
  : > "${ROOT}/new"
  _check
  [ "${status}" -eq 1 ]
  _has_line "root-writes: the suite changed real host paths:"
  _has_line "${ROOT}/new"
  _lacks_line "${ROOT}/a"
}

@test "check reports a file rewritten after the marker" {
  _arm
  printf 'x' > "${ROOT}/a"
  _check
  [ "${status}" -eq 1 ]
  _has_line "${ROOT}/a"
}

@test "check reports a chmod after the marker (ctime only)" {
  _arm
  chmod 600 "${ROOT}/d/b"
  _check
  [ "${status}" -eq 1 ]
  _has_line "${ROOT}/d/b"
}

@test "check reports the directory of a file deleted after the marker" {
  _arm
  rm "${ROOT}/d/b"
  _check
  [ "${status}" -eq 1 ]
  _has_line "${ROOT}/d"
  _lacks_line "${ROOT}/d/b"
}

@test "check resolves a symlinked root and reports a file created through it" {
  ln -s "${ROOT}" "${TMP}/link"
  export ROOT_WRITES_ROOTS="${TMP}/link"
  _arm
  : > "${TMP}/link/new"
  _check
  [ "${status}" -eq 1 ]
  _has_line "${ROOT}/new"
}

@test "check reports a root given as a symlink as scanned, not empty" {
  ln -s "${ROOT}" "${TMP}/link"
  export ROOT_WRITES_ROOTS="${TMP}/link"
  _arm
  _check
  [ "${status}" -eq 0 ]
  [ "${output}" = "root-writes: none (${TMP}/link 4)" ]
}

@test "check names an empty root and does not fail" {
  mkdir "${TMP}/hollow"
  export ROOT_WRITES_ROOTS="${TMP}/hollow"
  _arm
  _check
  [ "${status}" -eq 0 ]
  _has_line "empty: ${TMP}/hollow"
}

@test "check fails when the root listing is refused" {
  [[ ${EUID} -ne 0 ]] || skip "root reads any directory, so no listing is refused"
  _arm
  chmod 111 "${ROOT}"
  _check
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"listing of ${ROOT} refused"* ]]
}

@test "check fails when a non-empty root is walked but nothing below it is visited" {
  _arm
  printf '%s\n' "${ROOT}" > "${TMP}/find.out"
  : > "${TMP}/find.err"
  PATH="${STUBS}/findbin:${PATH}" FAKE_FIND_OUT="${TMP}/find.out" FAKE_FIND_ERR="${TMP}/find.err" FAKE_FIND_RC=0 \
    run bash "${SCRIPT}" check "${MARKER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"visited nothing"* ]]
}

@test "check without sudo names an unreadable directory and still reports a hit beside it" {
  [[ ${EUID} -ne 0 ]] || skip "root reads any directory, so nothing is unreadable"
  mkdir "${ROOT}/locked"
  chmod 000 "${ROOT}/locked"
  _arm
  : > "${ROOT}/beside"
  _check
  [ "${status}" -eq 1 ]
  _has_line "not scanned: ${ROOT}/locked"
  _has_line "${ROOT}/beside"
}

@test "check without sudo passes with an unreadable directory and no hit" {
  [[ ${EUID} -ne 0 ]] || skip "root reads any directory, so nothing is unreadable"
  mkdir "${ROOT}/locked"
  chmod 000 "${ROOT}/locked"
  _arm
  _check
  [ "${status}" -eq 0 ]
  _has_line "not scanned: ${ROOT}/locked"
  [[ "${output}" == *"root-writes: none ("* ]]
}

@test "check without sudo fails on a stderr line that is not Permission denied" {
  _arm
  printf '%s\n' "${ROOT}" "${ROOT}/a" > "${TMP}/find.out"
  printf '%s\n' "find: '${ROOT}/a': No such file or directory" > "${TMP}/find.err"
  PATH="${STUBS}/findbin:${PATH}" FAKE_FIND_OUT="${TMP}/find.out" FAKE_FIND_ERR="${TMP}/find.err" FAKE_FIND_RC=1 \
    run bash "${SCRIPT}" check "${MARKER}"
  [ "${status}" -eq 1 ]
}

@test "check without sudo fails when one stderr line is Permission denied and another is not" {
  _arm
  printf '%s\n' "${ROOT}" "${ROOT}/a" > "${TMP}/find.out"
  printf '%s\n' "find: '${ROOT}/d': Permission denied" "find: oops" > "${TMP}/find.err"
  PATH="${STUBS}/findbin:${PATH}" FAKE_FIND_OUT="${TMP}/find.out" FAKE_FIND_ERR="${TMP}/find.err" FAKE_FIND_RC=1 \
    run bash "${SCRIPT}" check "${MARKER}"
  [ "${status}" -eq 1 ]
}

@test "check without sudo fails on a find status other than 1" {
  _arm
  printf '%s\n' "${ROOT}" "${ROOT}/a" > "${TMP}/find.out"
  printf '%s\n' "find: '${ROOT}/d': Permission denied" > "${TMP}/find.err"
  PATH="${STUBS}/findbin:${PATH}" FAKE_FIND_OUT="${TMP}/find.out" FAKE_FIND_ERR="${TMP}/find.err" FAKE_FIND_RC=2 \
    run bash "${SCRIPT}" check "${MARKER}"
  [ "${status}" -eq 1 ]
}

@test "check accepts a Permission denied status 1 from the stub find without sudo" {
  _arm
  printf '%s\n' "${ROOT}" "${ROOT}/a" > "${TMP}/find.out"
  printf '%s\n' "find: '${ROOT}/d': Permission denied" > "${TMP}/find.err"
  PATH="${STUBS}/findbin:${PATH}" FAKE_FIND_OUT="${TMP}/find.out" FAKE_FIND_ERR="${TMP}/find.err" FAKE_FIND_RC=1 \
    run bash "${SCRIPT}" check "${MARKER}"
  [ "${status}" -eq 0 ]
  _has_line "not scanned: ${ROOT}/d"
}

@test "check with sudo runs find through it and passes a clean walk" {
  export ROOT_WRITES_SUDO="${STUBS}/sudo-ok"
  _arm
  _check
  [ "${status}" -eq 0 ]
  [ "${output}" = "root-writes: none (${ROOT} 4)" ]
}

@test "check with sudo reports a hit" {
  export ROOT_WRITES_SUDO="${STUBS}/sudo-ok"
  _arm
  : > "${ROOT}/new"
  _check
  [ "${status}" -eq 1 ]
  _has_line "${ROOT}/new"
}

@test "check with sudo fails on any non-zero find status, even Permission denied" {
  export ROOT_WRITES_SUDO="${STUBS}/sudo-ok"
  _arm
  printf '%s\n' "${ROOT}" "${ROOT}/a" > "${TMP}/find.out"
  printf '%s\n' "find: '${ROOT}/d': Permission denied" > "${TMP}/find.err"
  PATH="${STUBS}/findbin:${PATH}" FAKE_FIND_OUT="${TMP}/find.out" FAKE_FIND_ERR="${TMP}/find.err" FAKE_FIND_RC=1 \
    run bash "${SCRIPT}" check "${MARKER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"under sudo"* ]]
}

@test "check exits 1 when the marker is missing" {
  run bash "${SCRIPT}" check "${TMP}/absent-marker"
  [ "${status}" -eq 1 ]
}

@test "check skips a missing root and names it" {
  export ROOT_WRITES_ROOTS="${TMP}/gone ${ROOT}"
  _arm
  _check
  [ "${status}" -eq 0 ]
  _has_line "skipped: ${TMP}/gone (missing)"
  [[ "${output}" == *"root-writes: none (${ROOT} 4)"* ]]
}

@test "ROOT_WRITES_ROOTS and ROOT_WRITES_SUDO are ignored when BATS_TEST_TMPDIR is empty" {
  run env BATS_TEST_TMPDIR= ROOT_WRITES_ROOTS="${ROOT}" bash -c 'source "$1" && _rw_roots' _ "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'/etc\n/usr/local\n/usr/share/keyrings\n/opt' ]
  run bash -c 'source "$1" && _rw_roots' _ "${SCRIPT}"
  [ "${output}" = "${ROOT}" ]
}

@test "ROOT_WRITES_PRUNE is ignored when BATS_TEST_TMPDIR is empty" {
  run env BATS_TEST_TMPDIR= ROOT_WRITES_PRUNE="${ROOT}/d" bash -c 'source "$1" && _rw_prune_list' _ "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "prune: a write beside a pruned subtree is reported" {
  mkdir "${ROOT}/skip" "${ROOT}/keep"
  export ROOT_WRITES_PRUNE="${ROOT}/skip"
  _arm
  : > "${ROOT}/keep/new"
  _check
  [ "${status}" -eq 1 ]
  _has_line "${ROOT}/keep/new"
}

@test "prune: a write inside a pruned subtree is not reported" {
  mkdir "${ROOT}/skip" "${ROOT}/keep"
  export ROOT_WRITES_PRUNE="${ROOT}/skip"
  _arm
  : > "${ROOT}/skip/new"
  _check
  [ "${status}" -eq 0 ]
  [[ "${output}" == "root-writes: none ("* ]]
}

# _prune_overlap <entry> -- succeed when the entry equals, contains or sits
# inside a directory lib/ installs into, or is a glob that could match one.
_prune_overlap() {
  local _e="${1%/}" _f
  [[ -n ${_e} ]] || return 0
  [[ ${_e} == *[\*\?\[]* ]] && return 0
  for _f in /etc/apt /etc/docker /etc/sysctl.d /usr/share/keyrings /usr/local/bin /opt/homebrew \
    /private/etc/apt /private/etc/docker /private/etc/sysctl.d; do
    [[ ${_e} == "${_f}" || ${_f} == "${_e}"/* || ${_e} == "${_f}"/* ]] && return 0
  done
  return 1
}

_no_overlap() {
  ! _prune_overlap "$1"
}

@test "prune lists: no entry overlaps a directory lib installs into" {
  local _entries _e _bad=""
  _entries="$(bash -c 'source "$1"
    printf "%s\n" ${ROOT_WRITES_PRUNE_LINUX[@]+"${ROOT_WRITES_PRUNE_LINUX[@]}"} \
      ${ROOT_WRITES_PRUNE_DARWIN[@]+"${ROOT_WRITES_PRUNE_DARWIN[@]}"}' _ "${SCRIPT}")"
  while IFS= read -r _e; do
    [[ -n ${_e} ]] || continue
    if _prune_overlap "${_e}"; then _bad+="${_e} "; fi
  done <<< "${_entries}"
  [ -z "${_bad}" ]
}

@test "the prune overlap check refuses every forbidden shape and accepts a harmless entry" {
  local _e
  for _e in / /etc /etc/apt /etc/apt/ /etc/apt/sources.list.d '/etc/ap*' /etc/docker /etc/sysctl.d \
    /usr /usr/share/keyrings /usr/local/bin /opt /opt/homebrew /opt/homebrew/Cellar \
    /private/etc/apt /private/etc/docker /private/etc/sysctl.d/90-x.conf; do
    _prune_overlap "${_e}" || { printf 'not refused: %s\n' "${_e}" >&2; return 1; }
  done
  _no_overlap /etc/ssl/certs
  _no_overlap /opt/other
}
