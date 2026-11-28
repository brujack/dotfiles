#!/usr/bin/env bats
# Wiring of scripts/root-writes.sh into the test-shard and test-macos-shard
# jobs of .github/workflows/ci.yml (docs/superpowers/specs/2026-11-27-root-writes-scan-design.md
# R9, R10, N5). Each job is parsed on its own, comments stripped; nothing here
# greps the whole workflow for a job-specific fact. WORKFLOW_UNDER_TEST points
# the suite at a broken copy to show an assertion can fail.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${WORKFLOW_UNDER_TEST:-${REPO_ROOT}/.github/workflows/ci.yml}"
}

# _job_text <id>: the raw lines of one top-level job.
_job_text() {
  awk -v want="$1" '
    /^[^ #]/ { job=""; next }
    /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { job=$1; sub(/:$/, "", job); if (job == want) print; next }
    job == want { print }
  ' "${WF}"
}

# _code <id>: the job text without full-line and trailing comments.
_code() {
  _job_text "$1" | sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//'
}

# _step <id> <name-regex>: the lines of the one step whose `- name:` matches.
_step() {
  _code "$1" | awk -v pat="$2" '
    /^      - / { if (keep) printf "%s", buf; buf=""; keep=0 }
    { buf = buf $0 "\n" }
    /^      - name:/ && $0 ~ pat { keep=1 }
    END { if (keep) printf "%s", buf }'
}

# _line_of <pattern>: line number of the first match on stdin, empty if none.
_line_of() { awk -v pat="$1" '$0 ~ pat { print NR; exit }'; }

@test "extractor positive control: both jobs and their steps are found" {
  [ -n "$(_step test-shard 'Run traced suite')" ]
  [ -n "$(_step test-macos-shard 'Run tests')" ]
  [[ "$(_step test-shard 'Run traced suite')" != *"ci-suite-report"* ]]
}

@test "test-shard marks before the shard-1 prerequisites step" {
  local _t _mark _prereq
  _t="$(_code test-shard)"
  _mark="$(printf '%s\n' "${_t}" | _line_of '^      - name: Mark root-writes window$')"
  _prereq="$(printf '%s\n' "${_t}" | _line_of '^      - name: Run test prerequisites [(]shard 1 only[)]$')"
  [ -n "${_mark}" ]
  [ -n "${_prereq}" ]
  [ "${_mark}" -lt "${_prereq}" ]
  [ -z "$(_step test-shard 'Mark root-writes window' | command grep -E '^        if:' || true)" ]
  _step test-shard 'Mark root-writes window' |
    command grep -qF 'bash scripts/root-writes.sh mark "${RUNNER_TEMP}/root-writes.marker"'
}

@test "test-shard suite step keeps its env and runs check after make bash-coverage with no exit between" {
  local _s _make _check _exit
  _s="$(_step test-shard 'Run traced suite')"
  printf '%s\n' "${_s}" | command grep -qE '^          BATS_FILES_FROM: shard-\$\{\{ matrix.shard \}\}.files$'
  printf '%s\n' "${_s}" | command grep -qE '^          COVERAGE_TRACE_DIR: shard-out$'
  printf '%s\n' "${_s}" | command grep -qE '^          set \+e$'
  _make="$(printf '%s\n' "${_s}" | _line_of 'make bash-coverage < /dev/null')"
  _check="$(printf '%s\n' "${_s}" | _line_of 'bash scripts/root-writes.sh check "[$][{]RUNNER_TEMP[}]/root-writes.marker"')"
  [ -n "${_make}" ]
  [ -n "${_check}" ]
  [ "${_make}" -lt "${_check}" ]
  # No exit between make and check.
  [ -z "$(printf '%s\n' "${_s}" | sed -n "${_make},${_check}p" | command grep -E '\bexit\b' || true)" ]
  printf '%s\n' "${_s}" | sed -n "${_make},${_check}p" | command grep -qE '^          rc=\$\?$'
  printf '%s\n' "${_s}" | command grep -qE '^          check_rc=\$\?$'
}

@test "test-shard suite step final exit can come from check_rc" {
  local _s
  _s="$(_step test-shard 'Run traced suite')"
  printf '%s\n' "${_s}" | command grep -qE 'exit "\$\{rc\}"'
  printf '%s\n' "${_s}" | command grep -qE '^          exit "\$\{check_rc\}"$'
  # The make status is not the unconditional last word.
  [ -z "$(printf '%s\n' "${_s}" | command grep -E '^          exit "\$\{rc\}"$' || true)" ]
}

@test "test-shard report step is unchanged" {
  _step test-shard 'Check executed tests equal declared' |
    command grep -qF 'bash scripts/ci-suite-report.sh shard-out/bats_run.log --files "shard-${{ matrix.shard }}.files"'
}

@test "test-macos-shard runs mark before make" {
  local _s _mark _make
  _s="$(_step test-macos-shard 'Run tests')"
  _mark="$(printf '%s\n' "${_s}" | _line_of 'bash scripts/root-writes.sh mark "[$][{]RUNNER_TEMP[}]/root-writes.marker"')"
  _make="$(printf '%s\n' "${_s}" | _line_of 'make test( |-bats )')"
  [ -n "${_mark}" ]
  [ -n "${_make}" ]
  [ "${_mark}" -lt "${_make}" ]
}

@test "test-macos-shard runs check after the report with no exit between make and check" {
  local _s _make _report _check
  _s="$(_step test-macos-shard 'Run tests')"
  _make="$(printf '%s\n' "${_s}" | _line_of 'make test-bats ')"
  _report="$(printf '%s\n' "${_s}" | _line_of 'ci-suite-report.sh /tmp/make-test.log')"
  _check="$(printf '%s\n' "${_s}" | _line_of 'bash scripts/root-writes.sh check "[$][{]RUNNER_TEMP[}]/root-writes.marker"')"
  [ -n "${_make}" ]
  [ -n "${_report}" ]
  [ -n "${_check}" ]
  [ "${_make}" -lt "${_report}" ]
  [ "${_report}" -lt "${_check}" ]
  [ -z "$(printf '%s\n' "${_s}" | sed -n "${_make},${_check}p" | command grep -E '\bexit\b' || true)" ]
}

@test "test-macos-shard keeps the make failure handling" {
  local _s
  _s="$(_step test-macos-shard 'Run tests')"
  printf '%s\n' "${_s}" | command grep -qF "printf 'make exited %d\\n' \"\${rc}\" >&2"
  printf '%s\n' "${_s}" | command grep -qF 'tail -40 /tmp/make-test.log'
}

@test "test-macos-shard still exits with the report status when make passed and the report failed" {
  local _s _after
  _s="$(_step test-macos-shard 'Run tests')"
  printf '%s\n' "${_s}" | command grep -qE '^          check_rc=\$\?$'
  # A report failure must reach an exit, and must not be dropped in favour of check_rc.
  printf '%s\n' "${_s}" | command grep -qE 'report_rc' 
  _after="$(printf '%s\n' "${_s}" | awk '/check_rc=[$][?]/ { f=1; next } f')"
  [[ "${_after}" == *'"${report_rc}"'* ]]
  [[ "${_after}" == *'"${check_rc}"'* ]]
  # The report status is tested before check_rc is the fallback.
  [ "$(printf '%s\n' "${_after}" | _line_of 'report_rc')" -lt "$(printf '%s\n' "${_after}" | _line_of 'exit "[$][{]check_rc[}]"')" ]
}

@test "test-shard set +e comes before make bash-coverage" {
  local _s
  _s="$(_step test-shard 'Run traced suite')"
  [ -n "$(printf '%s\n' "${_s}" | _line_of '^          set [+]e$')" ]
  [ "$(printf '%s\n' "${_s}" | _line_of '^          set [+]e$')" -lt "$(printf '%s\n' "${_s}" | _line_of 'make bash-coverage < /dev/null')" ]
}

@test "test-macos-shard set +e comes before mark and make" {
  local _s _set
  _s="$(_step test-macos-shard 'Run tests')"
  _set="$(printf '%s\n' "${_s}" | _line_of '^          set [+]e$')"
  [ -n "${_set}" ]
  [ "${_set}" -lt "$(printf '%s\n' "${_s}" | _line_of 'root-writes.sh mark')" ]
  [ "${_set}" -lt "$(printf '%s\n' "${_s}" | _line_of 'make test( |-bats )')" ]
}

@test "test-macos-shard mark is unconditional: it precedes the shard if" {
  local _s _mark _if
  _s="$(_step test-macos-shard 'Run tests')"
  _mark="$(printf '%s\n' "${_s}" | _line_of 'root-writes.sh mark')"
  _if="$(printf '%s\n' "${_s}" | _line_of '^          if [[] "[$][{][{] matrix.shard [}][}]" = "1" []]; then$')"
  [ -n "${_mark}" ]
  [ -n "${_if}" ]
  [ "${_mark}" -lt "${_if}" ]
}

@test "the final exit check_rc is reachable: no top-level exit after make precedes it" {
  local _job _s
  for _job in "test-shard|Run traced suite|make bash-coverage" "test-macos-shard|Run tests|make test-bats "; do
    _s="$(_step "${_job%%|*}" "$(printf '%s' "${_job}" | cut -d'|' -f2)")"
    # Lines after the make line, up to the final exit, at the step's own indent.
    run bash -c 'printf "%s\n" "$1" | awk -v pat="$2" "
      index(\$0, pat) { f=1; next }
      f && /^          exit / && !/check_rc/ { bad=1 }
      f && /^          exit .*check_rc/ { found=1; exit }
      END { exit (found && !bad) ? 0 : 1 }"' _ "${_s}" "${_job##*|}"
    [ "${status}" -eq 0 ]
  done
}

# Homebrew Python writes stdlib bytecode under /opt/homebrew/Cellar the first
# time the suite imports a module (rollout runs 46103860810 and 46107517429, every
# test-macos-shard). PYTHONPYCACHEPREFIX cannot stop it: the suite's `python3 -I`
# callers ignore every PYTHON* variable. Compiling the stdlib before the window
# opens leaves Python nothing to write; /opt/homebrew stays unpruned.
@test "test-macos-shard precompiles the Homebrew Python stdlib in a step before Run tests" {
  local _t _pre _run
  _t="$(_code test-macos-shard)"
  _pre="$(printf '%s\n' "${_t}" | _line_of '^      - name: Precompile Homebrew Python stdlib$')"
  _run="$(printf '%s\n' "${_t}" | _line_of '^      - name: Run tests$')"
  [ -n "${_pre}" ]
  [ -n "${_run}" ]
  [ "${_pre}" -lt "${_run}" ]
  _step test-macos-shard 'Precompile Homebrew Python stdlib' |
    command grep -qF 'python3 -m compileall -q -j 0 -x /test/ "$(python3 -c '"'"'import sysconfig; print(sysconfig.get_path("stdlib"))'"'"')"'
  [ -z "$(_step test-macos-shard 'Precompile Homebrew Python stdlib' | command grep -E '^        if:' || true)" ]
}

@test "no shard step sets PYTHONPYCACHEPREFIX" {
  [ -z "$(_code test-shard | command grep PYTHONPYCACHEPREFIX || true)" ]
  [ -z "$(_code test-macos-shard | command grep PYTHONPYCACHEPREFIX || true)" ]
}
