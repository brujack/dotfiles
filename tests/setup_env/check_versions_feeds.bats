#!/usr/bin/env bats

# Covers _fetch_go_latest and _fetch_python_latest (lib/workflows.sh): the
# vendor-feed fetchers behind check-versions' go and python3 lines. Fixtures
# are served through tests/mocks/curl's MOCK_CURL_STDOUT; no test touches the
# network.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

_go_fixture() {
  cat <<'JSON'
[
 {"version":"go1.29rc1","stable":false,"files":[{"filename":"go1.29rc1.linux-amd64.tar.gz"},{"filename":"go1.29rc1.linux-arm64.tar.gz"}]},
 {"version":"go1.26.9","stable":true,"files":[{"filename":"go1.26.9.linux-amd64.tar.gz"},{"filename":"go1.26.9.linux-arm64.tar.gz"}]},
 {"version":"go1.28.3","stable":true,"files":[{"filename":"go1.28.3.linux-amd64.tar.gz"}]},
 {"version":"go1.28.2","stable":true,"files":[{"filename":"go1.28.2.linux-amd64.tar.gz"},{"filename":"go1.28.2.linux-arm64.tar.gz"}]},
 {"version":"go1.27.5","stable":true,"files":[{"filename":"go1.27.5.linux-amd64.tar.gz"},{"filename":"go1.27.5.linux-arm64.tar.gz"}]}
]
JSON
}

_python_fixture() {
  cat <<'JSON'
[
 {"name":"Python 3.15.0rc1"},
 {"name":"Python install manager 26.4"},
 {"name":"Python 3.14.9"},
 {"name":"Python 3.15.1"},
 {"name":"Python 3.14.10"},
 {"name":"Python 3.10.20"}
]
JSON
}

# ── _fetch_go_latest ────────────────────────────────────────────────────────

@test "_fetch_go_latest picks highest stable release with both linux tarballs" {
  MOCK_CURL_STDOUT="$(_go_fixture)" run _fetch_go_latest
  [ "$status" -eq 0 ]
  [ "$output" = "1.28.2" ]
}

@test "_fetch_go_latest fails empty when curl fails" {
  MOCK_CURL_EXIT=22 run _fetch_go_latest
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_fetch_go_latest fails empty on a non-JSON body" {
  MOCK_CURL_STDOUT="not json" run _fetch_go_latest
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_fetch_go_latest fails empty when no stable entry qualifies" {
  MOCK_CURL_STDOUT='[{"version":"go1.29rc1","stable":false,"files":[{"filename":"go1.29rc1.linux-amd64.tar.gz"},{"filename":"go1.29rc1.linux-arm64.tar.gz"}]}]' \
    run _fetch_go_latest
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_fetch_go_latest skips malformed entries and keeps valid ones" {
  MOCK_CURL_STDOUT='[{"version":5,"stable":true,"files":[]},{"version":"go1.30.1","stable":true,"files":null},{"version":"go1.28.2","stable":true,"files":[{"filename":"go1.28.2.linux-amd64.tar.gz"},{"filename":"go1.28.2.linux-arm64.tar.gz"}]}]' \
    run _fetch_go_latest
  [ "$status" -eq 0 ]
  [ "$output" = "1.28.2" ]
}

@test "_fetch_go_latest ignores non-ASCII digit versions" {
  MOCK_CURL_STDOUT='[{"version":"go١.٢.٣","stable":true,"files":[{"filename":"go١.٢.٣.linux-amd64.tar.gz"},{"filename":"go١.٢.٣.linux-arm64.tar.gz"}]},{"version":"go1.28.2","stable":true,"files":[{"filename":"go1.28.2.linux-amd64.tar.gz"},{"filename":"go1.28.2.linux-arm64.tar.gz"}]}]' \
    run _fetch_go_latest
  [ "$status" -eq 0 ]
  [ "$output" = "1.28.2" ]
}

@test "_fetch_go_latest compares numerically: 1.10 beats 1.9.1" {
  MOCK_CURL_STDOUT='[{"version":"go1.9.1","stable":true,"files":[{"filename":"go1.9.1.linux-amd64.tar.gz"},{"filename":"go1.9.1.linux-arm64.tar.gz"}]},{"version":"go1.10","stable":true,"files":[{"filename":"go1.10.linux-amd64.tar.gz"},{"filename":"go1.10.linux-arm64.tar.gz"}]}]' \
    run _fetch_go_latest
  [ "$status" -eq 0 ]
  [ "$output" = "1.10" ]
}

# ── _fetch_python_latest ────────────────────────────────────────────────────

@test "_fetch_python_latest prints in-series and overall highest" {
  MOCK_CURL_STDOUT="$(_python_fixture)" run _fetch_python_latest 3.14
  [ "$status" -eq 0 ]
  [ "$output" = "3.14.10 3.15.1" ]
}

@test "_fetch_python_latest prints dash when series has no release" {
  MOCK_CURL_STDOUT="$(_python_fixture)" run _fetch_python_latest 3.16
  [ "$status" -eq 0 ]
  [ "$output" = "- 3.15.1" ]
}

@test "_fetch_python_latest fails empty when curl fails" {
  MOCK_CURL_EXIT=22 run _fetch_python_latest 3.14
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_fetch_python_latest fails empty on a non-JSON body" {
  MOCK_CURL_STDOUT="not json" run _fetch_python_latest 3.14
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_fetch_python_latest fails empty when body is a dict, not a list" {
  MOCK_CURL_STDOUT='{"results": []}' run _fetch_python_latest 3.14
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_fetch_python_latest fails empty when no name is Python X.Y.Z" {
  MOCK_CURL_STDOUT='[{"name":"Python install manager 26.4"},{"name":"Python 3.15.0rc1"}]' \
    run _fetch_python_latest 3.14
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ── request shape: no credentials, bounded, single request ─────────────────

@test "go request is bounded and carries no credentials even with GITHUB_TOKEN set" {
  export GITHUB_TOKEN=tok
  export MOCK_CURL_STDIN_FILE="${BATS_TEST_TMPDIR}/stdin"
  MOCK_CURL_STDOUT="$(_go_fixture)" run _fetch_go_latest
  [ "$status" -eq 0 ]
  grep -qE -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}"
  [ "$(command grep -c 'Authorization' "${MOCK_CALLS_FILE}")" -eq 0 ]
  [ "$(command grep -cE -- ' (-H|--header)' "${MOCK_CALLS_FILE}")" -eq 0 ]
  [ ! -s "${MOCK_CURL_STDIN_FILE}" ]
  [ "$(command grep -c 'go.dev' "${MOCK_CALLS_FILE}")" -eq 1 ]
}

@test "python request is bounded, credential-free and a single request" {
  export GITHUB_TOKEN=tok
  export MOCK_CURL_STDIN_FILE="${BATS_TEST_TMPDIR}/stdin"
  MOCK_CURL_STDOUT="$(_python_fixture)" run _fetch_python_latest 3.14
  [ "$status" -eq 0 ]
  grep -qE -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}"
  [ "$(command grep -c 'Authorization' "${MOCK_CALLS_FILE}")" -eq 0 ]
  [ "$(command grep -cE -- ' (-H|--header)' "${MOCK_CALLS_FILE}")" -eq 0 ]
  [ ! -s "${MOCK_CURL_STDIN_FILE}" ]
  [ "$(command grep -c 'python.org' "${MOCK_CALLS_FILE}")" -eq 1 ]
}

# ── _check_one_pin_version ──────────────────────────────────────────────────

_stub_all_but_pins() {
  _check_one_version() { printf '  [OK]       %-12s\n' "$1"; }
  _check_cv_homebrew_install() { printf '  [OK]       brew\n'; }
  _check_one_cargo_version() { printf '  [OK]       %s\n' "$1"; }
  # shellcheck disable=SC2034 # read by run_check_versions, sourced from setup_env.sh
  CARGO_TOOLS=(foo@1.0.0)
}

@test "go pin equal to feed latest is OK and ignores the installed go" {
  local _bin="${BATS_TEST_TMPDIR}/gobin"
  mkdir -p "${_bin}"
  printf '#!/usr/bin/env bash\nprintf "go version go9.9.9 linux/amd64\\n"\n' > "${_bin}/go"
  chmod +x "${_bin}/go"
  export PATH="${_bin}:${PATH}"
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  _fetch_go_latest() { printf '1.27.1'; }
  run _check_one_pin_version "go" "1.27"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"pinned=1.27.1"* ]]
  [[ "$output" == *"latest=1.27.1"* ]]
  [[ "$output" != *"9.9.9"* ]]
  [[ "$output" != *"installed="* ]]
}

@test "go pin behind feed latest is OUTDATED with rc 1" {
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  _fetch_go_latest() { printf '1.27.2'; }
  run _check_one_pin_version "go" "1.27"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[OUTDATED]"* ]]
  [[ "$output" == *"pinned=1.27.1"* ]]
  [[ "$output" == *"latest=1.27.2"* ]]
}

@test "go pin ahead of feed latest is OK (numeric, not string, compare)" {
  export GO_DOWNLOAD_FILENAME="go1.28.0.linux-amd64.tar.gz"
  _fetch_go_latest() { printf '1.27.2'; }
  run _check_one_pin_version "go" "1.28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
}

@test "go numeric compare: 1.9.0 pin is behind 1.10.0" {
  export GO_DOWNLOAD_FILENAME="go1.9.0.linux-amd64.tar.gz"
  _fetch_go_latest() { printf '1.10.0'; }
  run _check_one_pin_version "go" "1.9"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[OUTDATED]"* ]]
}

@test "go with unparseable GO_DOWNLOAD_FILENAME warns and returns 0" {
  export GO_DOWNLOAD_FILENAME="garbage"
  _fetch_go_latest() { printf '1.27.2'; }
  run _check_one_pin_version "go" "1.27"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"go could not parse pinned version"* ]]
}

@test "go empty fetch warns could not fetch latest version" {
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  _fetch_go_latest() { return 1; }
  run _check_one_pin_version "go" "1.27"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"could not fetch latest version"* ]]
}

@test "python3 pin behind series latest is OUTDATED and adds series INFO" {
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run _check_one_pin_version "python3" "3.14.6"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[OUTDATED]"* ]]
  [[ "$output" == *"pinned=3.14.6"* ]]
  [[ "$output" == *"latest=3.14.8"* ]]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"3.15 series available (series move: requires-python, uv lock)"* ]]
}

@test "python3 pin at series latest is OK with INFO when a newer series exists" {
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run _check_one_pin_version "python3" "3.14.8"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"3.15 series available"* ]]
}

@test "python3 pin equal to overall latest has no INFO" {
  _fetch_python_latest() { printf '3.15.1 3.15.1'; }
  run _check_one_pin_version "python3" "3.15.1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" != *"[INFO]"* ]]
}

@test "python3 pin ahead of series latest is OK" {
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run _check_one_pin_version "python3" "3.14.9"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" != *"[OUTDATED]"* ]]
}

@test "python3 series absent from feed warns with pin and overall latest" {
  _fetch_python_latest() { printf -- '- 3.15.1'; }
  run _check_one_pin_version "python3" "3.16.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"python3 no 3.16 release in the feed yet (pinned=3.16.0 latest=3.15.1)"* ]]
  [[ "$output" != *"could not fetch"* ]]
}

@test "python3 empty fetch warns could not fetch latest version" {
  _fetch_python_latest() { return 1; }
  run _check_one_pin_version "python3" "3.14.8"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"could not fetch latest version"* ]]
}

@test "python3 not on PATH warns python3 not found, not could not fetch" {
  local _empty="${BATS_TEST_TMPDIR}/emptybin"
  mkdir -p "${_empty}"
  local _out _rc=0
  _out=$(PATH="${_empty}" _check_one_pin_version "go" "1.27") || _rc=$?
  [ "${_rc}" -eq 0 ]
  [[ "${_out}" == *"[WARN]"* ]]
  [[ "${_out}" == *"python3 not found; cannot read the release feed"* ]]
  [[ "${_out}" != *"could not fetch"* ]]
}

# ── run_check_versions integration ──────────────────────────────────────────

@test "R20 steady state: pin at series latest with newer series reports 0 outdated, rc 0" {
  _stub_all_but_pins
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  export PYTHON_VER="3.14.8"
  _fetch_go_latest() { printf '1.27.1'; }
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run run_check_versions
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"0 outdated"* ]]
  [[ "$output" == *"7 OK"* ]] || [[ "$output" == *"OK"* ]]
}

@test "INFO line is not counted: OUTDATED python3 with INFO counts 1 outdated" {
  _stub_all_but_pins
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  export PYTHON_VER="3.14.6"
  _fetch_go_latest() { printf '1.27.1'; }
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run run_check_versions
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 outdated"* ]]
}

@test "token-refused: go and python3 still run, 5 checks not run" {
  _stub_all_but_pins
  export GITHUB_TOKEN=$'a\nb'
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  export PYTHON_VER="3.14.8"
  _fetch_go_latest() { printf '1.27.1'; }
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run run_check_versions
  [ "$status" -eq 2 ]
  [[ "$output" == *"the 5 checks that send it were not run"* ]]
  [[ "$output" == *"5 not checked"* ]]
  [[ "$output" == *"pinned=1.27.1"* ]]
  [[ "$output" == *"pinned=3.14.8"* ]]
}
