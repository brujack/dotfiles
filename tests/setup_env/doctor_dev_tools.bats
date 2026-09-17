#!/usr/bin/env bats

# Covers lib/helpers.sh's _doctor_check_dev_tools.
#
# See docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md,
# Part 6: doctor reports the Linux dev tools that RUN, not merely resolve --
# each probe runs under `timeout` from ${HOME}, since a project-local
# .terraform-version must not steer the result and a hung binary must not
# block doctor. WARN only, never FAIL: every install it reports on is
# advisory.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"

  # A shim directory holding only what each test needs (shell.md: NOT a
  # scrubbed system PATH -- scrubbing removes co-located binaries the test
  # still needs). `timeout` is symlinked to the real one so the arm's
  # `timeout <n> <bin> <args>` wrapping is exercised for real, not mocked --
  # the thing under test is whether OUR arm resolves/wraps/reads rc
  # correctly, not whether `timeout` itself works.
  #
  # PATH is deliberately NOT exported globally here: this test file's own
  # commands (teardown's `rm`, `_write_stub`'s `cat`/`chmod`, the `grep`
  # assertions) need the real PATH. Each invocation of
  # _doctor_check_dev_tools below prefixes PATH="${_BIN_DIR}" on that one
  # command instead -- a bash prefix assignment scopes to the invoked
  # command (and, for a shell function, everything it calls) and reverts
  # once it returns.
  _BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_BIN_DIR}"
  local _real_timeout _real_sleep
  _real_timeout="$(command -v timeout)"
  _real_sleep="$(command -v sleep)"
  ln -s "${_real_timeout}" "${_BIN_DIR}/timeout"
  # The timeout-warning test's stub sleeps past the deadline; an absolute
  # shebang alone does not make `sleep` resolvable from inside the stub's
  # OWN PATH-scoped invocation, since a bare `sleep 3` in the stub body is
  # still a PATH lookup.
  ln -s "${_real_sleep}" "${_BIN_DIR}/sleep"

  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _DOCTOR_WARN=0

  unset LINUX HAS_DEVTOOLS _DOCTOR_PROBE_TIMEOUT
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Writes an executable "${_BIN_DIR}/${1}" whose body is "${2}".
#
# Absolute shebang deliberately, not `#!/usr/bin/env bash`: the whole point
# of these tests is a PATH scoped to ${_BIN_DIR} alone, and `env` would
# have to resolve `bash` through that same truncated PATH and fail with 127
# before the stub's own body ever ran.
_write_stub() {
  local _name="$1" _body="$2"
  cat > "${_BIN_DIR}/${_name}" <<STUB
#!/bin/bash
${_body}
STUB
  chmod +x "${_BIN_DIR}/${_name}"
}

# ── gating: LINUX and HAS_DEVTOOLS ──────────────────────────────────────────

@test "_doctor_check_dev_tools prints nothing without LINUX" {
  export HAS_DEVTOOLS=1
  unset LINUX
  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_doctor_check_dev_tools prints nothing without HAS_DEVTOOLS" {
  export LINUX=1
  unset HAS_DEVTOOLS
  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── PASS: resolves and runs ─────────────────────────────────────────────────

@test "_doctor_check_dev_tools passes a tool that resolves and runs" {
  export LINUX=1 HAS_DEVTOOLS=1
  _write_stub "zig" "exit 0"

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev tools:"* ]]
  # doctor_pass interleaves an ANSI reset code between "[PASS]" and the
  # value (`[PASS]${_NC} %s`), so "[PASS] zig" is never a literal
  # substring of the real output -- grep the zig line, then check IT
  # carries the [PASS] marker, rather than asserting the two tokens
  # anywhere in $output (which zig being the only resolvable stub makes
  # correct today but would stop discriminating if a second stub existed).
  local _zig_line
  _zig_line="$(printf '%s\n' "$output" | grep 'zig')"
  [[ "${_zig_line}" == *"[PASS]"* ]]
}

# ── WARN: unresolvable ───────────────────────────────────────────────────────

@test "_doctor_check_dev_tools warns and names the remedy when a tool is absent" {
  export LINUX=1 HAS_DEVTOOLS=1
  # No stub written for any tool -- every one of the five is unresolvable
  # under this shim PATH.

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  local _tflint_line
  _tflint_line="$(printf '%s\n' "$output" | grep 'tflint')"
  [[ "${_tflint_line}" == *"[WARN]"* ]]
  [[ "${_tflint_line}" == *"tflint: not found — setup_env.sh -t developer"* ]]
  [[ "$output" != *"[FAIL]"* ]]
}

# ── WARN: resolves but does not run -- proves "runs, not resolves" ─────────

@test "_doctor_check_dev_tools warns with the exit code when a tool resolves but exits non-zero" {
  export LINUX=1 HAS_DEVTOOLS=1
  _write_stub "tfsec" "exit 1"

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  local _tfsec_line
  _tfsec_line="$(printf '%s\n' "$output" | grep 'tfsec')"
  [[ "${_tfsec_line}" == *"[WARN]"* ]]
  [[ "${_tfsec_line}" == *"tfsec: does not run (rc 1) — setup_env.sh -t developer"* ]]
}

# ── WARN: timeout ────────────────────────────────────────────────────────────

@test "_doctor_check_dev_tools warns when a tool's probe hangs past the timeout" {
  export LINUX=1 HAS_DEVTOOLS=1
  export _DOCTOR_PROBE_TIMEOUT=1
  _write_stub "terraform" "sleep 3; exit 0"

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  # GNU/uutils timeout's own exit status for a killed process is 124.
  local _terraform_line
  _terraform_line="$(printf '%s\n' "$output" | grep 'terraform')"
  [[ "${_terraform_line}" == *"[WARN]"* ]]
  [[ "${_terraform_line}" == *"terraform: does not run (rc 124) — setup_env.sh -t developer"* ]]
}

# ── never FAILs ──────────────────────────────────────────────────────────────

@test "_doctor_check_dev_tools never fails even when every tool is absent" {
  export LINUX=1 HAS_DEVTOOLS=1
  # No stubs at all -- pwsh, tflint, zig, terraform and tfsec are all
  # unresolvable.

  # NOT `run`: bats' `run` captures output via a command substitution
  # subshell, so an update to _DOCTOR_FAILED/_DOCTOR_WARN made inside the
  # called function would not survive back to this process (mirrors
  # _doctor_check_gnu_coreutils's own regression test in unit.bats). Invoke
  # directly and redirect output to a file instead.
  #
  # `|| true` is required here, and it is a bats-body property, not a
  # production one: bats runs every test body under `set -e`. This repo's
  # own production code is deliberately never run under `set -e` (shell.md),
  # so `_bin="$(command -v "${_tool}" 2>/dev/null)"` failing for an absent
  # tool is an ordinary, expected outcome there -- but bash disables `-e`
  # for the ENTIRE duration of a function call only when that call's own
  # exit status is checked (e.g. by `||`), so without this the bats
  # errexit aborts the loop after the very first absent tool and only one
  # WARN line would ever print.
  local _outfile="${BATS_TEST_TMPDIR}/dev_tools_out.txt"
  PATH="${_BIN_DIR}" _doctor_check_dev_tools > "${_outfile}" || true

  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [[ "$(cat "${_outfile}")" != *"[FAIL]"* ]]
  local _warn_count
  _warn_count="$(grep -c '\[WARN\]' "${_outfile}")"
  [ "${_warn_count}" -eq 5 ]
}
