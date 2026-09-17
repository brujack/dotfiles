#!/usr/bin/env bats

# Covers _semver_cmp, _cargo_tool_state and install_cargo_tools
# (lib/developer.sh). See docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md
# Part 3: state is judged by whether the pinned binary RUNS
# (`<cargo> <sub> --help`), not by the version string cargo reports -- a
# listed version says nothing about whether the binary loads.
#
# tests/mocks/cargo never touches a real cargo (tdd.md E2): load_mocks
# exports _CARGO_BIN at the mock unconditionally, so install_cargo_tools's
# resolution order never reaches ${HOME}/.cargo/bin/cargo or a PATH cargo
# unless a test deliberately clears the seam.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  # HAS_RUST is profile-derived and load_setup_env does not call detect_env
  # (CLAUDE.md: "load_setup_env() does NOT set OS vars"), so it otherwise
  # carries whatever the invoking shell happened to export -- a state leak
  # (tdd.md pitfall A). Every test sets it explicitly.
  unset HAS_RUST
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Builds `cargo install --list` fixture output for all 8 CARGO_TOOLS pins,
# each at its pinned version by default. Args are "<crate>=<version>"
# overrides, or "<crate>=ABSENT" to omit a crate entirely -- so a test can
# drive exactly one pin's state while the other 7 stay "ok" and never
# trigger an install call of their own.
_cargo_list_fixture() {
  local -A _pins=(
    [cargo-audit]="0.22.1"
    [cargo-deny]="0.19.4"
    [cargo-insta]="1.47.2"
    [cargo-machete]="0.9.2"
    [cargo-mutants]="27.0.0"
    [cargo-semver-checks]="0.47.0"
    [cargo-tarpaulin]="0.35.2"
    [cargo-zigbuild]="0.22.3"
  )
  local _override _crate _version
  for _override in "$@"; do
    _crate="${_override%%=*}"
    _version="${_override#*=}"
    _pins["${_crate}"]="${_version}"
  done
  local -a _order=(
    cargo-audit cargo-deny cargo-insta cargo-machete cargo-mutants
    cargo-semver-checks cargo-tarpaulin cargo-zigbuild
  )
  for _crate in "${_order[@]}"; do
    [[ "${_pins[${_crate}]}" == "ABSENT" ]] && continue
    printf '%s v%s:\n    %s\n' "${_crate}" "${_pins[${_crate}]}" "${_crate}"
  done
}

# ── _semver_cmp ────────────────────────────────────────────────────────────

@test "_semver_cmp: 0.9.2 vs 0.10.0 is -1 (numeric, not lexical)" {
  run _semver_cmp "0.9.2" "0.10.0"
  [ "$status" -eq 0 ]
  [ "$output" == "-1" ]
}

@test "_semver_cmp: equal versions is 0" {
  run _semver_cmp "1.2.3" "1.2.3"
  [ "$status" -eq 0 ]
  [ "$output" == "0" ]
}

@test "_semver_cmp: 1.2.3 vs 1.2 is 1 (missing component treated as 0)" {
  run _semver_cmp "1.2.3" "1.2"
  [ "$status" -eq 0 ]
  [ "$output" == "1" ]
}

@test "_semver_cmp: 1.9 vs 1.10 is -1 -- a lexical compare would say the opposite" {
  # A lexical "$a" > "$b" comparison would read "1.9" as greater than
  # "1.10" here, because '9' > '1' at the first differing character
  # (shellcheck SC2072 flags that construct on decimal-looking operands
  # for exactly this reason). _semver_cmp must not take that path.
  run _semver_cmp "1.9" "1.10"
  [ "$status" -eq 0 ]
  [ "$output" == "-1" ]
}

# ── _cargo_tool_state ────────────────────────────────────────────────────

@test "_cargo_tool_state: absent when crate is not in the list" {
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" ""
  [ "$status" -eq 0 ]
  [ "$output" == "absent" ]
}

@test "_cargo_tool_state: ok when at the pin and --help exits 0" {
  local _list
  _list="$(_cargo_list_fixture)"
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "ok" ]
}

@test "_cargo_tool_state: newer when installed is higher and --help exits 0" {
  local _list
  _list="$(_cargo_list_fixture "cargo-audit=0.23.0")"
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "newer" ]
}

@test "_cargo_tool_state: older when installed is lower" {
  local _list
  _list="$(_cargo_list_fixture "cargo-audit=0.20.0")"
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "older" ]
}

@test "_cargo_tool_state: broken when at the pin but --help exits non-zero" {
  local _list
  _list="$(_cargo_list_fixture)"
  export MOCK_CARGO_HELP_EXIT_audit=7
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "broken" ]
}

# ── install_cargo_tools ────────────────────────────────────────────────────

@test "install_cargo_tools: skips with a message when HAS_RUST is unset" {
  run install_cargo_tools
  [ "$status" -eq 0 ]
  [ "$output" == "cargo tools: skipped (HAS_RUST unset)" ]
  [[ ! -s "${MOCK_CALLS_FILE}" ]]
}

@test "install_cargo_tools: returns 1 and prints a message when cargo cannot be resolved" {
  export HAS_RUST=1
  unset _CARGO_BIN
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run install_cargo_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"cargo not found"* ]]
}

@test "install_cargo_tools: all-ok reports ok for every pin and installs nothing" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture)"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo tools: cargo-audit 0.22.1 ok"* ]]
  [[ "$output" == *"cargo tools: cargo-tarpaulin 0.35.2 ok"* ]]
  refute_grep "install --locked" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: absent installs at the pin, no --force" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture "cargo-audit=ABSENT")"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  grep -qF "cargo install --locked cargo-audit@0.22.1" "${MOCK_CALLS_FILE}"
  refute_grep "install --locked --force cargo-audit" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: older installs at the pin, no --force" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture "cargo-audit=0.20.0")"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  grep -qF "cargo install --locked cargo-audit@0.22.1" "${MOCK_CALLS_FILE}"
  refute_grep "install --locked --force cargo-audit" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: newer is left alone -- no install call, ok line names the installed version" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture "cargo-audit=0.23.0")"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo tools: cargo-audit 0.23.0 ok"* ]]
  refute_grep "install --locked cargo-audit" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: broken installs WITH --force" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture)"
  export MOCK_CARGO_HELP_EXIT_audit=7
  run install_cargo_tools
  [ "$status" -eq 0 ]
  grep -qF "cargo install --locked --force cargo-audit@0.22.1" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: returns 2 and names the failed crate on stderr when an install fails" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture "cargo-audit=ABSENT")"
  export MOCK_CARGO_INSTALL_EXIT=3
  run install_cargo_tools
  [ "$status" -eq 2 ]
  [[ "$output" == *"cargo-audit"* ]]
}

@test "install_cargo_tools: LIBGIT2_NO_PKG_CONFIG=1 only on tarpaulin's install, empty on another crate's" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture "cargo-tarpaulin=ABSENT" "cargo-audit=ABSENT")"
  run install_cargo_tools
  [ "$status" -eq 0 ]

  local _tarpaulin_env _audit_env
  _tarpaulin_env="$(grep -A1 -F "cargo install --locked cargo-tarpaulin@0.35.2" "${MOCK_CALLS_FILE}" | tail -1)"
  _audit_env="$(grep -A1 -F "cargo install --locked cargo-audit@0.22.1" "${MOCK_CALLS_FILE}" | tail -1)"

  [ "${_tarpaulin_env}" == "cargo-env LIBGIT2_NO_PKG_CONFIG=1" ]
  [ "${_audit_env}" == "cargo-env LIBGIT2_NO_PKG_CONFIG=" ]
}
