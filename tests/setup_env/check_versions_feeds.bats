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
  # Default every test to a private copy so no writer can touch the real file.
  _CP="${BATS_TEST_TMPDIR}/constants.sh"
  cp "${REPO_ROOT}/lib/constants.sh" "${_CP}"
  export _OVERRIDE_CONSTANTS_PATH="${_CP}"
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
  _check_one_pinned_release() { printf '  [OK]       %-12s\n' "$1"; }
  _check_cv_homebrew_install() { printf '  [OK]       brew\n'; }
  _check_one_cargo_version() { printf '  [OK]       %s\n' "$1"; }
  # shellcheck disable=SC2034 # read by run_check_versions, sourced from setup_env.sh
  CARGO_TOOLS=(foo@1.0.0)
}

@test "go pin equal to feed latest is OK and ignores the installed go" {
  local _bin="${BATS_TEST_TMPDIR}/gobin"
  mkdir -p "${_bin}"
  printf '#!/bin/bash\nprintf "go version go9.9.9 linux/amd64\\n"\n' > "${_bin}/go"
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

@test "packer pin behind GitHub latest is OUTDATED even when the installed packer equals latest" {
  local _bin="${BATS_TEST_TMPDIR}/pbin"
  mkdir -p "${_bin}"
  printf '#!/bin/bash\nprintf "Packer v1.17.0\\n"\n' > "${_bin}/packer"
  chmod +x "${_bin}/packer"
  export PATH="${_bin}:${PATH}"
  # Real _check_one_pinned_release; only its network call and the other checks are stubbed.
  _check_one_version() { printf '  [OK]       %-12s\n' "$1"; }
  _check_one_pin_version() { printf '  [OK]       %-12s\n' "$1"; }
  _check_cv_homebrew_install() { printf '  [OK]       brew\n'; }
  _check_one_cargo_version() { printf '  [OK]       %s\n' "$1"; }
  # shellcheck disable=SC2034 # read by run_check_versions, sourced from setup_env.sh
  CARGO_TOOLS=(foo@1.0.0)
  _fetch_github_latest() { printf 'v1.17.0'; }
  # shellcheck disable=SC2034 # read by run_check_versions, sourced from setup_env.sh
  PACKER_VER="1.16.1"
  run run_check_versions
  [ "$status" -eq 1 ]
  [[ "$output" == *"[OUTDATED] packer"*"pinned=1.16.1"*"latest=1.17.0"* ]]
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
  [[ "$output" == *"[WARN]     go           could not parse pinned version"* ]]
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
  [[ "$output" == *"[WARN]     python3      no 3.16 release in the feed yet (pinned=3.16.0 latest=3.15.1)"* ]]
  [[ "$output" != *"could not fetch"* ]]
}

@test "python3 two-part pin warns could not parse pinned version, not a feed cause" {
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run _check_one_pin_version "python3" "3.14"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]     python3      could not parse pinned version"* ]]
  [[ "$output" != *"no 3 release"* ]]
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
  [[ "$output" == *"10 OK"* ]]
  [[ "$output" == *"[OK]       python3      pinned=3.14.8"* ]]
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

@test "token-refused: go and python3 still run, 7 checks not run" {
  _stub_all_but_pins
  export GITHUB_TOKEN=$'a\nb'
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  export PYTHON_VER="3.14.8"
  _fetch_go_latest() { printf '1.27.1'; }
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run run_check_versions
  [ "$status" -eq 2 ]
  [[ "$output" == *"the 7 checks that send it were not run"* ]]
  [[ "$output" == *"7 not checked"* ]]
  [[ "$output" == *"pinned=1.27.1"* ]]
  [[ "$output" == *"pinned=3.14.8"* ]]
  local _warn_ln _last_check_ln _summary_ln
  _warn_ln=$(printf '%s\n' "$output" | grep -n 'GITHUB_TOKEN' | cut -d: -f1)
  _last_check_ln=$(printf '%s\n' "$output" | grep -n '^  \[' | grep -v 'GITHUB_TOKEN' | tail -1 | cut -d: -f1)
  _summary_ln=$(printf '%s\n' "$output" | grep -n ' outdated, ' | cut -d: -f1)
  [ "${_warn_ln}" -gt "${_last_check_ln}" ]
  [ "${_warn_ln}" -lt "${_summary_ln}" ]
}

# ── --update writers (_update_go_pin, _update_python_pin) ───────────────────

# Per-test writable copy of lib/constants.sh; the real file is never touched.
_seed_constants() {
  _CP="${BATS_TEST_TMPDIR}/constants.sh"
  cp "${REPO_ROOT}/lib/constants.sh" "${_CP}"
  export _OVERRIDE_CONSTANTS_PATH="${_CP}"
}

# Pins go at GO_VER=<series>, filename go<full>; fails if the seed did not take.
_seed_go() {
  sed -i.bak -e "s|^GO_VER=.*|GO_VER=\"$1\"|" \
    -e "s|^GO_DOWNLOAD_FILENAME=.*|GO_DOWNLOAD_FILENAME=\"go$2.linux-\${_LINUX_ARCH}.tar.gz\"|" "${_CP}"
  rm -f "${_CP}.bak"
  grep -Fqx "GO_VER=\"$1\"" "${_CP}"
}

# A PATH holding only the named tools (no go, no pyenv unless asked for).
_shim_path() {
  local _d="${BATS_TEST_TMPDIR}/shim" _t
  mkdir -p "${_d}"
  for _t in sed grep rm cut dirname cat head cp mv; do
    ln -sf "$(PATH=/usr/bin:/bin command -v "${_t}")" "${_d}/${_t}"
  done
  printf '%s' "${_d}"
}

_stub_go() {
  local _d="$1" _v="$2"
  printf '#!/bin/bash\nprintf "go version go%s linux/amd64\\n"\n' "${_v}" > "${_d}/go"
  chmod +x "${_d}/go"
}

# Argument-checking stand-in for _fetch_go_sha256: answers only for the one
# version the test targets, so a writer that passes the wrong value (the
# series, say) gets rc 1 instead of a hash and the test goes red.
_stub_go_sha256() {
  _STUB_GO_VER="$1"
  _fetch_go_sha256() {
    [[ "$1" == "${_STUB_GO_VER}" ]] || return 1
    printf '%s %s\n' "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})"
  }
}

@test "go update within the series moves the filename and keeps GO_VER" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.27.2"
  _shim="$(_shim_path)"
  PATH="${_shim}" run _prompt_version_update "go" "GO_VER" "1.27" "1.27.2" <<< "y"
  [ "$status" -eq 0 ]
  grep -Fqx 'GO_VER="1.27"' "${_CP}"
  grep -Fqx 'GO_DOWNLOAD_FILENAME="go1.27.2.linux-${_LINUX_ARCH}.tar.gz"' "${_CP}"
  [[ "$output" == *"Updated GO_VER → 1.27.2"* ]]
  grep -Fqx 'GO_SHA256_AMD64="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "${_CP}"
  grep -Fqx 'GO_SHA256_ARM64="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "${_CP}"
  [[ "$output" == *"go: after this change merges and each machine pulls: on macOS run brew upgrade go; on Linux run ./setup_env.sh -t developer"* ]]
}

@test "go update across a minor moves GO_VER and the filename" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.28.0"
  _shim="$(_shim_path)"
  PATH="${_shim}" run _prompt_version_update "go" "GO_VER" "1.27" "1.28.0" <<< "y"
  [ "$status" -eq 0 ]
  grep -Fqx 'GO_VER="1.28"' "${_CP}"
  grep -Fqx 'GO_DOWNLOAD_FILENAME="go1.28.0.linux-${_LINUX_ARCH}.tar.gz"' "${_CP}"
  [[ "$output" == *"Updated GO_VER → 1.28.0"* ]]
  grep -Fqx 'GO_SHA256_AMD64="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "${_CP}"
  grep -Fqx 'GO_SHA256_ARM64="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "${_CP}"
}

@test "go read-back failure: rc 1, names the constant, no Updated" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.27.2"
  sed -i.bak '/^GO_VER=/d' "${_CP}"; rm -f "${_CP}.bak"
  _shim="$(_shim_path)"
  PATH="${_shim}" run _update_go_pin "1.27.2"
  [ "$status" -eq 1 ]
  [[ "$output" == *'go: pin update failed: GO_VER is not 1.27'* ]]
  if compgen -G "${_CP}.new*" >/dev/null; then false; fi
  PATH="${_shim}" run _prompt_version_update "go" "GO_VER" "1.27" "1.27.2" <<< "y"
  [[ "$output" == *"pin update failed"* ]]
  [[ "$output" != *"Updated"* ]]
}

@test "go mv failure: rc 1, original unchanged, no temp file left" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.27.2"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  export MOCK_MV_FAIL_ARGS=".new."
  run _update_go_pin "1.27.2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: pin update failed: could not replace"* ]]
  grep -q "mv .*\.new\." "${MOCK_CALLS_FILE}"
  cmp "${BATS_TEST_TMPDIR}/before" "${_CP}"
  if compgen -G "${_CP}.new*" >/dev/null; then false; fi
}

@test "go local-series warning: installed go outside the new series warns" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.28.0"
  _shim="$(_shim_path)"
  _stub_go "${_shim}" "1.27.1"
  PATH="${_shim}" run _update_go_pin "1.28.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"go: this machine runs 1.27.1, outside the new 1.28 series; doctor fails here until go is upgraded"* ]]
}

@test "go local-series warning: installed go inside the new series is silent" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.28.0"
  _shim="$(_shim_path)"
  _stub_go "${_shim}" "1.28.0"
  PATH="${_shim}" run _update_go_pin "1.28.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"go: after this change merges"* ]]   # positive: the writer ran
  [[ "$output" != *"this machine runs"* ]]
}

@test "go local-series warning: no go on PATH is silent and prints no empty version" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.28.0"
  _shim="$(_shim_path)"
  [ ! -e "${_shim}/go" ]
  PATH="${_shim}" run _update_go_pin "1.28.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"go: after this change merges"* ]]
  [[ "$output" != *"this machine runs"* ]]
}

@test "python update writes PYTHON_VER and prints exact next steps" {
  _seed_constants
  sed -i.bak 's|^PYTHON_VER=.*|PYTHON_VER="3.14.6"|' "${_CP}"; rm -f "${_CP}.bak"
  export MOCK_PYENV_INSTALL_LIST=$'  3.14.8\n  3.14.8t'
  run _prompt_version_update "python3" "PYTHON_VER" "3.14.6" "3.14.8" <<< "y"
  [ "$status" -eq 0 ]
  grep -Fqx 'PYTHON_VER="3.14.8"' "${_CP}"
  [[ "$output" == *"Updated PYTHON_VER → 3.14.8"* ]]
  [[ "$output" == *"python3: after this change merges and each machine pulls: run brew upgrade pyenv, then on macOS pyenv install 3.14.8 && ./setup_env.sh -t ansible; on Linux ./setup_env.sh -t ansible"* ]]
  [[ "$output" != *"recreate-venv"* ]]
}

@test "python guard: only 3.14.8t listed refuses, file byte-identical, pyenv asked" {
  _seed_constants
  sed -i.bak 's|^PYTHON_VER=.*|PYTHON_VER="3.14.6"|' "${_CP}"; rm -f "${_CP}.bak"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  export MOCK_PYENV_INSTALL_LIST=$'  3.14.8t\n  3.14.7'
  run _prompt_version_update "python3" "PYTHON_VER" "3.14.6" "3.14.8" <<< "y"
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  [[ "$output" == *"python3: pyenv on this machine cannot build 3.14.8; run brew upgrade pyenv"* ]]
  [[ "$output" != *"Updated"* ]]
  grep -Fq "pyenv install --list" "${MOCK_CALLS_FILE}"
}

@test "python guard: dots are literal (3.14x8 in the list does not satisfy 3.14.8)" {
  _seed_constants
  sed -i.bak 's|^PYTHON_VER=.*|PYTHON_VER="3.14.6"|' "${_CP}"; rm -f "${_CP}.bak"
  export MOCK_PYENV_INSTALL_LIST=$'  3.14x8'
  run _update_python_pin "3.14.6" "3.14.8"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot build 3.14.8"* ]]
}

@test "python guard: no pyenv refuses, file byte-identical, no Updated" {
  _seed_constants
  sed -i.bak 's|^PYTHON_VER=.*|PYTHON_VER="3.14.6"|' "${_CP}"; rm -f "${_CP}.bak"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  _shim="$(_shim_path)"
  [ ! -e "${_shim}/pyenv" ]
  PATH="${_shim}" run _prompt_version_update "python3" "PYTHON_VER" "3.14.6" "3.14.8" <<< "y"
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  [[ "$output" == *"python3: pyenv on this machine cannot build 3.14.8; run brew upgrade pyenv"* ]]
  [[ "$output" != *"Updated"* ]]
}

@test "python read-back failure: rc 1, pin update failed, no Updated" {
  _seed_constants
  sed -i.bak '/^PYTHON_VER=/d' "${_CP}"; rm -f "${_CP}.bak"
  export MOCK_PYENV_INSTALL_LIST=$'  3.14.8'
  run _update_python_pin "3.14.6" "3.14.8"
  [ "$status" -eq 1 ]
  [[ "$output" == *"python3: pin update failed: PYTHON_VER is not 3.14.8"* ]]
  run _prompt_version_update "python3" "PYTHON_VER" "3.14.6" "3.14.8" <<< "y"
  [[ "$output" != *"Updated"* ]]
}

@test "pin ahead of the feed with UPDATE_VERSIONS=1: both OK, no prompt, constants byte-identical" {
  _stub_all_but_pins
  _seed_constants
  _seed_go "1.28" "1.28.0"
  sed -i.bak 's|^PYTHON_VER=.*|PYTHON_VER="3.14.9"|' "${_CP}"; rm -f "${_CP}.bak"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  export GO_DOWNLOAD_FILENAME="go1.28.0.linux-amd64.tar.gz" GO_VER="1.28" PYTHON_VER="3.14.9"
  export UPDATE_VERSIONS=1
  _fetch_go_latest() { printf '1.27.2'; }
  _fetch_python_latest() { printf '3.14.8 3.15.1'; }
  run run_check_versions <<< "y"
  [[ "$output" == *"[OK]       go"* ]]
  [[ "$output" == *"[OK]       python3"* ]]
  [[ "$output" != *"Update go"* ]]
  [[ "$output" != *"Update python3"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
}

@test "outdated go under UPDATE_VERSIONS=1 passes the full latest to the writer" {
  _stub_all_but_pins
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.27.2"
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz" GO_VER="1.27" PYTHON_VER="3.14.8"
  export UPDATE_VERSIONS=1
  _fetch_go_latest() { printf '1.27.2'; }
  _fetch_python_latest() { printf '3.14.8 3.14.8'; }
  run run_check_versions <<< "y"
  grep -Fqx 'GO_DOWNLOAD_FILENAME="go1.27.2.linux-${_LINUX_ARCH}.tar.gz"' "${_CP}"
  [[ "$output" == *"Updated GO_VER → 1.27.2"* ]]
  grep -Fqx 'GO_SHA256_AMD64="'"$(printf 'a%.0s' {1..64})"'"' "${_CP}"
  grep -Fqx 'GO_SHA256_ARM64="'"$(printf 'b%.0s' {1..64})"'"' "${_CP}"
}

@test "go update refuses a two-part latest: byte-identical, message, no Updated" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  run _prompt_version_update "go" "GO_VER" "1.27" "1.28" <<< "y"
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  [[ "$output" == *"go: refusing pin update: latest 1.28 is not X.Y.Z"* ]]
  [[ "$output" != *"Updated"* ]]
  grep -Fqx 'GO_VER="1.27"' "${_CP}"
}

@test "go update is atomic when the pinned filename has no patch" {
  _seed_constants
  _seed_go "1.27" "1.27"
  _stub_go_sha256 "1.28.0"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  run _update_go_pin "1.28.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pin update failed: GO_DOWNLOAD_FILENAME is not"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  if compgen -G "${BATS_TEST_TMPDIR}/constants.sh.new*"; then false; fi
}

@test "go update is atomic when GO_DOWNLOAD_FILENAME line is missing" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.28.0"
  sed -i.bak '/^GO_DOWNLOAD_FILENAME=/d' "${_CP}"; rm -f "${_CP}.bak"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  run _update_go_pin "1.28.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GO_DOWNLOAD_FILENAME is not"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  if compgen -G "${BATS_TEST_TMPDIR}/constants.sh.new*"; then false; fi
}

@test "go update success leaves no temp file and the new pins in place" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  _stub_go_sha256 "1.28.0"
  run _update_go_pin "1.28.0"
  [ "$status" -eq 0 ]
  grep -Fqx 'GO_VER="1.28"' "${_CP}"
  grep -Fqx 'GO_SHA256_AMD64="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "${_CP}"
  grep -Fqx 'GO_SHA256_ARM64="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "${_CP}"
  if compgen -G "${BATS_TEST_TMPDIR}/constants.sh.new*"; then false; fi
}

# ── _fetch_go_sha256 and the sha256 pins ────────────────────────────────────

_sha_a="$(printf 'a%.0s' {1..64})"
_sha_b="$(printf 'b%.0s' {1..64})"

_go_sha_fixture() {
  cat <<JSON
[
 {"version":"go1.28.2","stable":true,"files":[{"filename":"go1.28.2.linux-amd64.tar.gz","sha256":"${_sha_a}"},{"filename":"go1.28.2.linux-arm64.tar.gz","sha256":"${_sha_b}"}]},
 {"version":"go1.28.1","stable":true,"files":[{"filename":"go1.28.1.linux-amd64.tar.gz","sha256":"${_sha_a}"}]},
 {"version":"go1.28.0","stable":true,"files":[{"filename":"go1.28.0.linux-amd64.tar.gz","sha256":"${_sha_a}"},{"filename":"go1.28.0.linux-arm64.tar.gz"}]},
 {"version":"go1.28.4","stable":true,"files":[{"filename":["x"],"sha256":"${_sha_a}"},{"filename":"go1.28.4.linux-amd64.tar.gz","sha256":"${_sha_a}"},{"filename":"go1.28.4.linux-arm64.tar.gz","sha256":"${_sha_b}"}]},
 {"version":"go1.27.9","stable":true,"files":[{"filename":"go1.27.9.linux-amd64.tar.gz","sha256":"${_sha_a}"},{"filename":"go1.27.9.linux-arm64.tar.gz","sha256":"${_sha_b:1}"}]},
 {"version":"go1.28.5","stable":false,"files":[{"filename":"go1.28.5.linux-amd64.tar.gz","sha256":"${_sha_a}"},{"filename":"go1.28.5.linux-arm64.tar.gz","sha256":"${_sha_b}"}]}
]
JSON
}

@test "_fetch_go_sha256 prints amd64 and arm64 hashes for a present version" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "1.28.2"
  [ "$status" -eq 0 ]
  [ "$output" = "${_sha_a} ${_sha_b}" ]
}

@test "_fetch_go_sha256 fails empty when the arm64 file is missing" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "1.28.1"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_fetch_go_sha256 fails empty when a sha256 field is missing" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "1.28.0"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_fetch_go_sha256 fails empty on a 63-char hash" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "1.27.9"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_fetch_go_sha256 fails empty for an unstable release with otherwise valid files" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "1.28.5"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_fetch_go_sha256 rejects a malformed version before any fetch" {
  local _v
  for _v in "" "1.28rc1"; do
    : > "${MOCK_CALLS_FILE}"
    MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "${_v}"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    refute_grep "^curl " "${MOCK_CALLS_FILE}"
  done
}

@test "_fetch_go_sha256 fails empty for an unknown version" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "9.9.9"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_fetch_go_sha256 fails empty when curl fails" {
  MOCK_CURL_EXIT=22 run _fetch_go_sha256 "1.28.2"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_fetch_go_sha256 fails empty on a non-JSON body" {
  MOCK_CURL_STDOUT="not json" run _fetch_go_sha256 "1.28.2"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "go update refuses when the feed has no sha256: rc 1, constants byte-identical" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  _fetch_go_sha256() { return 1; }
  run _update_go_pin "1.28.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not get sha256 for"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  if compgen -G "${_CP}.new*" >/dev/null; then false; fi
}

@test "go update read-back failure names a missing GO_SHA256_AMD64 line" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  sed -i.bak '/^GO_SHA256_AMD64=/d' "${_CP}"; rm -f "${_CP}.bak"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  _stub_go_sha256 "1.28.0"
  run _update_go_pin "1.28.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: pin update failed: GO_SHA256_AMD64 is not ${_sha_a}"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  if compgen -G "${_CP}.new*" >/dev/null; then false; fi
}

@test "go update read-back failure names a missing GO_SHA256_ARM64 line" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  sed -i.bak '/^GO_SHA256_ARM64=/d' "${_CP}"; rm -f "${_CP}.bak"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  _stub_go_sha256 "1.28.0"
  run _update_go_pin "1.28.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: pin update failed: GO_SHA256_ARM64 is not ${_sha_b}"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  if compgen -G "${_CP}.new*" >/dev/null; then false; fi
}

@test "_fetch_go_sha256 tolerates a list-valued filename: no traceback, rc 0 from valid entries" {
  MOCK_CURL_STDOUT="$(_go_sha_fixture)" run _fetch_go_sha256 "1.28.4"
  [ "$status" -eq 0 ]
  [ "$output" = "${_sha_a} ${_sha_b}" ]
}

@test "_fetch_go_sha256 fails empty without a traceback when the only filename is a list" {
  MOCK_CURL_STDOUT='[{"version":"go1.28.5","stable":true,"files":[{"filename":["x"],"sha256":"'"${_sha_a}"'"}]}]' \
    run _fetch_go_sha256 "1.28.5"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "go update refuses a non-hex arm64 digest: rc 1, constants byte-identical" {
  _seed_constants
  _seed_go "1.27" "1.27.1"
  cp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  _fetch_go_sha256() {
    [[ "$1" == "1.28.0" ]] || return 1
    printf '%s %s\n' "${_sha_a}" "$(printf 'z%.0s' {1..64})"
  }
  run _update_go_pin "1.28.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not get sha256 for 1.28.0"* ]]
  cmp "${_CP}" "${BATS_TEST_TMPDIR}/before"
  if compgen -G "${_CP}.new*" >/dev/null; then false; fi
}
