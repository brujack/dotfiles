#!/usr/bin/env bats
# Coverage backfill for lib/package_capture.sh — the "tool present" branches of
# _list_brew_packages/_list_apt_packages/_list_pip_packages, the full
# capture_all_packages flow (all three sources, and the guards that skip a
# source when its tool is absent or reports nothing), the direct-execution
# entry point, and capture_package_diff's error/idempotency behavior.
# tests/test_package_capture.bats already covers the "tool absent" single-line
# guards and the diff-building/ledger-write/ledger-absent paths; this file
# adds the branches that were still uncovered rather than duplicating those.

load '../helpers/common.bash'

setup() {
  ORIGINAL_PATH="${PATH}"
  load_mocks
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/package_capture.sh"
}

teardown() {
  export PATH="${ORIGINAL_PATH}"
}

# Writes an executable at ${dir}/${name} that ignores its arguments and always
# prints ${output} to stdout, exit 0. Used to stand in for brew/dpkg-query/
# pip3/pip with full control over the exact "name version" / tab / JSON shape
# each real tool would produce — the shared tests/mocks/brew and
# tests/mocks/dpkg-query mocks can't reproduce this: tests/mocks/brew expands
# MOCK_BREW_LIST_FORMULA unquoted, so a value containing the name/version
# space (e.g. "wget 1.21.4") gets word-split onto two separate output lines
# instead of staying "name version" on one line.
# Shebang uses the resolved absolute bash path rather than `#!/usr/bin/env
# bash`, and the body uses only the `printf` builtin rather than `cat` — the
# pip-fallback/absent-tool tests run these mocks under a curated PATH that
# deliberately contains nothing but the mock itself and (sometimes) a python3
# symlink, so neither `env` nor `cat` is guaranteed to be resolvable there. A
# shebang or body command that depends on either fails the script with exit
# 127 before it prints anything, which reads as "tool not found" and silently
# defeats the test.
_make_mock_tool() {
  local _name="$1" _output="$2"
  local _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/${_name}" << EOF
#!${_bash_bin}
printf '${_name} %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
printf '%s\n' '${_output}'
exit 0
EOF
  chmod +x "${_dir}/${_name}"
  printf '%s' "${_dir}"
}

# A curated PATH containing only a real python3 (symlinked, not the directory
# it lives in) — used by the pip-fallback and brew/apt-absent tests, which
# need pip3 (and on this fleet's dev machines, brew) to be genuinely
# unreachable. Real pip3/pip live in the same pyenv shims directory as
# python3 on every dev machine this was verified on, so simply prepending a
# mock dir in front of the full PATH is not enough to make pip3 "absent" —
# the real one is still found further down the same PATH.
#
# Resolves sys.executable rather than symlinking `command -v python3` directly
# — on a pyenv machine that IS a shim script (`#!/usr/bin/env bash`), and a
# curated PATH containing only this one directory has no `env`/`bash` for the
# shim to exec, so every python3 call fails with exit 127.
_make_python3_only_dir() {
  local _dir _real_python3
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _real_python3="$(command -v python3)"
  _real_python3="$("${_real_python3}" -c 'import sys; print(sys.executable)' 2>/dev/null || printf '%s' "${_real_python3}")"
  ln -s "${_real_python3}" "${_dir}/python3"
  printf '%s' "${_dir}"
}

# capture_all_packages/capture_package_diff call `cat` (to read
# MACHINE_ID_PATH) and `date` (to stamp captured_at) directly — not just the
# brew/dpkg-query/pip3/python3 tools this file mocks. A curated PATH built to
# make brew/apt/pip3 "absent" also makes cat/date absent, and `cat`'s failure
# is silently indistinguishable from a real missing-machine-id: both hit the
# same `|| { WARNING; return 0; }` guard, which lets a test built on this
# curated PATH assert "no ledger write happened" and pass — for the wrong
# reason, without ever reaching the guard branch it claims to exercise.
_make_coreutils_dir() {
  local _dir
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  ln -s "$(command -v cat)" "${_dir}/cat"
  ln -s "$(command -v date)" "${_dir}/date"
  printf '%s' "${_dir}"
}

# Ledger mock that records every write's payload (one JSON blob per call,
# newline-separated) so a test can assert which source(s) were actually
# captured, not just that "some" write happened.
# Same reason as _make_mock_tool: an absolute bash shebang (not `env bash`)
# and a stdin-capture built from the `read` builtin (not `cat`) —
# capture_all_packages calls this via the plain $LEDGER_BIN path under the
# same curated, coreutils-less PATH used for the brew/apt-absent tests.
# `read -r -d ''` with an empty delimiter reads to EOF in one shot, which is
# fine here: capture_package_diff's payload is single-line JSON (json.dumps
# without an indent argument never embeds a newline).
_make_mock_ledger() {
  local _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/ledger" << EOF
#!${_bash_bin}
IFS= read -r -d '' _payload
printf '%s\n' "\${_payload}" >> "\${MOCK_LEDGER_PAYLOAD_FILE}"
printf 'ledger %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
exit 0
EOF
  chmod +x "${_dir}/ledger"
  printf '%s' "${_dir}/ledger"
}

# ── _list_brew_packages — tool present ──────────────────────────────────────

@test "_list_brew_packages: emits name/version JSON for multiple installed formulae" {
  local _mock_dir
  _mock_dir="$(_make_mock_tool "brew" "$(printf 'wget 1.21.4\ncurl 8.7.1')")"
  PATH="${_mock_dir}:${ORIGINAL_PATH}" run _list_brew_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name": "wget", "version": "1.21.4"'* ]]
  [[ "$output" == *'"name": "curl", "version": "8.7.1"'* ]]
  [ "$(grep -o '"name"' <<< "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "_list_brew_packages: drops a malformed listing line with no version field" {
  local _mock_dir
  _mock_dir="$(_make_mock_tool "brew" "$(printf 'wget 1.21.4\nsolo\ncurl 8.7.1')")"
  PATH="${_mock_dir}:${ORIGINAL_PATH}" run _list_brew_packages
  [ "$status" -eq 0 ]
  [[ "$output" != *'"solo"'* ]]
  [ "$(grep -o '"name"' <<< "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

# ── _list_apt_packages — tool present ───────────────────────────────────────

@test "_list_apt_packages: emits name/version JSON for multiple installed packages" {
  local _mock_dir
  _mock_dir="$(_make_mock_tool "dpkg-query" "$(printf 'wget\t1.21.4\ncurl\t8.7.1')")"
  PATH="${_mock_dir}:${ORIGINAL_PATH}" run _list_apt_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name": "wget", "version": "1.21.4"'* ]]
  [[ "$output" == *'"name": "curl", "version": "8.7.1"'* ]]
}

@test "_list_apt_packages: returns [] when dpkg-query is present but lists nothing" {
  local _mock_dir
  _mock_dir="$(_make_mock_tool "dpkg-query" "")"
  PATH="${_mock_dir}:${ORIGINAL_PATH}" run _list_apt_packages
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ── _list_pip_packages — tool present ───────────────────────────────────────

@test "_list_pip_packages: prefers pip3 over pip when both are present" {
  local _pip3_dir _pip_dir _py_dir
  _pip3_dir="$(_make_mock_tool "pip3" '[{"name": "requests", "version": "2.31.0"}]')"
  _pip_dir="$(_make_mock_tool "pip" '[{"name": "wrong-tool", "version": "9.9.9"}]')"
  _py_dir="$(_make_python3_only_dir)"
  PATH="${_pip3_dir}:${_pip_dir}:${_py_dir}" run _list_pip_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name": "requests"'* ]]
  [[ "$output" != *"wrong-tool"* ]]
}

@test "_list_pip_packages: falls back to pip when pip3 is absent" {
  local _pip_dir _py_dir
  _pip_dir="$(_make_mock_tool "pip" '[{"name": "black", "version": "24.0.0"}]')"
  _py_dir="$(_make_python3_only_dir)"
  PATH="${_pip_dir}:${_py_dir}" run _list_pip_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name": "black", "version": "24.0.0"'* ]]
}

# ── capture_all_packages — full flow and guard branches ─────────────────────

@test "capture_all_packages: captures brew, apt, and pip diffs in one run when all tools present" {
  local _brew_dir _apt_dir _pip_dir _ledger_bin
  _brew_dir="$(_make_mock_tool "brew" "$(printf 'wget 1.21.4')")"
  _apt_dir="$(_make_mock_tool "dpkg-query" "$(printf 'curl\t8.7.1')")"
  _pip_dir="$(_make_mock_tool "pip3" '[{"name": "requests", "version": "2.31.0"}]')"
  _ledger_bin="$(_make_mock_ledger)"
  export MOCK_LEDGER_PAYLOAD_FILE="${BATS_TEST_TMPDIR}/ledger_payloads.txt"
  touch "${MOCK_LEDGER_PAYLOAD_FILE}"
  export LEDGER_BIN="${_ledger_bin}"
  export MACHINE_ID_PATH="${BATS_TEST_TMPDIR}/machine-id"
  printf 'test-machine\n' > "${MACHINE_ID_PATH}"

  PATH="${_brew_dir}:${_apt_dir}:${_pip_dir}:${ORIGINAL_PATH}" run capture_all_packages "run-full"
  [ "$status" -eq 0 ]
  [ "$(grep -c "ledger write" "${MOCK_CALLS_FILE}")" -eq 3 ]
  grep -q '"source": "brew"' "${MOCK_LEDGER_PAYLOAD_FILE}"
  grep -q '"source": "apt"' "${MOCK_LEDGER_PAYLOAD_FILE}"
  grep -q '"source": "pip"' "${MOCK_LEDGER_PAYLOAD_FILE}"
}

@test "capture_all_packages: skips brew and apt capture when neither tool is present" {
  local _pip_dir _py_dir _coreutils_dir _ledger_bin
  _pip_dir="$(_make_mock_tool "pip3" '[{"name": "requests", "version": "2.31.0"}]')"
  _py_dir="$(_make_python3_only_dir)"
  _coreutils_dir="$(_make_coreutils_dir)"
  _ledger_bin="$(_make_mock_ledger)"
  export MOCK_LEDGER_PAYLOAD_FILE="${BATS_TEST_TMPDIR}/ledger_payloads.txt"
  touch "${MOCK_LEDGER_PAYLOAD_FILE}"
  export LEDGER_BIN="${_ledger_bin}"
  export MACHINE_ID_PATH="${BATS_TEST_TMPDIR}/machine-id"
  printf 'test-machine\n' > "${MACHINE_ID_PATH}"

  PATH="${_pip_dir}:${_py_dir}:${_coreutils_dir}" run capture_all_packages "run-pip-only"
  [ "$status" -eq 0 ]
  grep -q "pip3 list" "${MOCK_CALLS_FILE}"
  [ "$(grep -c "ledger write" "${MOCK_CALLS_FILE}")" -eq 1 ]
  grep -q '"source": "pip"' "${MOCK_LEDGER_PAYLOAD_FILE}"
  refute_grep '"source": "brew"' "${MOCK_LEDGER_PAYLOAD_FILE}"
  refute_grep '"source": "apt"' "${MOCK_LEDGER_PAYLOAD_FILE}"
}

@test "capture_all_packages: skips pip capture when the pip package list is empty" {
  local _pip_dir _py_dir _coreutils_dir _ledger_bin
  _pip_dir="$(_make_mock_tool "pip3" "[]")"
  _py_dir="$(_make_python3_only_dir)"
  _coreutils_dir="$(_make_coreutils_dir)"
  _ledger_bin="$(_make_mock_ledger)"
  export MOCK_LEDGER_PAYLOAD_FILE="${BATS_TEST_TMPDIR}/ledger_payloads.txt"
  touch "${MOCK_LEDGER_PAYLOAD_FILE}"
  export LEDGER_BIN="${_ledger_bin}"
  export MACHINE_ID_PATH="${BATS_TEST_TMPDIR}/machine-id"
  printf 'test-machine\n' > "${MACHINE_ID_PATH}"

  # Status is 1, not 0: `[[ "${_curr_pip}" != "[]" ]] && capture_package_diff
  # ...` is the last statement in capture_all_packages, and with no explicit
  # `return` after it, the function's own exit status is whatever that
  # statement's is — a false `[[ ]]` guard, same as any other, exits 1. This
  # only surfaces when pip is the last-considered source AND its list is
  # empty; the brew/apt guards earlier in the function are followed by more
  # code, so their own false case never becomes the function's return value.
  PATH="${_pip_dir}:${_py_dir}:${_coreutils_dir}" run capture_all_packages "run-empty-pip"
  [ "$status" -eq 1 ]
  grep -q "pip3 list" "${MOCK_CALLS_FILE}"
  [ ! -s "${MOCK_LEDGER_PAYLOAD_FILE}" ]
  refute_grep "ledger write" "${MOCK_CALLS_FILE}"
}

# ── capture_package_diff — error path and idempotency ───────────────────────

@test "capture_package_diff: malformed current-package JSON fails python3 and returns 1 without writing to ledger" {
  local _ledger_bin
  _ledger_bin="$(_make_mock_ledger)"
  export MOCK_LEDGER_PAYLOAD_FILE="${BATS_TEST_TMPDIR}/ledger_payloads.txt"
  touch "${MOCK_LEDGER_PAYLOAD_FILE}"
  export LEDGER_BIN="${_ledger_bin}"

  run capture_package_diff "brew" "test-machine" "run-001" "[]" "not-valid-json"
  [ "$status" -eq 1 ]
  [ ! -s "${MOCK_LEDGER_PAYLOAD_FILE}" ]
  refute_grep "ledger write" "${MOCK_CALLS_FILE}"
}

@test "capture_package_diff: capturing the same diff twice is idempotent — no ledger write either time" {
  local _ledger_bin
  _ledger_bin="$(_make_mock_ledger)"
  export MOCK_LEDGER_PAYLOAD_FILE="${BATS_TEST_TMPDIR}/ledger_payloads.txt"
  touch "${MOCK_LEDGER_PAYLOAD_FILE}"
  export LEDGER_BIN="${_ledger_bin}"
  local _pkg='[{"name":"curl","version":"8.0"}]'

  run capture_package_diff "brew" "test-machine" "run-001" "${_pkg}" "${_pkg}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run capture_package_diff "brew" "test-machine" "run-002" "${_pkg}" "${_pkg}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "${MOCK_LEDGER_PAYLOAD_FILE}" ]
}

# ── direct execution (not sourced) ──────────────────────────────────────────

@test "package_capture.sh: running the file directly invokes capture_all_packages" {
  PACKAGE_CAPTURE_ENABLED=false run bash "${REPO_ROOT}/lib/package_capture.sh" "run-direct"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
