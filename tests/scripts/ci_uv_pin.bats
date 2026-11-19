#!/usr/bin/env bats
# CI's pinned uv must equal lib/constants.sh, per job, and each pinned-uv job
# must export PINNED_UV_BIN so make test resolves the uv its install step wrote
# (spec 2026-11-19-pinned-uv-renderings-design.md, Design 6, R15, R16).
#
# Parsed with awk, not python3 + yaml: the suite runs on the macOS and Linux
# runners, and neither image guarantees pyyaml for the system python3.
# Parsing is per job, never a whole-file grep: ci.yml holds two uv pins for two
# different assets.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CI_YML="${REPO_ROOT}/.github/workflows/ci.yml"
  REFRESH_YML="${REPO_ROOT}/.github/workflows/uv-lock-refresh.yml"
  # constants.sh defines plain assignments; source it in the test shell.
  # shellcheck source=/dev/null  # path resolved at runtime from BATS_TEST_DIRNAME
  source "${REPO_ROOT}/lib/constants.sh"
}

# _uv_job_records <workflow>: one line per job that sets UV_VER or installs uv
# (an `Install uv (pinned)` step or an astral-sh/uv release URL), as
# job|UV_VER|UV_SHA256|asset|PINNED_UV_BIN, where asset is linux-amd64 or
# darwin-arm64 from the install URL, and PINNED_UV_BIN is read from the
# job-level env only (6-space key under a 4-space `env:`).
_uv_job_records() {
  awk '
    function flush() {
      if (job != "" && (ver != "" || seen)) printf "%s|%s|%s|%s|%s\n", job, ver, sha, asset, pin
      ver = ""; sha = ""; asset = ""; pin = ""; inenv = 0; seen = 0
    }
    function val(s) { sub(/^[^:]*:[[:space:]]*/, "", s); sub(/[[:space:]]*#.*$/, "", s); gsub(/"/, "", s); return s }
    /^[[:space:]]*#/ { next }
    /^jobs:/ { injobs = 1; next }
    /^[a-z]/ { flush(); job = ""; injobs = 0; next }
    injobs && /^  [a-zA-Z_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); next }
    job == "" { next }
    /^    env:[[:space:]]*$/ { inenv = 1; next }
    /^    [^ ]/ { inenv = 0 }
    inenv && /^      PINNED_UV_BIN:/ { pin = val($0) }
    /^[[:space:]]+UV_VER:/ { ver = val($0); seen = 1 }
    /Install uv \(pinned\)/ || /astral-sh\/uv\/releases\/download/ { seen = 1 }
    /^[[:space:]]+UV_SHA256:/ { sha = val($0) }
    /uv-x86_64-unknown-linux-gnu\.tar\.gz/ && asset == "" { asset = "linux-amd64" }
    /uv-aarch64-apple-darwin\.tar\.gz/ && asset == "" { asset = "darwin-arm64" }
    END { flush() }
  ' "$1"
}

# _check_uv_pins <workflow>...: print one line per violation, naming
# <file>:<job>; return 1 if any, or if no pinned-uv job was found at all.
_check_uv_pins() {
  local wf job ver sha asset pin want_sha bad=0 total=0 base
  for wf in "$@"; do
    base="$(basename "${wf}")"
    while IFS='|' read -r job ver sha asset pin; do
      [[ -n "${job}" ]] || continue
      total=$((total + 1))
      if [[ -z "${ver}" ]]; then
        printf '%s:%s: installs uv but sets no UV_VER\n' "${base}" "${job}"; bad=1; continue
      fi
      case "${asset}" in
        linux-amd64) want_sha="${UV_SHA256_LINUX_AMD64}" ;;
        darwin-arm64) want_sha="${UV_SHA256_DARWIN_ARM64}" ;;
        *) printf '%s:%s: unrecognised uv asset in install URL\n' "${base}" "${job}"; bad=1; continue ;;
      esac
      if [[ "${ver}" != "${UV_VER}" ]]; then
        printf '%s:%s: UV_VER %s != constants.sh %s\n' "${base}" "${job}" "${ver}" "${UV_VER}"; bad=1
      fi
      if [[ "${sha}" != "${want_sha}" ]]; then
        printf '%s:%s: UV_SHA256 %s != constants.sh %s asset digest\n' "${base}" "${job}" "${sha}" "${asset}"; bad=1
      fi
      if [[ "${pin}" != "/usr/local/bin/uv" ]]; then
        printf '%s:%s: job env PINNED_UV_BIN is "%s", want /usr/local/bin/uv\n' "${base}" "${job}" "${pin}"; bad=1
      fi
    done < <(_uv_job_records "${wf}")
  done
  if [[ "${total}" -ne 3 ]]; then
    printf 'found %s pinned-uv jobs, want exactly 3\n' "${total}"; bad=1
  fi
  return "${bad}"
}

@test "ci_uv_pin: every pinned-uv job matches constants.sh and sets PINNED_UV_BIN" {
  run _check_uv_pins "${CI_YML}" "${REFRESH_YML}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ci_uv_pin: parser finds the three jobs with their assets" {
  run _uv_job_records "${CI_YML}"
  [[ "${output}" == *"test-shard|"*"|linux-amd64|"* ]]
  [[ "${output}" == *"test-macos-shard|"*"|darwin-arm64|"* ]]
  run _uv_job_records "${REFRESH_YML}"
  [[ "${output}" == "refresh|"*"|linux-amd64|"* ]]
}

@test "ci_uv_pin: an empty parse fails" {
  : > "${BATS_TEST_TMPDIR}/empty.yml"
  run _check_uv_pins "${BATS_TEST_TMPDIR}/empty.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found 0 pinned-uv jobs"* ]]
}

@test "ci_uv_pin: a mismatched fixture workflow fails" {
  local fixture="${BATS_TEST_TMPDIR}/ci.yml"
  # First UV_VER in ci.yml belongs to test-shard.
  # awk, not sed '0,/re/': that address is GNU-only and a no-op on BSD sed.
  awk '!d && /UV_VER:/ { sub(/"[^"]*"/, "\"0.0.1\""); d = 1 } 1' "${CI_YML}" > "${fixture}"
  run cmp -s "${CI_YML}" "${fixture}"
  [ "$status" -ne 0 ]
  run _check_uv_pins "${fixture}" "${REFRESH_YML}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ci.yml:test-shard: UV_VER 0.0.1 != constants.sh ${UV_VER}"* ]]
}

@test "ci_uv_pin: a uv-installing job with no UV_VER fails" {
  local fixture="${BATS_TEST_TMPDIR}/extra.yml"
  cat > "${fixture}" <<'YML'
jobs:
  sneaky:
    runs-on: ubuntu-latest
    env:
      PINNED_UV_BIN: /usr/local/bin/uv
    steps:
      - name: Install uv
        run: curl -fsSL -o /tmp/uv.tgz https://github.com/astral-sh/uv/releases/download/0.9.9/uv-x86_64-unknown-linux-gnu.tar.gz
YML
  run _check_uv_pins "${CI_YML}" "${REFRESH_YML}" "${fixture}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"extra.yml:sneaky: installs uv but sets no UV_VER"* ]]
}

@test "ci_uv_pin: a comment inside the job env block does not hide PINNED_UV_BIN" {
  local fixture="${BATS_TEST_TMPDIR}/ci.yml"
  # Insert a comment line between the first `env:` and its PINNED_UV_BIN line.
  awk '1; !d && /^    env:$/ { print "    # a comment inside the env block"; d = 1 }' "${CI_YML}" > "${fixture}"
  run cmp -s "${CI_YML}" "${fixture}"
  [ "$status" -ne 0 ]
  run _check_uv_pins "${fixture}" "${REFRESH_YML}"
  [ "$status" -eq 0 ]
}
