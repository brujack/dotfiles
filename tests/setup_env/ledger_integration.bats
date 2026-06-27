#!/usr/bin/env bats

setup() {
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

# ── ensure_machine_id ─────────────────────────────────────────────────────────

@test "ensure_machine_id: creates machine-id file when absent" {
    run ensure_machine_id
    [ "$status" -eq 0 ]
    [ -f "${HOME}/.config/dotfiles/machine-id" ]
}

@test "ensure_machine_id: machine-id is valid UUID4 format" {
    ensure_machine_id || true
    local _id
    _id="$(cat "${HOME}/.config/dotfiles/machine-id")"
    [[ "${_id}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

@test "ensure_machine_id: idempotent — preserves existing id" {
    mkdir -p "${HOME}/.config/dotfiles"
    echo "test-machine-id" > "${HOME}/.config/dotfiles/machine-id"
    ensure_machine_id || true
    local _id
    _id="$(cat "${HOME}/.config/dotfiles/machine-id")"
    [ "${_id}" = "test-machine-id" ]
}

@test "ensure_machine_id: returns 0 when machine-id already exists" {
    mkdir -p "${HOME}/.config/dotfiles"
    echo "existing-id" > "${HOME}/.config/dotfiles/machine-id"
    run ensure_machine_id
    [ "$status" -eq 0 ]
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
