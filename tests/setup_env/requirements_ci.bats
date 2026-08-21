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

@test "every CI job that runs the suite installs a checksum-verified uv" {
  # Asserts PER JOB, not per file. The original grepped the whole workflow for
  # UV_SHA256 and passed on presence anywhere — which it had, in the `test` job
  # only, while `bash-coverage` ran the same suite without uv and 4 tests failed
  # there. An assertion satisfied by a different job than the one under test is
  # the same cause-isolation defect as an assertion satisfied by a different
  # code path.
  local _wf="${REPO_ROOT}/.github/workflows/ci.yml"
  local _bad
  # `working-directory:` is load-bearing, not defensive: the powershell job runs
  # `make test` under working-directory: powershell, which is Pester against
  # powershell/Makefile, not the root suite. Counting it would make this fire on
  # correct state, and a check that fires on correct state gets ignored.
  _bad="$(awk '
    /^  [a-z-]+:$/       { job=$1; sub(/:$/,"",job); has_uv[job]=0; runs[job]=0 }
    /^      - name:/     { wd=0 }
    /working-directory:/ { wd=1 }
    /Install uv \(pinned\)/            { has_uv[job]=1 }
    /make test|make bash-coverage/     { if (!wd) runs[job]=1 }
    END { for (j in runs) if (runs[j] && !has_uv[j]) print j }
  ' "${_wf}")"
  if [[ -n "${_bad}" ]]; then
    printf "job(s) run the suite without installing uv: %s\n" "${_bad}" >&2
    return 1
  fi
  # positive control: the scan must actually have found jobs that run the suite
  local _n
  _n="$(awk '
    /^  [a-z-]+:$/       { job=$1 }
    /^      - name:/     { wd=0 }
    /working-directory:/ { wd=1 }
    /make test|make bash-coverage/ { if (!wd) print job }
  ' "${_wf}" | sort -u | wc -l | tr -d " ")"
  [ "${_n}" -ge 2 ]
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
