#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/sync-requirements-ci.sh"
  # Never point at the tracked file: the drift and missing cases mutate it, and
  # a crash between mutating and restoring would leave the repo dirty.
  TARGET="${BATS_TEST_TMPDIR}/requirements-ci.txt"
  export REQUIREMENTS_CI_TARGET="${TARGET}"
  cp "${REPO_ROOT}/requirements-ci.txt" "${TARGET}"
}

@test "check passes against the committed rendering" {
  run "${SCRIPT}" check
  [ "${status}" -eq 0 ]
}

@test "check fails when the rendering has drifted" {
  printf 'ruff==0.0.1\n' >> "${TARGET}"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"DRIFT"* ]]
}

@test "check fails when the rendering is missing entirely" {
  rm -f "${TARGET}"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"MISSING"* ]]
}

@test "the rendering carries no machine-specific path" {
  # uv's own header echoes the argv it was given, including an absolute
  # --project path. A leaked path would match on a dev machine and never in CI.
  if grep -qE '^[^#]*(/Users/|/home/|/private/)' "${TARGET}"; then
    printf "rendering contains an absolute path\n" >&2
    return 1
  fi
  # positive control: the file must actually have content to scan
  [ "$(grep -c . "${TARGET}")" -gt 100 ]
}

@test "the rendering is hash-pinned" {
  grep -q -- '--hash=sha256:' "${TARGET}"
  grep -q '^ruff==' "${TARGET}"
}

@test "an unknown subcommand exits 2 with usage" {
  run "${SCRIPT}" bogus
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"usage:"* ]]
}

@test "make test depends on the drift check" {
  # Without this the gate exists but nothing runs it, which is the failure mode
  # it was added to prevent one level up.
  local _deps
  _deps="$(grep -E '^test:' "${REPO_ROOT}/Makefile")"
  if [[ "${_deps}" != *"check-requirements-ci"* ]]; then
    printf "make test no longer runs the drift check: %s\n" "${_deps}" >&2
    return 1
  fi
}

@test "CI installs a checksum-verified uv, so the check is not skipped there" {
  # The Makefile guard skips when uv is absent. That is correct locally and
  # would make the gate inert in CI, where it is the real gate.
  local _wf="${REPO_ROOT}/.github/workflows/ci.yml"
  grep -q 'UV_SHA256' "${_wf}"
  grep -q 'sha256sum -c -' "${_wf}"
}

@test "check fails when uv cannot be resolved, distinctly from drift" {
  # cmd_check's third failure path: _render itself fails. Asserts the uv
  # message rather than merely non-zero, because MISSING and DRIFT also
  # exit non-zero and would satisfy a bare status check.
  export UV_BIN="${BATS_TEST_TMPDIR}/no-such-uv"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  if [[ "${output}" != *"UV_BIN is set to"* ]]; then
    printf "did not fail on uv resolution: %s\n" "${output}" >&2
    return 1
  fi
  if [[ "${output}" == *"DRIFT"* || "${output}" == *"MISSING"* ]]; then
    printf "reported drift/missing when the real cause was uv resolution\n" >&2
    return 1
  fi
}

@test "check treats an empty rendering as drift, not as a match" {
  # Boundary: a zero-length target. An implementation comparing only when
  # both sides are non-empty would call this a match.
  : > "${TARGET}"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"DRIFT"* ]]
}
