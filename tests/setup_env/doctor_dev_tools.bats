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
  # Explicit `skip`, not an unguarded assignment: `command -v timeout`
  # failing (no GNU coreutils on this mac) must not silently produce
  # `ln -s "" "${_BIN_DIR}/timeout"` -- a dangling symlink that `command -v`
  # inside the arm would still resolve (it only checks the PATH entry
  # exists, not that it's a valid target), sending every test down the
  # unbounded-probe fallback and making the timeout test (which expects a
  # real kill at 1s) pass only because its 3s sleep happened to finish
  # before anyone noticed.
  local _real_timeout _real_sleep
  _real_timeout="$(command -v timeout 2>/dev/null || true)"
  if [[ -z "${_real_timeout}" ]]; then
    skip "no 'timeout' binary on PATH -- this suite exercises the arm's real timeout wrapping and cannot fake it (macOS without GNU coreutils)"
  fi
  _real_sleep="$(command -v sleep 2>/dev/null || true)"
  if [[ -z "${_real_sleep}" ]]; then
    skip "no 'sleep' binary on PATH"
  fi
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

# ── HOME unusable: refuse the whole arm, not five misleading per-tool
# verdicts ───────────────────────────────────────────────────────────────

@test "_doctor_check_dev_tools warns once for the whole arm when HOME is unset, rather than probing from the caller's cwd" {
  export LINUX=1 HAS_DEVTOOLS=1
  # A resolvable, working stub for every tool -- if the HOME guard did NOT
  # short-circuit, `cd ""` (unset HOME) returns 0 and leaves cwd wherever
  # bats happens to be, so every probe would still resolve and PASS. The
  # assertion is on the ABSENCE of any per-tool verdict, not on failure.
  _write_stub "zig" "exit 0"
  unset HOME

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev tools:"* ]]
  [[ "$output" == *"cannot probe: HOME is unset or unreadable"* ]]
  [[ "$output" != *"zig"* ]]
  [[ "$output" != *"[PASS]"* ]]
}

@test "_doctor_check_dev_tools warns once for the whole arm when HOME points at a directory that does not exist" {
  export LINUX=1 HAS_DEVTOOLS=1
  # Every tool genuinely resolvable and working -- an unreadable HOME must
  # not blame five healthy installs with "does not run (rc 1)" from a
  # failing `cd`.
  _write_stub "pwsh" "exit 0"
  _write_stub "tflint" "exit 0"
  _write_stub "zig" "exit 0"
  _write_stub "terraform" "exit 0"
  _write_stub "tfsec" "exit 0"
  export HOME="${BATS_TEST_TMPDIR}/does-not-exist"

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot probe: HOME is unset or unreadable"* ]]
  [[ "$output" != *"[PASS]"* ]]
  [[ "$output" != *"rc 1"* ]]
}

@test "_doctor_check_dev_tools warns once for the whole arm when HOME exists but is not traversable" {
  # `[[ -d ]]` only stats the path -- it needs `x` on the PARENT, not on the
  # directory itself, so a HOME lacking its own execute bit passes a bare
  # `-d` guard and every probe's `cd` then fails, reporting five healthy
  # installs as "does not run (rc 1)" exactly like the does-not-exist case
  # above. Running as root makes every directory traversable regardless of
  # mode, so this test cannot discriminate under a root runner -- skip
  # there rather than pass for the wrong reason (bats/tests/scripts'
  # existing convention for the same hazard).
  [ "$(id -u)" -ne 0 ] || skip "running as root; chmod 0600 does not block traversal"
  export LINUX=1 HAS_DEVTOOLS=1
  _write_stub "pwsh" "exit 0"
  _write_stub "tflint" "exit 0"
  _write_stub "zig" "exit 0"
  _write_stub "terraform" "exit 0"
  _write_stub "tfsec" "exit 0"
  local _unreadable_home="${BATS_TEST_TMPDIR}/unreadable-home"
  mkdir -p "${_unreadable_home}"
  chmod 0600 "${_unreadable_home}"
  export HOME="${_unreadable_home}"

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  chmod 0700 "${_unreadable_home}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot probe: HOME is unset or unreadable"* ]]
  [[ "$output" != *"[PASS]"* ]]
  [[ "$output" != *"rc 1"* ]]
}

# ── T1: the timeout-absent fallback must still discriminate a real
# failure, not vacuously PASS every tool ──────────────────────────────────

@test "_doctor_check_dev_tools still warns a failing tool when timeout itself is not on PATH" {
  export LINUX=1 HAS_DEVTOOLS=1
  # A separate shim dir with NO timeout symlink at all -- this exercises
  # the arm's unbounded-probe fallback branch directly, distinct from every
  # other test in this file (which all carry the real timeout via
  # ${_BIN_DIR}). Deleting the fallback's `else` branch would make the
  # surrounding `if` compound return 0 with nothing run inside it, so `_rc`
  # reads 0 and this would wrongly PASS.
  local _no_timeout_dir="${BATS_TEST_TMPDIR}/bin_no_timeout"
  mkdir -p "${_no_timeout_dir}"
  cat > "${_no_timeout_dir}/zig" <<'STUB'
#!/bin/bash
exit 1
STUB
  chmod +x "${_no_timeout_dir}/zig"

  PATH="${_no_timeout_dir}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  local _zig_line
  _zig_line="$(printf '%s\n' "$output" | grep 'zig')"
  [[ "${_zig_line}" == *"[WARN]"* ]]
  [[ "${_zig_line}" == *"does not run (rc 1)"* ]]
}

# ── T2: the probe must actually run from HOME, not from the caller's cwd
# ───────────────────────────────────────────────────────────────────────

@test "_doctor_check_dev_tools ignores a project-local .terraform-version sitting in the caller's cwd" {
  export LINUX=1 HAS_DEVTOOLS=1
  # Exits 9 -- distinct from every other rc this file asserts on -- only
  # when a .terraform-version file is present in ITS OWN cwd at run time.
  # HOME (this test's real, empty ${_BIN_DIR}'s sibling home dir) carries
  # no such file; the caller's bats cwd, set below, does. PASS is only
  # possible if the arm's `cd "${_probe_dir}"` actually took effect.
  _write_stub "terraform" '[[ -f .terraform-version ]] && exit 9; exit 0'

  local _fixture_dir="${BATS_TEST_TMPDIR}/tf-fixture"
  mkdir -p "${_fixture_dir}"
  : > "${_fixture_dir}/.terraform-version"

  local _orig_pwd="${PWD}"
  cd "${_fixture_dir}"
  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  cd "${_orig_pwd}"

  [ "$status" -eq 0 ]
  local _terraform_line
  _terraform_line="$(printf '%s\n' "$output" | grep 'terraform')"
  [[ "${_terraform_line}" == *"[PASS]"* ]]
}

# ── T3: the documented probe arguments are what actually reaches each
# tool ─────────────────────────────────────────────────────────────────

@test "_doctor_check_dev_tools invokes every tool with its documented probe arguments" {
  export LINUX=1 HAS_DEVTOOLS=1
  # Blanking any single tool's _args value survives every other test in
  # this file -- only argv itself discriminates it. A bare `pwsh` with no
  # args starts an interactive REPL instead of exiting (the exact failure
  # mode this test exists to catch, since it would convert a PASS into a
  # 10s timeout WARN on every real doctor run); a bare `tfsec`/`tflint`
  # with no args scans the probe's cwd instead of printing a version,
  # which would surface as an rc-124 timeout rather than a wrong-args
  # failure and be misdiagnosed as "does not run". MOCK_CALLS_FILE is
  # exported in setup() and otherwise unused by this file.
  _write_stub "pwsh" 'printf "pwsh %s\n" "$*" >> "${MOCK_CALLS_FILE}"; exit 0'
  _write_stub "zig" 'printf "zig %s\n" "$*" >> "${MOCK_CALLS_FILE}"; exit 0'
  _write_stub "tflint" 'printf "tflint %s\n" "$*" >> "${MOCK_CALLS_FILE}"; exit 0'
  _write_stub "terraform" 'printf "terraform %s\n" "$*" >> "${MOCK_CALLS_FILE}"; exit 0'
  _write_stub "tfsec" 'printf "tfsec %s\n" "$*" >> "${MOCK_CALLS_FILE}"; exit 0'

  PATH="${_BIN_DIR}" run _doctor_check_dev_tools
  [ "$status" -eq 0 ]
  grep -qF 'pwsh -NoProfile -Command exit' "${MOCK_CALLS_FILE}"
  grep -qF 'zig version' "${MOCK_CALLS_FILE}"
  grep -qF 'tflint --version' "${MOCK_CALLS_FILE}"
  grep -qF 'terraform version' "${MOCK_CALLS_FILE}"
  grep -qF 'tfsec --version' "${MOCK_CALLS_FILE}"
}

# ── T6: wiring order is pinned against the source, not just presence
# ───────────────────────────────────────────────────────────────────────

@test "lib/helpers.sh: _doctor_check_dev_tools is called directly after _doctor_check_tools in run_doctor" {
  # Both names appearing somewhere in run_doctor is not enough -- swapping
  # the two call lines, or interposing another check between them, still
  # satisfies "both present". Pin the call site's adjacency against the
  # source; line numbers are derived with grep -n at test time, never
  # hardcoded, since this file is edited by sibling tasks. Style:
  # developer.bats' equivalent pin for install_pyenv_rehash_hook's
  # adjacency to `pyenv rehash`.
  local _src="${BATS_TEST_DIRNAME}/../../lib/helpers.sh"
  local _tools_line
  _tools_line="$(grep -n '^  _doctor_check_tools$' "${_src}" | head -1 | cut -d: -f1)"
  [ -n "${_tools_line}" ]
  local _next_line
  _next_line=$(( _tools_line + 1 ))
  local _next_content
  _next_content="$(sed -n "${_next_line}p" "${_src}")"
  [[ "${_next_content}" == *"_doctor_check_dev_tools"* ]]
}
