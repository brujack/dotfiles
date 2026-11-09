#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Fixed clock: cutoff = 2026-10-26T19:00:00Z (14 days earlier). OLD is aged,
# FRESH is inside the cooldown.
OLD="2026-10-01T00:00:00Z"
AGED="2026-10-10T00:00:00Z"
FRESH="2026-11-08T00:00:00Z"
CUTOFF="2026-10-26T19:00:00Z"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/refresh-uv-lock.sh"
  FIXTURE="${BATS_TEST_TMPDIR}/root"
  LOCKS="${BATS_TEST_TMPDIR}/locks"
  mkdir -p "${FIXTURE}" "${LOCKS}"
  export REFRESH_UV_LOCK_ROOT="${FIXTURE}"
  export _UV_BIN="${REPO_ROOT}/tests/stubs/uv-refresh-stub"
  export _MAKE_BIN="${REPO_ROOT}/tests/stubs/make-refresh-stub"
  export STUB_MAKE_LOG="${BATS_TEST_TMPDIR}/make.log"
  export STUB_UV_ARGS_LOG="${BATS_TEST_TMPDIR}/uv.args"
  export STUB_UV_LOCK_DIR="${LOCKS}"
  export REFRESH_COOLDOWN_NOW="2026-11-09T19:00:00Z"
  unset _DOWNGRADE_HELPER _COOLDOWN_HELPER
  BODY="${BATS_TEST_TMPDIR}/body.md"
  unset STUB_UV_LINES STUB_UV_EXIT STUB_UV_FAIL_CALL STUB_MAKE_FAIL
  unset WRAP_FAIL_SUB WRAP_FAIL_RC WRAP_DIFF_TEXT
}

# _lock FILE SPEC...: write a minimal valid lock. SPEC is
# name,version,upload-time[,wheel-upload-time]; a repeated name is a fork.
_lock() {
  local file="${1}" spec name version up wheel
  shift
  printf 'version = 1\nrequires-python = ">=3.12"\n' > "${file}"
  for spec in "$@"; do
    IFS=, read -r name version up wheel <<< "${spec}"
    printf '\n[[package]]\nname = "%s"\nversion = "%s"\n' "${name}" "${version}" >> "${file}"
    printf 'source = { registry = "https://pypi.org/simple" }\n' >> "${file}"
    printf 'sdist = { url = "u", hash = "h", size = 1, upload-time = "%s" }\n' "${up}" >> "${file}"
    if [[ -n "${wheel}" ]]; then
      printf 'wheels = [{ url = "w", hash = "h", size = 1, upload-time = "%s" }]\n' "${wheel}" >> "${file}"
    fi
  done
}

# One aged package moving 1.0 -> 2.0: nothing is held.
_simple_change() {
  _lock "${FIXTURE}/uv.lock" "acme,1.0,${OLD}"
  _lock "${LOCKS}/1.lock" "acme,2.0,${OLD}"
  export STUB_UV_LINES='Updated acme v1.0 -> v2.0'
}

# acme gains a fresh 2.0 (aged 1.1 exists); other moves 5.0 -> 6.0, aged.
_capped_change() {
  _lock "${FIXTURE}/uv.lock" "acme,1.0,${OLD}" "other,5.0,${OLD}"
  _lock "${LOCKS}/1.lock" "acme,2.0,${FRESH}" "other,6.0,${OLD}"
  _lock "${LOCKS}/2.lock" "acme,1.1,${AGED}" "other,6.0,${OLD}"
  cp "${LOCKS}/2.lock" "${LOCKS}/3.lock"
  export STUB_UV_LINES=$'Updated acme v1.0 -> v2.0\nUpdated other v5.0 -> v6.0'
}

# A cooldown helper that fails one subcommand or fakes diff output, and
# otherwise runs the real helper.
_wrap_helper() {
  cat > "${BATS_TEST_TMPDIR}/wrap.py" <<'PY'
import os
import subprocess
import sys

sub = sys.argv[1]
if sub == os.environ.get("WRAP_FAIL_SUB"):
    sys.exit(int(os.environ.get("WRAP_FAIL_RC", "2")))
if sub == "diff" and os.environ.get("WRAP_DIFF_TEXT"):
    print(os.environ["WRAP_DIFF_TEXT"])
    sys.exit(0)
sys.exit(subprocess.call([sys.executable, os.environ["WRAP_REAL"], *sys.argv[1:]]))
PY
  export WRAP_REAL="${REPO_ROOT}/scripts/uv_lock_cooldown.py"
  export _COOLDOWN_HELPER="${BATS_TEST_TMPDIR}/wrap.py"
}

run_script() {
  run --separate-stderr bash "${SCRIPT}" "${BODY}" < /dev/null
}

@test "unchanged lock prints no changes, writes no body and calls uv once" {
  _lock "${FIXTURE}/uv.lock" "acme,1.0,${OLD}"
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "no changes" ]
  [ ! -e "${BODY}" ]
  [ ! -e "${STUB_MAKE_LOG}" ]
  [ "$(wc -l < "${STUB_UV_ARGS_LOG}")" -eq 1 ]
}

@test "no fresh change makes exactly one uv call" {
  _simple_change
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
  [ "$(wc -l < "${STUB_UV_ARGS_LOG}")" -eq 1 ]
  [[ "${output}" != *"Held by"* ]]
  ! command grep -qF 'Held by the 14-day cooldown' "${BODY}"
}

@test "a fresh change is capped and the body lists it" {
  _capped_change
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
  [ "$(sed -n 1p "${STUB_UV_ARGS_LOG}")" = "uv lock --upgrade --color never" ]
  [ "$(sed -n 2p "${STUB_UV_ARGS_LOG}")" = "uv lock --color never --upgrade-package acme --exclude-newer-package acme=${CUTOFF}" ]
  [ "$(sed -n 3p "${STUB_UV_ARGS_LOG}")" = "uv lock --color never" ]
  [ "$(wc -l < "${STUB_UV_ARGS_LOG}")" -eq 3 ]
  command grep -qF '### Held by the 14-day cooldown' "${BODY}"
  command grep -qxF -- "- acme: newest 2.0 uploaded ${FRESH}; took 1.1" "${BODY}"
  command grep -qF 'Updated acme v1.0 -> v1.1' "${BODY}"
  command grep -qF 'Updated other v5.0 -> v6.0' "${BODY}"
}

@test "the cap cutoff is the helper's cutoff for the clock and 14 days" {
  _capped_change
  run_script
  [ "${status}" -eq 0 ]
  local want
  want="$(python3 "${REPO_ROOT}/scripts/uv_lock_cooldown.py" cutoff "${REFRESH_COOLDOWN_NOW}" 14)"
  [ "${want}" = "${CUTOFF}" ]
  command grep -qF -- "--exclude-newer-package acme=${want}" "${STUB_UV_ARGS_LOG}"
}

@test "REFRESH_COOLDOWN_DAYS equals renovate.json's minimumReleaseAge" {
  local days age
  days="$(command grep -oE '^readonly REFRESH_COOLDOWN_DAYS=[0-9]+' "${SCRIPT}" | cut -d= -f2)"
  age="$(python3 - "${REPO_ROOT}/renovate.json" <<'PY'
import json
import re
import sys

def find(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "minimumReleaseAge":
                yield value
            yield from find(value)
    elif isinstance(node, list):
        for item in node:
            yield from find(item)

ages = {re.fullmatch(r"(\d+) days?", v).group(1) for v in find(json.load(open(sys.argv[1])))}
print(ages.pop() if len(ages) == 1 else "mixed")
PY
)"
  [ -n "${days}" ]
  [ "${days}" = "${age}" ]
}

@test "the final uv.lock holds no exclude-newer after a cap" {
  _capped_change
  {
    cat "${LOCKS}/2.lock"
    printf '\n[options]\nexclude-newer-package = { acme = "%s" }\n\n[options.exclude-newer-package]\nacme = "%s"\n' "${CUTOFF}" "${CUTOFF}"
  } > "${LOCKS}/2.lock.new"
  mv "${LOCKS}/2.lock.new" "${LOCKS}/2.lock"
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
  ! command grep -q 'exclude-newer' "${FIXTURE}/uv.lock"
}

@test "a cap that restores every version is no changes and leaves uv.lock as it was" {
  _lock "${FIXTURE}/uv.lock" "acme,1.0,${OLD}"
  _lock "${LOCKS}/1.lock" "acme,2.0,${FRESH}"
  _lock "${LOCKS}/2.lock" "acme,1.0,${OLD},${OLD}"
  cp "${LOCKS}/2.lock" "${LOCKS}/3.lock"
  export STUB_UV_LINES='Updated acme v1.0 -> v2.0'
  cp "${FIXTURE}/uv.lock" "${BATS_TEST_TMPDIR}/base.lock"
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "no changes" ]
  cmp -s "${FIXTURE}/uv.lock" "${BATS_TEST_TMPDIR}/base.lock"
  [ ! -e "${BODY}" ]
  [ ! -e "${STUB_MAKE_LOG}" ]
}

@test "a re-resolve that keeps a fresh version is not honoured" {
  _capped_change
  _lock "${LOCKS}/2.lock" "acme,2.0,${FRESH}" "other,6.0,${OLD}"
  cp "${LOCKS}/2.lock" "${LOCKS}/3.lock"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cooldown not honoured: acme"* ]]
  [ ! -e "${BODY}" ]
  [ ! -e "${STUB_MAKE_LOG}" ]
}

@test "a failed re-resolve is named" {
  _capped_change
  export STUB_UV_FAIL_CALL=2
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cooldown re-resolve failed"* ]]
  [ ! -e "${BODY}" ]
}

@test "a failed lock rewrite is named" {
  _capped_change
  export STUB_UV_FAIL_CALL=3
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cooldown lock rewrite failed"* ]]
  [ ! -e "${BODY}" ]
}

@test "a failing cooldown helper is reported with its rc at every step" {
  local sub
  for sub in cutoff plan verify diff; do
    _capped_change
    rm -f "${LOCKS}/.calls"
    _lock "${FIXTURE}/uv.lock" "acme,1.0,${OLD}" "other,5.0,${OLD}"
    _wrap_helper
    export WRAP_FAIL_SUB="${sub}" WRAP_FAIL_RC=5
    run_script
    [ "${status}" -eq 1 ]
    [[ "${stderr}" == *"cooldown helper failed (rc 5)"* ]]
    [[ "${output}" != *changed* ]]
    [ ! -e "${BODY}" ]
  done
}

@test "a failing diff is a helper failure, never no changes" {
  _capped_change
  _wrap_helper
  export WRAP_FAIL_SUB=diff WRAP_FAIL_RC=2
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cooldown helper failed (rc 2)"* ]]
  [[ "${output}" != *"no changes"* ]]
}

@test "a missing cooldown helper is a helper failure" {
  _simple_change
  export _COOLDOWN_HELPER="${BATS_TEST_TMPDIR}/absent.py"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cooldown helper failed (rc 2)"* ]]
}

@test "a change uv reported that the diff and the held report lack is refused" {
  _simple_change
  export STUB_UV_LINES=$'Updated acme v1.0 -> v2.0\nUpdated ghost v1.0 -> v2.0'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cooldown change list disagrees with uv: ghost"* ]]
  [ ! -e "${BODY}" ]
}

@test "changed lock writes body with every line and the four review commands" {
  _lock "${FIXTURE}/uv.lock" "acme,5.7.0,${OLD}" "greenlet,3.5.5,${OLD}"
  _lock "${LOCKS}/1.lock" "acme,5.9.0,${OLD}" "cloudpickle,3.1.2,${OLD}"
  export STUB_UV_LINES=$'Updated acme v5.7.0 -> v5.9.0\nAdded cloudpickle v3.1.2\nRemoved greenlet v3.5.5'
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
  command grep -qF 'Updated acme v5.7.0 -> v5.9.0' "${BODY}"
  command grep -qF 'Added cloudpickle v3.1.2' "${BODY}"
  command grep -qF 'Removed greenlet v3.5.5' "${BODY}"
  command grep -qF 'gh pr close chore/uv-lock-refresh && gh pr reopen chore/uv-lock-refresh' "${BODY}"
  command grep -qF 'gh pr merge chore/uv-lock-refresh --squash' "${BODY}"
  command grep -qF 'gh workflow run uv-lock-refresh.yml' "${BODY}"
  command grep -qF 'the auto-merge gate holds bot PRs and a label only re-runs CI' "${BODY}"
  command grep -qF "replaces this PR's contents with a fresh refresh from master" "${BODY}"
  command grep -qF 'changed 3 package entries' "${BODY}"
}

@test "downgrade is refused" {
  _lock "${FIXTURE}/uv.lock" "acme,2.0,${OLD}"
  _lock "${LOCKS}/1.lock" "acme,1.9,${OLD}"
  export STUB_UV_LINES='Updated acme v2.0 -> v1.9'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"refusing downgrade: acme"* ]]
  [[ "${stderr}" == *"yanked"* ]]
  [ ! -e "${STUB_MAKE_LOG}" ]
  [ ! -e "${BODY}" ]
}

@test "comma form downgrade is refused and comma form upgrade passes" {
  _lock "${FIXTURE}/uv.lock" "six,1.15.0,${OLD}" "six,1.16.0,${OLD}"
  _lock "${LOCKS}/1.lock" "six,1.15.0,${OLD}"
  export STUB_UV_LINES='Updated six v1.15.0, v1.16.0 -> v1.15.0'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"refusing downgrade: six"* ]]
  [ ! -e "${BODY}" ]
  rm -f "${LOCKS}/.calls"
  _lock "${FIXTURE}/uv.lock" "six,1.15.0,${OLD}" "six,1.16.0,${OLD}"
  _lock "${LOCKS}/1.lock" "six,1.16.0,${OLD}"
  export STUB_UV_LINES='Updated six v1.15.0, v1.16.0 -> v1.16.0'
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
}

@test "unparseable Updated line is refused" {
  _simple_change
  _wrap_helper
  export WRAP_DIFF_TEXT='Updated acme sideways'
  export STUB_UV_LINES='Updated acme v1.0 -> v2.0'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"unparseable: Updated acme sideways"* ]]
  [ ! -e "${BODY}" ]
}

@test "uv failure exits 1 with its own message" {
  _simple_change
  export STUB_UV_EXIT=2
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"uv lock --upgrade failed"* ]]
  [[ "${stderr}" == *"STUB-UV-SENTINEL"* ]]
  [ ! -e "${BODY}" ]
}

@test "sync-requirements-ci failure is named" {
  _simple_change
  export STUB_MAKE_FAIL=sync-requirements-ci
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"make sync-requirements-ci failed"* ]]
  [ ! -e "${BODY}" ]
}

@test "check-lock failure is named" {
  _simple_change
  export STUB_MAKE_FAIL=check-lock
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"make check-lock failed"* ]]
  [ ! -e "${BODY}" ]
}

@test "check-requirements-ci failure is named" {
  _simple_change
  export STUB_MAKE_FAIL=check-requirements-ci
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"make check-requirements-ci failed"* ]]
  [ ! -e "${BODY}" ]
}

@test "both checks run with REQUIRE_TOOLS=1 and the sync does not" {
  _simple_change
  unset REQUIRE_TOOLS
  run_script
  [ "${status}" -eq 0 ]
  command grep -qx 'sync-requirements-ci REQUIRE_TOOLS=unset' "${STUB_MAKE_LOG}"
  command grep -qx 'check-lock REQUIRE_TOOLS=1' "${STUB_MAKE_LOG}"
  command grep -qx 'check-requirements-ci REQUIRE_TOOLS=1' "${STUB_MAKE_LOG}"
}

@test "stub sentinel stays off stdout and the last line is the result word" {
  _simple_change
  run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "changed" ]
  [[ "${output}" != *"STUB-UV-SENTINEL"* ]]
  [[ "${output}" != *"STUB-MAKE-SENTINEL"* ]]
  [[ "${stderr}" == *"STUB-UV-SENTINEL"* ]]
  [[ "${stderr}" == *"STUB-MAKE-SENTINEL"* ]]
}

@test "uv runs with --color never" {
  _simple_change
  run_script
  [ "${status}" -eq 0 ]
  command grep -qx 'uv lock --upgrade --color never' "${STUB_UV_ARGS_LOG}"
}

@test "lowest-fork downgrade is refused" {
  _lock "${FIXTURE}/uv.lock" "a,1.0,${OLD}" "a,3.0,${OLD}"
  _lock "${LOCKS}/1.lock" "a,0.5,${OLD}" "a,3.0,${OLD}"
  export STUB_UV_LINES='Updated a v1.0, v3.0 -> v0.5, v3.0'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"refusing downgrade: a"* ]]
  [ ! -e "${BODY}" ]
}

@test "helper crash is reported as a failed check, not a downgrade" {
  _simple_change
  printf 'raise RuntimeError("boom")\n' > "${BATS_TEST_TMPDIR}/crash.py"
  export _DOWNGRADE_HELPER="${BATS_TEST_TMPDIR}/crash.py"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"downgrade check failed"* ]]
  [[ "${stderr}" != *"refusing downgrade"* ]]
  [[ "${stderr}" != *"yanked"* ]]
  [ ! -e "${BODY}" ]
}

@test "helper rc 1 with no offenders is a crash, not a downgrade" {
  _simple_change
  printf 'import sys\nsys.exit(1)\n' > "${BATS_TEST_TMPDIR}/rc1.py"
  export _DOWNGRADE_HELPER="${BATS_TEST_TMPDIR}/rc1.py"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"downgrade check failed (helper rc 1)"* ]]
  [[ "${stderr}" != *"yanked"* ]]
  [ ! -e "${BODY}" ]
}

@test "unexpected helper rc is a failed check and writes no body" {
  _simple_change
  printf 'import sys\nsys.exit(5)\n' > "${BATS_TEST_TMPDIR}/rc5.py"
  export _DOWNGRADE_HELPER="${BATS_TEST_TMPDIR}/rc5.py"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"helper rc 5"* ]]
  [ ! -e "${BODY}" ]
  [ ! -e "${STUB_MAKE_LOG}" ]
}

@test "two downgrades are both named" {
  _lock "${FIXTURE}/uv.lock" "a,2.0,${OLD}" "b,3.0,${OLD}"
  _lock "${LOCKS}/1.lock" "a,1.0,${OLD}" "b,2.0,${OLD}"
  export STUB_UV_LINES=$'Updated a v2.0 -> v1.0\nUpdated b v3.0 -> v2.0'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"refusing downgrade: a, b"* ]]
  [ ! -e "${BODY}" ]
}

@test "downgrade helper missing is reported as a failed check" {
  _simple_change
  export _DOWNGRADE_HELPER="${BATS_TEST_TMPDIR}/absent.py"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"downgrade check failed (helper rc 2)"* ]]
  [ ! -e "${BODY}" ]
}

@test "missing body-file argument exits 2" {
  run --separate-stderr bash "${SCRIPT}" < /dev/null
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"usage"* ]]
}

@test "unreachable root exits 1 before anything downstream runs" {
  export REFRESH_UV_LOCK_ROOT="${BATS_TEST_TMPDIR}/nope"
  # A cwd with no uv.lock, so a missing return cannot fall through to the
  # repo root's real lock and still exit 1 by another route.
  cd "${BATS_TEST_TMPDIR}"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot cd"* ]]
  [[ "${stderr}" != *"cannot read uv.lock"* ]]
  [ ! -e "${STUB_UV_ARGS_LOG}" ]
  [ ! -e "${BODY}" ]
}

@test "missing uv.lock exits 1 before uv runs" {
  rm -f "${FIXTURE}/uv.lock"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot read uv.lock"* ]]
  [ ! -e "${STUB_UV_ARGS_LOG}" ]
  [ ! -e "${BODY}" ]
}

@test "unwritable body file exits 1 and never reports changed" {
  _simple_change
  BODY="${BATS_TEST_TMPDIR}/nodir/body.md"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot write"* ]]
  [[ "${output}" != *changed* ]]
}

# The make stub accepts any target, so pin the script's targets to real
# Makefile rules: exactly three, each defined.
@test "every make target the script runs is a Makefile rule" {
  local targets t
  targets="$(command grep -oE '_refresh_make [a-z-]+' "${SCRIPT}" | cut -d' ' -f2 | LC_ALL=C sort -u)"
  [ "$(printf '%s\n' "${targets}" | command grep -c .)" -eq 3 ]
  for t in ${targets}; do
    command grep -qE "^${t}:" "${REPO_ROOT}/Makefile"
  done
}

@test "relative body-file resolves against the caller's cwd" {
  _simple_change
  cd "${BATS_TEST_TMPDIR}"
  run --separate-stderr bash "${SCRIPT}" rel-body.md < /dev/null
  [ "${status}" -eq 0 ]
  [ -s "${BATS_TEST_TMPDIR}/rel-body.md" ]
}

@test "no temp dir is left behind" {
  _simple_change
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMPDIR}"
  run_script
  [ "${status}" -eq 0 ]
  [ -z "$(ls -A "${TMPDIR}")" ]
}
