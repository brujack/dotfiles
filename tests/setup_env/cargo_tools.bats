#!/usr/bin/env bats

# `run --separate-stderr` is a 1.5.0 flag; without this declaration bats
# emits BW02 on every invocation. ubuntu-latest ships 1.10.0 via apt and the
# dev machines 1.14.0, so the floor is satisfied everywhere this runs.
bats_require_minimum_version 1.5.0

# Covers _semver_cmp, _cargo_list_version, _cargo_tool_state and
# install_cargo_tools (lib/developer.sh). See
# docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md
# Part 3: state is judged by whether the pinned binary RUNS
# (`<cargo> <sub> --help`), not by the version string cargo reports -- a
# listed version says nothing about whether the binary loads.
#
# tests/mocks/cargo never touches a real cargo (tdd.md E2) in any suite
# that calls load_mocks -- it exports _CARGO_BIN at the mock, ahead of
# ${HOME}/.cargo/bin/cargo and a PATH cargo, in install_cargo_tools's own
# resolution order. That guarantee does not extend to a test that
# deliberately unsets _CARGO_BIN to exercise another branch (this file has
# three such tests, each responsible for keeping ${HOME}/.cargo/bin and
# PATH cargo-free on its own), or to a suite that never calls load_mocks
# at all.

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

# Writes a tiny cargo mock at <path> that logs "<prefix> $*" to
# MOCK_CALLS_FILE and, for `install --list`, prints MOCK_CARGO_LIST.
# Distinguishable BY LOG PREFIX from tests/mocks/cargo (which always logs
# a bare "cargo " prefix), so a test can prove WHICH resolved cargo
# actually ran -- not merely that "a" cargo ran, which the shared mock
# alone cannot distinguish between _CARGO_BIN, ${HOME}/.cargo/bin/cargo
# and a PATH cargo when more than one of them could resolve.
_write_distinct_cargo_mock() {
  local _path="$1" _prefix="$2"
  mkdir -p "$(dirname "${_path}")"
  local _template
  _template='#!/usr/bin/env bash
printf "__PREFIX__ %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "install" ]] && [[ "$2" == "--list" ]]; then
  printf "%s" "${MOCK_CARGO_LIST:-}"
fi
exit 0
'
  printf '%s\n' "${_template//__PREFIX__/"${_prefix}"}" > "${_path}"
  chmod +x "${_path}"
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

@test "_semver_cmp: a leading-zero component compares as decimal, not octal" {
  # Without the 10# base prefix, bash arithmetic reads "08" as a
  # malformed octal literal (8 and 9 are not valid octal digits) and
  # errors rather than comparing -- this pins the decimal reading.
  run _semver_cmp "0.08.1" "0.8.1"
  [ "$status" -eq 0 ]
  [ "$output" == "0" ]
}

@test "_semver_cmp: a non-numeric component is treated as 0" {
  run _semver_cmp "1.abc.3" "1.5.3"
  [ "$status" -eq 0 ]
  [ "$output" == "-1" ]
}

@test "_semver_cmp: pre-release suffixes compare as .0 -- 1.2.3-rc9 and 1.2.3-rc1 are EQUAL (deliberate)" {
  # See the comment above the regex gate in _semver_cmp: every
  # CARGO_TOOLS consumer only needs "strictly greater than the pin" vs
  # "not", and this is the "not" case either way, so the suffix ordering
  # is never asked about.
  run _semver_cmp "1.2.3-rc9" "1.2.3-rc1"
  [ "$status" -eq 0 ]
  [ "$output" == "0" ]
}

# ── _cargo_list_version ────────────────────────────────────────────────────

@test "_cargo_list_version: a path/git install strips the location, keeping only the version" {
  local _list
  _list="cargo-audit v0.22.1 (/Users/x/src/cargo-audit):
    cargo-audit"
  run _cargo_list_version "cargo-audit" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "0.22.1" ]
}

@test "_cargo_list_version: cargo-deny and cargo-denylist do not cross-match (denylist listed first)" {
  local _list
  _list="cargo-denylist v9.9.9:
    cargo-denylist
cargo-deny v0.19.4:
    cargo-deny"
  run _cargo_list_version "cargo-denylist" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "9.9.9" ]
  run _cargo_list_version "cargo-deny" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "0.19.4" ]
}

@test "_cargo_list_version: cargo-deny and cargo-denylist do not cross-match (deny listed first)" {
  local _list
  _list="cargo-deny v0.19.4:
    cargo-deny
cargo-denylist v9.9.9:
    cargo-denylist"
  run _cargo_list_version "cargo-deny" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "0.19.4" ]
  run _cargo_list_version "cargo-denylist" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "9.9.9" ]
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

@test "_cargo_tool_state: older is reported even when the lower install's --help fails (deliberately unprobed)" {
  local _list
  _list="$(_cargo_list_fixture "cargo-audit=0.20.0")"
  export MOCK_CARGO_HELP_EXIT_audit=9
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "older" ]
  # Not just the right outcome -- no --help probe happened at all.
  refute_grep "audit --help" "${MOCK_CALLS_FILE}"
}

@test "_cargo_tool_state: broken when at the pin but --help exits non-zero" {
  local _list
  _list="$(_cargo_list_fixture)"
  export MOCK_CARGO_HELP_EXIT_audit=7
  run _cargo_tool_state "${_CARGO_BIN}" "cargo-audit" "0.22.1" "${_list}"
  [ "$status" -eq 0 ]
  [ "$output" == "broken" ]
}

# ── install_cargo_tools: resolution order ─────────────────────────────────

@test "install_cargo_tools: skips with a message when HAS_RUST is unset" {
  run install_cargo_tools
  [ "$status" -eq 0 ]
  [ "$output" == "cargo tools: skipped (HAS_RUST unset)" ]
  [[ ! -s "${MOCK_CALLS_FILE}" ]]
}

@test "install_cargo_tools: returns 1 and prints a message when cargo cannot be resolved" {
  export HAS_RUST=1
  unset _CARGO_BIN
  # An empty shim dir, not a scrubbed system PATH (shell.md): the
  # unresolvable-cargo path reaches `return 1` using only builtins
  # ([[ -x ]], `command -v`, `printf`), so nothing here needs an external
  # binary. A scrubbed-but-nonempty PATH (e.g. /usr/bin:/bin) would leave
  # `command -v cargo` reachable wherever a distro package puts cargo in
  # one of those directories.
  local _nocargo="${BATS_TEST_TMPDIR}/nocargo" _orig_path="${PATH}"
  mkdir -p "${_nocargo}"
  export PATH="${_nocargo}"
  run install_cargo_tools
  # Restore PATH immediately -- bats' teardown() runs in this same test's
  # environment (unlike setup(), which is fresh per test), and it needs
  # `rm` on PATH.
  export PATH="${_orig_path}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cargo not found"* ]]
}

@test "install_cargo_tools: falls back to \${HOME}/.cargo/bin/cargo when _CARGO_BIN is unset" {
  export HAS_RUST=1
  unset _CARGO_BIN
  _write_distinct_cargo_mock "${HOME}/.cargo/bin/cargo" "homecargo"
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture)"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  grep -qF "homecargo install --list" "${MOCK_CALLS_FILE}"
  # Proves the PATH mock (tests/mocks/cargo, which logs a bare "cargo "
  # prefix) was NOT what ran, even though it is still on PATH.
  refute_grep "^cargo install --list$" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: falls back to a PATH cargo when _CARGO_BIN is unset and \${HOME}/.cargo/bin/cargo is absent" {
  export HAS_RUST=1
  unset _CARGO_BIN
  local _decoy="${BATS_TEST_TMPDIR}/decoy"
  _write_distinct_cargo_mock "${_decoy}/cargo" "pathcargo"
  export PATH="${_decoy}:${PATH}"
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture)"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  grep -qF "pathcargo install --list" "${MOCK_CALLS_FILE}"
}

@test "install_cargo_tools: _CARGO_BIN outranks \${HOME}/.cargo/bin/cargo when both are present" {
  export HAS_RUST=1
  # _CARGO_BIN is already the tests/mocks/cargo default from load_mocks
  # (logs a bare "cargo " prefix); give HOME a distinguishable copy so a
  # wrong precedence is observable rather than merely "a cargo ran".
  _write_distinct_cargo_mock "${HOME}/.cargo/bin/cargo" "homecargo"
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture)"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  grep -qF "cargo install --list" "${MOCK_CALLS_FILE}"
  refute_grep "homecargo" "${MOCK_CALLS_FILE}"
}

# ── install_cargo_tools: per-pin behaviour ─────────────────────────────────

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

@test "install_cargo_tools: reads the list exactly once for an 8-pin run" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture)"
  run install_cargo_tools
  [ "$status" -eq 0 ]
  local _list_calls
  _list_calls="$(grep -cF "cargo install --list" "${MOCK_CALLS_FILE}")"
  [ "${_list_calls}" -eq 1 ]
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

@test "install_cargo_tools: returns 2 and names the failed crate on stderr, not stdout, when an install fails" {
  export HAS_RUST=1
  export MOCK_CARGO_LIST
  MOCK_CARGO_LIST="$(_cargo_list_fixture "cargo-audit=ABSENT")"
  export MOCK_CARGO_INSTALL_EXIT=3
  run --separate-stderr install_cargo_tools
  [ "$status" -eq 2 ]
  [ "$stderr" == "cargo tools: cargo-audit install failed" ]
  [[ "$output" != *"install failed"* ]]
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
