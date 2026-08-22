#!/usr/bin/env bats

# `run !` (negated run) is a 1.5.0 flag; without this declaration bats emits BW02
# on every invocation. ubuntu-latest ships 1.10.0 via apt and the dev machines
# 1.14.0, so the floor is satisfied everywhere this runs.
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/sync-requirements-ci.sh"
  # Never point at the tracked file: the drift and missing cases mutate it, and
  # a crash between mutating and restoring would leave the repo dirty.
  TARGET="${BATS_TEST_TMPDIR}/requirements-ci.txt"
  export REQUIREMENTS_CI_TARGET="${TARGET}"
  cp "${REPO_ROOT}/requirements-ci.txt" "${TARGET}"
  # Same reasoning for the second rendering. Both seams must be redirected, or a
  # drift case leaves a tracked file modified.
  RUNTIME_TARGET="${BATS_TEST_TMPDIR}/requirements-runtime-ci.txt"
  export REQUIREMENTS_RUNTIME_CI_TARGET="${RUNTIME_TARGET}"
  cp "${REPO_ROOT}/requirements-runtime-ci.txt" "${RUNTIME_TARGET}"
  CI_TEST_TARGET="${BATS_TEST_TMPDIR}/requirements-ci-test.txt"
  export REQUIREMENTS_CI_TEST_TARGET="${CI_TEST_TARGET}"
  cp "${REPO_ROOT}/requirements-ci-test.txt" "${CI_TEST_TARGET}"
  CI_MUTATION_TARGET="${BATS_TEST_TMPDIR}/requirements-ci-mutation.txt"
  export REQUIREMENTS_CI_MUTATION_TARGET="${CI_MUTATION_TARGET}"
  cp "${REPO_ROOT}/requirements-ci-mutation.txt" "${CI_MUTATION_TARGET}"
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

@test "check fails when the RUNTIME rendering has drifted" {
  # The load-bearing case for the two-group loop. Without it the runtime arm
  # could be dead -- never rendered, never compared -- and every other test in
  # this file would still pass, because they all exercise only the test-lint
  # rendering. A loop whose second iteration does nothing is indistinguishable
  # from a correct one unless something drifts exactly there.
  printf 'ansible==0.0.1\n' >> "${RUNTIME_TARGET}"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"DRIFT"* ]]
  [[ "${output}" == *"requirements-runtime-ci.txt"* ]]
}

@test "check fails when the RUNTIME rendering is missing entirely" {
  rm -f "${RUNTIME_TARGET}"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"MISSING"* ]]
  [[ "${output}" == *"requirements-runtime-ci.txt"* ]]
}

@test "check reports BOTH renderings, not just the first to fail" {
  # cmd_check continues past a failure rather than returning early, so a run
  # with two broken renderings names both. Returning on the first would hide
  # the second until someone fixed the first and re-ran.
  printf 'ruff==0.0.1\n'    >> "${TARGET}"
  printf 'ansible==0.0.1\n' >> "${RUNTIME_TARGET}"
  run "${SCRIPT}" check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"requirements-ci.txt"* ]]
  [[ "${output}" == *"requirements-runtime-ci.txt"* ]]
}

@test "the runtime rendering is hash-pinned and carries no machine-specific path" {
  grep -q -- '--hash=sha256:' "${REPO_ROOT}/requirements-runtime-ci.txt"
  run grep -c -E '/Users/|/home/' "${REPO_ROOT}/requirements-runtime-ci.txt"
  [ "${output}" -eq 0 ]
}

@test "the two renderings are different files with different content" {
  # They are deliberately separate: terraform_ansible installs the runtime set
  # and no test tooling, the other three the reverse. This guards against a
  # later "harmonisation" into one file, which would serve terraform_ansible
  # not at all.
  run ! diff -q "${REPO_ROOT}/requirements-ci.txt" \
                "${REPO_ROOT}/requirements-runtime-ci.txt"
  grep -q '^ansible==' "${REPO_ROOT}/requirements-runtime-ci.txt"
  run ! grep -q '^ansible==' "${REPO_ROOT}/requirements-ci.txt"
}

@test "the molecule-plugins[docker] extra is flattened into the runtime rendering" {
  # An extra cannot appear as `pkg[extra]` in a hash-pinned requirements file.
  # uv export resolves it away instead, emitting the extra's dependencies as
  # top-level pins -- so a consumer needs no second, unhashed install line.
  # Measured: [docker] requires docker, requests, selinux.
  local _f="${REPO_ROOT}/requirements-runtime-ci.txt"
  run ! grep -qE '^[A-Za-z0-9._-]+\[' "${_f}"
  for _dep in docker requests selinux; do
    grep -qE "^${_dep}==" "${_f}" || { printf 'missing %s\n' "${_dep}" >&2; return 1; }
  done
}

@test "check fails when the ci-test rendering has drifted" {
  # Third loop iteration. Without this the ci-test arm could be dead and every
  # other case in this file would still pass.
  printf 'ruff==0.0.1\n' >> "${CI_TEST_TARGET}"
  run "${SCRIPT}" check
  [ "$status" -ne 0 ]
  [[ "${output}" == *"requirements-ci-test.txt"* ]]
}

@test "check fails when the ci-mutation rendering has drifted" {
  printf 'cosmic-ray==0.0.1\n' >> "${CI_MUTATION_TARGET}"
  run "${SCRIPT}" check
  [ "$status" -ne 0 ]
  [[ "${output}" == *"requirements-ci-mutation.txt"* ]]
}

@test "ci-test carries none of the mutation whales" {
  # The BOUNDARY guard, and the reason these groups exist at all. ci-test is
  # "what a per-PR test/lint job runs" -- not "where tools go". The predicted
  # failure is that a tool lands in ci-test because that is the convenient
  # group, and in a year ci-test is the union again.
  #
  # These six arrive only through cosmic-ray's closure. A per-PR job that runs
  # a linter has no business installing an ORM, an HTTP client and a git
  # library, so their appearance in ci-test means the boundary has eroded.
  local _f="${REPO_ROOT}/requirements-ci-test.txt"
  for _whale in sqlalchemy aiohttp gitpython yarl frozenlist multidict; do
    if grep -qiE "^${_whale}==" "${_f}"; then
      printf 'ci-test has absorbed %s — the boundary has eroded\n' "${_whale}" >&2
      return 1
    fi
  done
  # positive control: the packages ci-test is FOR must be present, so this
  # cannot pass by the file having moved or emptied
  grep -qE '^ruff==' "${_f}"
  grep -qE '^pytest==' "${_f}"
}

@test "ci-test is materially smaller than the full test-lint rendering" {
  # The whole justification. If these ever converge the split has stopped
  # paying for itself and should be retired rather than maintained.
  local _t _f
  _t=$(grep -cE '^[a-zA-Z0-9._-]+==' "${REPO_ROOT}/requirements-ci-test.txt")
  _f=$(grep -cE '^[a-zA-Z0-9._-]+==' "${REPO_ROOT}/requirements-ci.txt")
  [ "${_t}" -lt "$(( _f / 2 ))" ]
}

@test "all four renderings are distinct files" {
  local _a="${REPO_ROOT}/requirements-ci.txt"
  local _b="${REPO_ROOT}/requirements-runtime-ci.txt"
  local _c="${REPO_ROOT}/requirements-ci-test.txt"
  local _d="${REPO_ROOT}/requirements-ci-mutation.txt"
  run ! diff -q "${_a}" "${_c}"
  run ! diff -q "${_c}" "${_d}"
  run ! diff -q "${_b}" "${_d}"
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
