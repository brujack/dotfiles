#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export HOME="${BATS_TEST_TMPDIR}"
    export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
    touch "${MOCK_CALLS_FILE}"
    export ORIGINAL_PATH="${PATH}"
    source "${REPO_ROOT}/lib/package_capture.sh"
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

# ── _list_brew_packages ───────────────────────────────────────────────────────

@test "_list_brew_packages: returns [] when brew absent" {
    local _clean_path="/usr/bin:/bin"
    PATH="${_clean_path}" run _list_brew_packages
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# ── _list_apt_packages ────────────────────────────────────────────────────────

@test "_list_apt_packages: returns [] when dpkg-query absent" {
    # dpkg-query in /usr/bin on Ubuntu — use tmpdir (no dpkg-query there)
    PATH="${BATS_TEST_TMPDIR}" run _list_apt_packages
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# ── _list_pip_packages ────────────────────────────────────────────────────────

@test "_list_pip_packages: returns [] when pip absent" {
    # /usr/bin/pip3 exists on macOS — use tmpdir (no pip there) to make lookup fail
    PATH="${BATS_TEST_TMPDIR}" run _list_pip_packages
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# ── capture_package_diff ─────────────────────────────────────────────────────

@test "capture_package_diff: no changes (curr == prev) writes nothing, exits 0" {
    export LEDGER_BIN="${BATS_TEST_TMPDIR}/ledger"
    local _pkg='[{"name":"curl","version":"8.0"}]'
    run capture_package_diff "brew" "test-machine" "run-001" "${_pkg}" "${_pkg}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "ledger write" "${MOCK_CALLS_FILE}"
}

@test "capture_package_diff: new package writes entry with added" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    export LEDGER_BIN="${_mock_dir}/ledger"
    PATH="${_mock_dir}:${PATH}"
    local _prev='[]'
    local _curr='[{"name":"ripgrep","version":"14.1.0"}]'
    run capture_package_diff "brew" "test-machine" "run-001" "${_prev}" "${_curr}"
    [ "$status" -eq 0 ]
    grep -q "ledger write" "${MOCK_CALLS_FILE}"
}

@test "capture_package_diff: removed package writes entry with removed" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    export LEDGER_BIN="${_mock_dir}/ledger"
    PATH="${_mock_dir}:${PATH}"
    local _prev='[{"name":"ripgrep","version":"14.1.0"}]'
    local _curr='[]'
    run capture_package_diff "brew" "test-machine" "run-001" "${_prev}" "${_curr}"
    [ "$status" -eq 0 ]
    grep -q "ledger write" "${MOCK_CALLS_FILE}"
}

@test "capture_package_diff: upgraded package writes entry with from/to" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    export LEDGER_BIN="${_mock_dir}/ledger"
    PATH="${_mock_dir}:${PATH}"
    local _prev='[{"name":"ripgrep","version":"13.0.0"}]'
    local _curr='[{"name":"ripgrep","version":"14.1.0"}]'
    run capture_package_diff "brew" "test-machine" "run-001" "${_prev}" "${_curr}"
    [ "$status" -eq 0 ]
    grep -q "ledger write" "${MOCK_CALLS_FILE}"
}

@test "capture_package_diff: VCS version in current is sanitized to vcs-redacted" {
    local _written_json
    local _mock_dir
    _mock_dir="$(mktemp -d)"
    cat > "${_mock_dir}/ledger" << 'EOF'
#!/usr/bin/env bash
cat > /tmp/ledger_payload.json
printf "ledger write\n" >> "${MOCK_CALLS_FILE}"
exit 0
EOF
    chmod +x "${_mock_dir}/ledger"
    export LEDGER_BIN="${_mock_dir}/ledger"
    PATH="${_mock_dir}:${PATH}"
    local _prev='[]'
    local _curr='[{"name":"mylib","version":"git+ssh://internal/mylib@abc123"}]'
    run capture_package_diff "pip" "test-machine" "run-001" "${_prev}" "${_curr}"
    [ "$status" -eq 0 ]
    _written_json="$(cat /tmp/ledger_payload.json 2>/dev/null || true)"
    [[ "${_written_json}" == *"<vcs-redacted>"* ]]
    [[ "${_written_json}" != *"git+ssh://"* ]]
}

@test "capture_package_diff: ledger absent prints WARNING, exits 0" {
    export LEDGER_BIN="/nonexistent/ledger"
    local _prev='[]'
    local _curr='[{"name":"curl","version":"8.0"}]'
    run capture_package_diff "brew" "test-machine" "run-001" "${_prev}" "${_curr}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

# ── capture_all_packages ─────────────────────────────────────────────────────

@test "capture_all_packages: PACKAGE_CAPTURE_ENABLED=false returns early, no ledger calls" {
    local _mock_dir
    _mock_dir="$(_make_mock_ledger 0)"
    export LEDGER_BIN="${_mock_dir}/ledger"
    PATH="${_mock_dir}:${PATH}"
    mkdir -p "${HOME}/.config/dotfiles"
    echo "test-machine-id" > "${HOME}/.config/dotfiles/machine-id"
    PACKAGE_CAPTURE_ENABLED=false run capture_all_packages "run-001"
    [ "$status" -eq 0 ]
    ! grep -q "ledger" "${MOCK_CALLS_FILE}" 2>/dev/null
}

@test "capture_all_packages: missing machine-id prints WARNING, exits 0" {
    run capture_all_packages "run-001"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"*"machine-id"* ]]
}
