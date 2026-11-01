#!/usr/bin/env bats
# Shape of the test-shard matrix job and the test gate job in
# .github/workflows/ci.yml (docs/superpowers/specs/2026-10-31-bash-coverage-shard-design.md,
# "CI"). Each job is read as raw text, `run: |` bodies included, so a check of
# what a command line contains sees the command. Nothing here greps the whole
# workflow for a job-specific fact, except where the fact is about the file
# (job absent, `always()` count, SHA pins). WORKFLOW_UNDER_TEST points the
# suite at a broken copy to show an assertion can fail.

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

# _step <id> <name-regex>: the lines of the one step of job <id> whose
# `- name:` matches, up to the next step.
_step() {
  _code "$1" | awk -v pat="$2" '
    /^      - / { if (keep) printf "%s", buf; buf=""; keep=0 }
    { buf = buf $0 "\n" }
    /^      - name:/ && $0 ~ pat { keep=1 }
    END { if (keep) printf "%s", buf }'
}

@test "extractor positive control: shard and gate text are separate and non-empty" {
  local _shard _gate
  _shard="$(_job_text test-shard)"
  _gate="$(_job_text test)"
  [ -n "${_shard}" ]
  [ -n "${_gate}" ]
  [[ "${_shard}" == *"make bash-coverage"* ]]
  [[ "${_shard}" != *"ci-shard-gate.sh"* ]]
  [[ "${_gate}" == *"ci-shard-gate.sh"* ]]
  [[ "${_gate}" != *"make bash-coverage"* ]]
  # The job after the gate (powershell) must not leak into the gate.
  [[ "${_gate}" != *"ubuntu-24.04"* ]]
}

@test "no bash-coverage job exists and test is the gate over test-shard" {
  [ -z "$(_job_text bash-coverage)" ]
  _code test | command grep -qE '^    needs: test-shard$'
  [ "$(_code test | _count 'make test')" -eq 0 ]
}

@test "auto-merge needs lists test and not bash-coverage" {
  local _needs
  _needs="$(_code auto-merge | sed -n 's/^    needs: //p')"
  [ -n "${_needs}" ]
  [[ "${_needs}" == *"test,"* ]]
  [[ "${_needs}" != *"bash-coverage"* ]]
  [[ "${_needs}" == *"test-macos"* ]]
}

@test "the shard matrix is [1, 2, 3] with fail-fast false on ubuntu-latest, 30 minutes, contents read" {
  local _t
  _t="$(_code test-shard)"
  [ "$(printf '%s\n' "${_t}" | _count '^      fail-fast: false$')" -eq 1 ]
  [ "$(printf '%s\n' "${_t}" | _count '^        shard: \[1, 2, 3\]$')" -eq 1 ]
  printf '%s\n' "${_t}" | command grep -qE '^    runs-on: ubuntu-latest$'
  printf '%s\n' "${_t}" | command grep -qE '^    timeout-minutes: 30$'
  printf '%s\n' "${_t}" | command grep -qE '^      contents: read$'
}

@test "bats-shard.sh is called once, from matrix.shard and strategy.job-total" {
  local _t
  _t="$(_code test-shard)"
  [ "$(printf '%s\n' "${_t}" | _count 'bats-shard\.sh')" -eq 1 ]
  printf '%s\n' "${_t}" | command grep -qF 'bash scripts/bats-shard.sh "${{ matrix.shard }}" "${{ strategy.job-total }}" > "shard-${{ matrix.shard }}.files"'
}

@test "make test-prereqs runs once, on shard 1 only" {
  local _t
  _t="$(_code test-shard)"
  [ "$(printf '%s\n' "${_t}" | _count 'make test-prereqs')" -eq 1 ]
  # Same step guards it on the shard number.
  _step test-shard 'prereq' | command grep -qE 'matrix\.shard \}\}" = "1"|matrix\.shard == 1'
}

@test "BATS_FILES_FROM and COVERAGE_TRACE_DIR are step env entries and never on a command line" {
  local _t _other
  _t="$(_code test-shard)"
  printf '%s\n' "${_t}" | command grep -qE '^          BATS_FILES_FROM: shard-\$\{\{ matrix\.shard \}\}\.files$'
  printf '%s\n' "${_t}" | command grep -qE '^          COVERAGE_TRACE_DIR: shard-out$'
  _other="$(printf '%s\n' "${_t}" | command grep -E 'BATS_FILES_FROM|COVERAGE_TRACE_DIR' | command grep -vE '^          (BATS_FILES_FROM|COVERAGE_TRACE_DIR): ' || true)"
  [ -z "${_other}" ]
  # Control: the make line is present, so the absence above is not vacuous.
  [ "$(printf '%s\n' "${_t}" | _count 'make bash-coverage')" -eq 1 ]
}

@test "the suite report has no if, reads the trace dir's log and the same list" {
  local _s
  _s="$(_step test-shard 'suite|report|executed')"
  [ -n "${_s}" ]
  # Whole line, so a trailing `|| true` cannot neutralise the check.
  printf '%s\n' "${_s}" | command grep -qxF '        run: bash scripts/ci-suite-report.sh shard-out/bats_run.log --files "shard-${{ matrix.shard }}.files"'
  if printf '%s' "${_s}" | command grep -qE '^ *(- )?if:'; then return 1; fi
  # The log path is the COVERAGE_TRACE_DIR value the coverage step writes to.
  [ "$(_code test-shard | _count '^          COVERAGE_TRACE_DIR: shard-out$')" -eq 1 ]
}

@test "the list-and-trace upload is success-only, attempt-scoped and errors on a missing file" {
  local _block
  _block="$(_code test-shard | awk '
    /^      - / { if (keep) printf "%s", buf; buf=""; keep=0 }
    { buf = buf $0 "\n" }
    /name: test-shard-\$\{\{ github\.run_attempt \}\}-\$\{\{ matrix\.shard \}\}$/ { keep=1 }
    END { if (keep) printf "%s", buf }')"
  [ -n "${_block}" ]
  [[ "${_block}" == *"actions/upload-artifact@"* ]]
  [[ "${_block}" == *"if-no-files-found: error"* ]]
  if printf '%s' "${_block}" | command grep -qE '^ *(- )?if:'; then return 1; fi
  # Both the list and the trace are staged and uploaded.
  [ "$(_code test-shard | _count 'shard-\$\{\{ matrix\.shard \}\}\.trace')" -ge 1 ]
}

@test "the failure log upload keeps the full log with overwrite" {
  local _block
  _block="$(_code test-shard | awk '
    /^      - / { if (keep) printf "%s", buf; buf=""; keep=0 }
    { buf = buf $0 "\n" }
    /name: test-shard-log-\$\{\{ matrix\.shard \}\}$/ { keep=1 }
    END { if (keep) printf "%s", buf }')"
  [ -n "${_block}" ]
  [[ "${_block}" == *"if: failure() || cancelled()"* ]]
  [[ "${_block}" == *"path: shard-out/bats_run.log"* ]]
  [[ "${_block}" == *"overwrite: true"* ]]
}

@test "the gate is if always(), fails unless the shard result is success, 10 minutes" {
  _job_text test | command grep -qE '^    if: always\(\)[[:space:]]*$'
  local _req
  _req="$(_step test 'Require every shard')"
  [ -n "${_req}" ]
  printf '%s\n' "${_req}" | command grep -qxF '          [ "${{ needs.test-shard.result }}" = "success" ] || exit 1'
  # No early success path before or after the comparison.
  if printf '%s\n' "${_req}" | command grep -qE 'exit 0|\|\| true|&& exit'; then return 1; fi
  _code test | command grep -qE '^    timeout-minutes: 10$'
  _code test | command grep -qE '^    runs-on: ubuntu-latest$'
}

@test "always() occurs exactly twice outside comments: the if of test-macos and of test" {
  local _n
  _n="$(sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "${WF}" | _count 'always\(\)')"
  [ "${_n}" -eq 2 ]
}

@test "the gate downloads this attempt's artifacts into cov-shards, merged, and runs the gate then the score" {
  local _t
  _t="$(_code test)"
  [ "$(printf '%s\n' "${_t}" | _count 'download-artifact@')" -eq 1 ]
  printf '%s\n' "${_t}" | command grep -qE '^          pattern: test-shard-\$\{\{ github\.run_attempt \}\}-\*$'
  printf '%s\n' "${_t}" | command grep -qE '^          merge-multiple: true$'
  printf '%s\n' "${_t}" | command grep -qE '^          path: cov-shards$'
  printf '%s\n' "${_t}" | command grep -qF 'bash scripts/ci-shard-gate.sh --with-traces cov-shards'
  printf '%s\n' "${_t}" | command grep -qF 'bash scripts/run-bash-coverage.sh --score cov-shards/shard-*.trace'
}

@test "no job under test sets continue-on-error" {
  [ -n "$(_code test-shard)" ]
  [ -n "$(_code test)" ]
  if _code test-shard | command grep -q 'continue-on-error'; then return 1; fi
  if _code test | command grep -q 'continue-on-error'; then return 1; fi
}

@test "the score step fails on a scoring error and on a missing percentage" {
  local _s
  _s="$(_step test 'Score the union')"
  [ -n "${_s}" ]
  printf '%s\n' "${_s}" | command grep -qxF '          bash scripts/run-bash-coverage.sh --score cov-shards/shard-*.trace > /tmp/bash-cov-out.txt 2>&1 || { cat /tmp/bash-cov-out.txt; exit 1; }'
  printf '%s\n' "${_s}" | command grep -qxF '          if [ -z "${PCT}" ]; then'
  printf '%s\n' "${_s}" | command grep -qxF '            printf "FAIL: coverage output not found\n" >&2'
  printf '%s\n' "${_s}" | command grep -qxF '            exit 1'
  printf '%s\n' "${_s}" | command grep -qxF '          if [ "${PCT}" -lt 91 ]; then'
  if printf '%s\n' "${_s}" | command grep -qE '\|\| true'; then return 1; fi
}

@test "the gate enforces the 91 floor and publishes the badge" {
  local _t
  _t="$(_code test)"
  printf '%s\n' "${_t}" | command grep -qF -- '-lt 91'
  printf '%s\n' "${_t}" | command grep -qF 'bash.json'
  printf '%s\n' "${_t}" | command grep -qF '"label":"bash coverage"'
}

@test "the test gate has contents: write and no shard or macOS job does" {
  local _j
  _code test | command grep -qE '^      contents: write$'
  for _j in test-shard test-macos-shard test-macos lint-macos secret-scan; do
    if _code "${_j}" | command grep -qE '^      contents: write$'; then return 1; fi
  done
}

@test "every uses: line in both jobs is pinned to a full commit SHA, with a floor" {
  local _job _uses _n=0 _line
  for _job in test-shard test; do
    _uses="$(_code "${_job}" | command grep -E '^ *(- )?uses:' || true)"
    [ -n "${_uses}" ]
    while IFS= read -r _line; do
      [[ "${_line}" =~ @[0-9a-f]{40}$ ]] || { printf 'unpinned: %s\n' "${_line}" >&2; return 1; }
      _n=$((_n + 1))
    done <<< "${_uses}"
  done
  # shard: checkout + 2 uploads; gate: checkout + download.
  [ "${_n}" -ge 5 ]
}

@test "the shard job installs pinned shellcheck and uv with checksum checks" {
  local _t
  _t="$(_code test-shard)"
  printf '%s\n' "${_t}" | command grep -qE 'SC_SHA256: "[0-9a-f]{64}"'
  printf '%s\n' "${_t}" | command grep -qE 'UV_SHA256: "[0-9a-f]{64}"'
  [ "$(printf '%s\n' "${_t}" | _count 'sha256sum -c -')" -ge 2 ]
  printf '%s\n' "${_t}" | command grep -qF 'apt-get install -y bats zsh parallel'
}
