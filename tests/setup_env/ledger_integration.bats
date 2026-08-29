#!/usr/bin/env bats
#
# `run --separate-stderr` needs bats >= 1.5.0 (CI 1.10.0, this box 1.14.0).
# Declared so an older bats fails loudly rather than silently ignoring the flag.
bats_require_minimum_version 1.5.0

setup() {
    # Close stdin for every test in this file. The ledger mock ends with
    # `cat > /dev/null`, emulating the real binary draining its input -- and a
    # mock inherits the test's stdin, which under bats is the live suite pipe.
    # `cat` then blocks forever on an EOF bats never sends, hanging the whole
    # run with no failing test and no timeout.
    #
    # Measured 2026-08-22, twice, both times stalling at the same test with the
    # suite sitting at 720 ok / 0 not ok indefinitely. Diagnosed live rather
    # than guessed: `lsof` on the stuck mock showed `fd 0u unix` -- stdin bound
    # to the bats socket. Same class as ci.md's `make test < /dev/null` rule.
    #
    # Applied at setup() scope rather than per call site on purpose: there are
    # 15+ invocations and a per-site redirect leaves the trap armed for the
    # next test someone adds to this file.
    exec < /dev/null
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_mocks
    export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
    touch "${MOCK_CALLS_FILE}"
    load_setup_env
    export HOME="${BATS_TEST_TMPDIR}"
    export ORIGINAL_PATH="${PATH}"
}

teardown() {
    export PATH="${ORIGINAL_PATH}"
}

_make_mock_ledger() {
    local _exit="${1:-0}"
    local _dir
    _dir="$(mktemp -d)"
    cat > "${_dir}/ledger" << EOF
#!/usr/bin/env bash
printf "ledger %s\n" "\$*" >> "\${MOCK_CALLS_FILE}"
cat > /dev/null 2>&1
exit ${_exit}
EOF
    chmod +x "${_dir}/ledger"
    printf '%s' "${_dir}"
}

# ── ledger_write_entry ────────────────────────────────────────────────────────

@test "ledger_write_entry: returns 0 with WARNING when ledger binary absent" {
    local _clean_path="/usr/bin:/bin"
    PATH="${_clean_path}" run ledger_write_entry '{"tool":"test"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "ledger_write_entry: calls ledger write with json" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    PATH="${_mock_dir}:${PATH}" run ledger_write_entry '{"tool":"dotfiles"}'
    [ "$status" -eq 0 ]
    grep -q "ledger write" "${MOCK_CALLS_FILE}"
}

@test "ledger_write_entry: returns 2 with WARNING when ledger exits 2" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 2)"
    PATH="${_mock_dir}:${PATH}" run ledger_write_entry '{"tool":"test"}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARNING"*"spooled"* ]]
}

@test "ledger_write_entry: propagates non-zero non-2 exit code" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 1)"
    local _rc=0
    PATH="${_mock_dir}:${PATH}" ledger_write_entry '{"tool":"test"}' || _rc=$?
    [ "${_rc}" -eq 1 ]
}

# ── ledger_flush_spool ────────────────────────────────────────────────────────

@test "ledger_flush_spool: returns 0 silently when ledger binary absent" {
    local _clean_path="/usr/bin:/bin"
    PATH="${_clean_path}" run ledger_flush_spool
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ledger_flush_spool: calls ledger flush" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    PATH="${_mock_dir}:${PATH}" run ledger_flush_spool
    [ "$status" -eq 0 ]
    grep -q "ledger flush" "${MOCK_CALLS_FILE}"
}

@test "ledger_flush_spool: propagates non-zero exit from ledger" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 2)"
    local _rc=0
    PATH="${_mock_dir}:${PATH}" ledger_flush_spool || _rc=$?
    [ "${_rc}" -eq 2 ]
}

# ── fallback to ~/.local/bin/ledger ──────────────────────────────────────────

@test "ledger_write_entry: falls back to ~/.local/bin/ledger when not in PATH" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    mkdir -p "${HOME}/.local/bin"
    cp "${_mock_dir}/ledger" "${HOME}/.local/bin/ledger"
    local _clean_path="/usr/bin:/bin"
    PATH="${_clean_path}" run ledger_write_entry '{"tool":"dotfiles"}'
    [ "$status" -eq 0 ]
    grep -q "ledger write" "${MOCK_CALLS_FILE}"
}

@test "ledger_flush_spool: falls back to ~/.local/bin/ledger when not in PATH" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    mkdir -p "${HOME}/.local/bin"
    cp "${_mock_dir}/ledger" "${HOME}/.local/bin/ledger"
    local _clean_path="/usr/bin:/bin"
    PATH="${_clean_path}" run ledger_flush_spool
    [ "$status" -eq 0 ]
    grep -q "ledger flush" "${MOCK_CALLS_FILE}"
}

# ── _ledger_write_dotfiles_entry ──────────────────────────────────────────────

_setup_ledger_tmpdir() {
    export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}/update"
    mkdir -p "${_DOTFILES_RUN_TMPDIR}"
    printf '2026-06-28T12:00:00Z\n' > "${_DOTFILES_RUN_TMPDIR}/started_at"
    printf '1751116800\n'           > "${_DOTFILES_RUN_TMPDIR}/start_epoch"
    printf 'test-run-uuid\n'        > "${_DOTFILES_RUN_TMPDIR}/run_id"
    printf 'abc1234deadbeef\n'      > "${_DOTFILES_RUN_TMPDIR}/git_sha"
}

_make_mock_ledger_capture() {
    local _capture_file="${1:?_make_mock_ledger_capture: capture path required}"
    local _dir
    _dir="$(mktemp -d)"
    cat > "${_dir}/ledger" << EOF
#!/usr/bin/env bash
printf "ledger %s\n" "\$*" >> "\${MOCK_CALLS_FILE}"
cat > "${_capture_file}"
EOF
    chmod +x "${_dir}/ledger"
    printf '%s' "${_dir}"
}

@test "_ledger_write_dotfiles_entry: no-ops when started_at absent" {
    export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}/update"
    mkdir -p "${_DOTFILES_RUN_TMPDIR}"
    # No started_at file — simulates direct _update_summary call, not run_update
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    PATH="${_mock_dir}:${PATH}" _ledger_write_dotfiles_entry
    run grep "ledger write" "${MOCK_CALLS_FILE}"
    [ "$status" -ne 0 ]
}

@test "_ledger_write_dotfiles_entry: no-ops when machine-id absent" {
    _setup_ledger_tmpdir
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    PATH="${_mock_dir}:${PATH}" _ledger_write_dotfiles_entry
    run grep "ledger write" "${MOCK_CALLS_FILE}"
    [ "$status" -ne 0 ]
}

@test "_ledger_write_dotfiles_entry: calls ledger write with required JSON fields" {
    _setup_ledger_tmpdir
    mkdir -p "${HOME}/.config/dotfiles"
    printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"

    local _captured="${BATS_TEST_TMPDIR}/ledger_stdin"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger_capture "${_captured}")"
    PATH="${_mock_dir}:${PATH}" _ledger_write_dotfiles_entry

    grep -q "ledger write" "${MOCK_CALLS_FILE}"
    grep -q '"tool": "dotfiles"' "${_captured}"
    grep -q '"entity_id": "test-machine-uuid"' "${_captured}"
    grep -q '"started_at": "2026-06-28T12:00:00Z"' "${_captured}"
    grep -q '"success": true' "${_captured}"
    grep -q '"failure_stage": null' "${_captured}"
}

@test "_ledger_write_dotfiles_entry: sets success=false and failure_stage when fail count > 0" {
    _setup_ledger_tmpdir
    mkdir -p "${HOME}/.config/dotfiles"
    printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"
    printf 'FAIL\n' > "${_DOTFILES_RUN_TMPDIR}/status_brew"
    printf 'exit 1\n' > "${_DOTFILES_RUN_TMPDIR}/result_brew"

    local _captured="${BATS_TEST_TMPDIR}/ledger_stdin"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger_capture "${_captured}")"

    # Simulate _fail=1 as ledger_write_entry would see from _update_summary scope
    _fail=1 PATH="${_mock_dir}:${PATH}" _ledger_write_dotfiles_entry

    grep -q '"success": false' "${_captured}"
    grep -q '"failure_stage": "brew"' "${_captured}"
}

# ── _ledger_write_run_entry (generalized) ─────────────────────────────────────

@test "_ledger_write_run_entry: no-ops when started_at absent" {
    export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}/run"
    mkdir -p "${_DOTFILES_RUN_TMPDIR}"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    PATH="${_mock_dir}:${PATH}" _ledger_write_run_entry "setup_user" 0
    run grep "ledger write" "${MOCK_CALLS_FILE}"
    [ "$status" -ne 0 ]
}

@test "_ledger_write_run_entry: no-ops when machine-id absent" {
    _setup_ledger_tmpdir
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    PATH="${_mock_dir}:${PATH}" _ledger_write_run_entry "setup_user" 0
    run grep "ledger write" "${MOCK_CALLS_FILE}"
    [ "$status" -ne 0 ]
}

@test "_ledger_write_run_entry setup_user: writes run_type=setup_user and success=true" {
    _setup_ledger_tmpdir
    mkdir -p "${HOME}/.config/dotfiles"
    printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"

    local _captured="${BATS_TEST_TMPDIR}/ledger_stdin"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger_capture "${_captured}")"
    PATH="${_mock_dir}:${PATH}" _ledger_write_run_entry "setup_user" 0

    grep -q '"run_type": "setup_user"' "${_captured}"
    grep -q '"success": true' "${_captured}"
    grep -q '"tool": "dotfiles"' "${_captured}"
    # setup_user must NOT include update-only fields
    run grep '"failure_stage"' "${_captured}"
    [ "$status" -ne 0 ]
}

@test "_ledger_write_run_entry setup_user: success=false when exit_code non-zero" {
    _setup_ledger_tmpdir
    mkdir -p "${HOME}/.config/dotfiles"
    printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"

    local _captured="${BATS_TEST_TMPDIR}/ledger_stdin"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger_capture "${_captured}")"
    PATH="${_mock_dir}:${PATH}" _ledger_write_run_entry "setup_user" 1

    grep -q '"success": false' "${_captured}"
}

@test "_ledger_write_run_entry developer: writes run_type=developer" {
    _setup_ledger_tmpdir
    mkdir -p "${HOME}/.config/dotfiles"
    printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"

    local _captured="${BATS_TEST_TMPDIR}/ledger_stdin"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger_capture "${_captured}")"
    PATH="${_mock_dir}:${PATH}" _ledger_write_run_entry "developer" 0

    grep -q '"run_type": "developer"' "${_captured}"
}

@test "_ledger_write_run_entry update: includes failure_stage and workflows_ran" {
    _setup_ledger_tmpdir
    mkdir -p "${HOME}/.config/dotfiles"
    printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"
    printf 'FAIL\n' > "${_DOTFILES_RUN_TMPDIR}/status_brew"

    local _captured="${BATS_TEST_TMPDIR}/ledger_stdin"
    local _mock_dir
    _mock_dir="$(_make_mock_ledger_capture "${_captured}")"
    PATH="${_mock_dir}:${PATH}" _ledger_write_run_entry "update" 1

    grep -q '"run_type": "update"' "${_captured}"
    grep -q '"failure_stage"' "${_captured}"
    grep -q '"workflows_ran"' "${_captured}"
}

# ── _dotfiles_run_tmpdir_setup ────────────────────────────────────────────────

@test "_dotfiles_run_tmpdir_setup: creates tmpdir and writes started_at" {
    unset _DOTFILES_RUN_TMPDIR
    _dotfiles_run_tmpdir_setup
    [ -d "${_DOTFILES_RUN_TMPDIR}" ]
    [ -f "${_DOTFILES_RUN_TMPDIR}/started_at" ]
    grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "${_DOTFILES_RUN_TMPDIR}/started_at"
}

@test "_dotfiles_run_tmpdir_setup: writes start_epoch run_id and git_sha" {
    unset _DOTFILES_RUN_TMPDIR
    _dotfiles_run_tmpdir_setup
    [ -f "${_DOTFILES_RUN_TMPDIR}/start_epoch" ]
    [ -f "${_DOTFILES_RUN_TMPDIR}/run_id" ]
    [ -f "${_DOTFILES_RUN_TMPDIR}/git_sha" ]
}

@test "_dotfiles_run_tmpdir_setup: returns 1 and leaves the var unset when the tmpdir root is unreachable" {
    unset _DOTFILES_RUN_TMPDIR
    export _OVERRIDE_RUN_TMPDIR_ROOT="${BATS_TEST_TMPDIR}/nonexistent-root"
    # No `set -e`: the script must survive _dotfiles_run_tmpdir_setup's non-zero
    # return long enough to capture it and print the variable's post-call state.
    # --separate-stderr: mktemp's own failure message goes to stderr and would
    # otherwise land in $output ahead of the printf, corrupting the equality check.
    run --separate-stderr bash -c '
      source "'"${REPO_ROOT}"'/setup_env.sh" >/dev/null 2>&1 || true
      _dotfiles_run_tmpdir_setup
      printf "rc=%s var=[%s]" "$?" "${_DOTFILES_RUN_TMPDIR:-}"'
    unset _OVERRIDE_RUN_TMPDIR_ROOT
    [ "$status" -eq 0 ]                  # bash -c itself exits 0 (rc captured, not propagated)
    [[ "$output" == "rc=1 var=[]" ]]     # RED today: mktemp ignores the unreachable root entirely
}

@test "_dotfiles_run_tmpdir_setup: directory survives the EXIT trap" {
    run bash -c 'set -e
      source "'"${REPO_ROOT}"'/setup_env.sh" >/dev/null 2>&1 || true
      _dotfiles_run_tmpdir_setup
      printf "%s" "${_DOTFILES_RUN_TMPDIR}"'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ -d "$output" ]              # RED today: the trap removed it when bash -c exited
    [ -f "${output}/started_at" ]
    rm -rf "$output"
}

@test "_dotfiles_run_tmpdir_setup: directory name carries the dotfiles-run prefix" {
    unset _DOTFILES_RUN_TMPDIR
    _dotfiles_run_tmpdir_setup
    [[ "$(basename "${_DOTFILES_RUN_TMPDIR}")" == dotfiles-run.* ]]  # RED: name is tmp.XXXXXXXX
}
