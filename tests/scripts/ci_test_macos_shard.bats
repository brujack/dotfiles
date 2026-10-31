#!/usr/bin/env bats
# Shape of the test-macos-shard matrix job and the test-macos gate job in
# .github/workflows/ci.yml (docs/superpowers/specs/2026-10-30-test-macos-shard-design.md,
# "CI"). Each job is read as raw text, `run: |` bodies included, so a check of
# what a command line contains sees the command. Nothing here greps the whole
# workflow for a job-specific fact.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${WORKFLOW_UNDER_TEST:-${REPO_ROOT}/.github/workflows/ci.yml}"
}

# _job_text <id>: the raw lines of one top-level job, from its two-space
# header to the line before the next job header (or the next top-level key).
_job_text() {
  awk -v want="$1" '
    /^[^ #]/ { job=""; next }
    /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { job=$1; sub(/:$/, "", job); if (job == want) print; next }
    job == want { print }
  ' "${WF}"
}

# _code <id>: the job text without full-line comments and trailing comments.
_code() {
  _job_text "$1" | sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//'
}

_count() { command grep -c -E -- "$1" || true; }

@test "extractor positive control: the shard job's make test line is inside a run body, no neighbour leaks" {
  local _shard _gate
  _shard="$(_job_text test-macos-shard)"
  _gate="$(_job_text test-macos)"
  [ -n "${_shard}" ]
  [ -n "${_gate}" ]
  [[ "${_shard}" == *"make test"* ]]
  [[ "${_shard}" == *"runs-on: macos-latest"* ]]
  # The gate is the next job: its lines must not appear in the shard text.
  [[ "${_shard}" != *"ci-shard-gate.sh"* ]]
  [[ "${_gate}" != *"make test"* ]]
  [[ "${_gate}" == *"runs-on: ubuntu-latest"* ]]
  # And the job after the gate must not leak into the gate.
  [[ "${_gate}" != *"ubuntu-24.04"* ]]
}

@test "always() occurs once outside comments: the if of job test-macos" {
  local _n
  _n="$(sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "${WF}" | _count 'always\(\)')"
  [ "${_n}" -eq 1 ]
  _job_text test-macos | command grep -qE '^    if: always\(\)[[:space:]]*$'
  _code test-macos | command grep -q 'needs.test-macos-shard.result'
  # The printf alone names the result; the comparison is what fails the job.
  _code test-macos | command grep -qF '[ "${{ needs.test-macos-shard.result }}" = "success" ] || exit 1'
}

@test "the gate needs test-macos-shard and runs on ubuntu-latest with a 10 minute timeout" {
  _code test-macos | command grep -qE '^    needs: test-macos-shard$'
  _code test-macos | command grep -qE '^    runs-on: ubuntu-latest$'
  _code test-macos | command grep -qE '^    timeout-minutes: 10$'
}

@test "the shard matrix is [1, 2, 3] with fail-fast false" {
  local _t
  _t="$(_code test-macos-shard)"
  [ "$(printf '%s\n' "${_t}" | _count '^      fail-fast: false$')" -eq 1 ]
  [ "$(printf '%s\n' "${_t}" | _count '^        shard: \[1, 2, 3\]$')" -eq 1 ]
  printf '%s\n' "${_t}" | command grep -qE '^    timeout-minutes: 30$'
}

@test "bats-shard.sh is called once, from matrix.shard and strategy.job-total" {
  local _t
  _t="$(_code test-macos-shard)"
  [ "$(printf '%s\n' "${_t}" | _count 'bats-shard\.sh')" -eq 1 ]
  printf '%s\n' "${_t}" | command grep -qF 'bash scripts/bats-shard.sh "${{ matrix.shard }}" "${{ strategy.job-total }}" > "shard-${{ matrix.shard }}.files"'
}

@test "BATS_FILES_FROM is a step env entry and never on a make command line" {
  local _t
  _t="$(_code test-macos-shard)"
  [ "$(printf '%s\n' "${_t}" | _count 'BATS_FILES_FROM')" -ge 1 ]
  printf '%s\n' "${_t}" | command grep -qE '^          BATS_FILES_FROM: shard-\$\{\{ matrix\.shard \}\}\.files$'
  # Any line naming BATS_FILES_FROM must be that env entry.
  local _other
  _other="$(printf '%s\n' "${_t}" | command grep 'BATS_FILES_FROM' | command grep -vE '^          BATS_FILES_FROM: ' || true)"
  [ -z "${_other}" ]
  # Control: the make lines are present, so the absence above is not vacuous.
  [ "$(printf '%s\n' "${_t}" | _count 'make test')" -ge 1 ]
  [ "$(printf '%s\n' "${_t}" | _count 'make test-bats')" -ge 1 ]
}

@test "the report is scoped to the shard's own list" {
  _code test-macos-shard | command grep -qF 'bash scripts/ci-suite-report.sh /tmp/make-test.log --files "shard-${{ matrix.shard }}.files"'
}

@test "the list upload has no if, a run_attempt name and errors on a missing file" {
  local _block
  _block="$(_code test-macos-shard | awk '
    /^      - / { if (keep) print buf; buf=""; keep=0 }
    { buf = buf $0 "\n" }
    /name: test-macos-shard-\$\{\{ github\.run_attempt \}\}-/ { keep=1 }
    END { if (keep) printf "%s", buf }')"
  [ -n "${_block}" ]
  [[ "${_block}" == *"actions/upload-artifact@"* ]]
  [[ "${_block}" == *"if-no-files-found: error"* ]]
  [[ "${_block}" == *"matrix.shard"* ]]
  # No step-level if: (a two-space-deeper "if:" under a step is the 8-space key).
  ! printf '%s' "${_block}" | command grep -qE '^ *(- )?if:'
}

@test "the download pattern carries run_attempt, merges, and lands where the gate reads" {
  local _t
  _t="$(_code test-macos)"
  [ "$(printf '%s\n' "${_t}" | _count 'download-artifact@')" -eq 1 ]
  printf '%s\n' "${_t}" | command grep -qE '^          pattern: test-macos-shard-\$\{\{ github\.run_attempt \}\}-\*$'
  printf '%s\n' "${_t}" | command grep -qE '^          merge-multiple: true$'
  local _path _gate_dir
  _path="$(printf '%s\n' "${_t}" | sed -n 's/^          path: //p')"
  _gate_dir="$(printf '%s\n' "${_t}" | sed -n 's/.*ci-shard-gate\.sh[[:space:]]*//p')"
  [ -n "${_path}" ]
  [ "${_path}" = "${_gate_dir}" ]
}

@test "every uses: line in both jobs is pinned to a full commit SHA" {
  local _job _uses _n=0 _line
  for _job in test-macos-shard test-macos; do
    _uses="$(_code "${_job}" | command grep -E '^ *(- )?uses:' || true)"
    [ -n "${_uses}" ]
    while IFS= read -r _line; do
      [[ "${_line}" =~ @[0-9a-f]{40}$ ]] || { printf 'unpinned: %s\n' "${_line}" >&2; return 1; }
      _n=$((_n + 1))
    done <<< "${_uses}"
  done
  # checkout + upload x2 in the shard job, checkout + download in the gate.
  [ "${_n}" -ge 5 ]
}
