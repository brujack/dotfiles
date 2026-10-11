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
