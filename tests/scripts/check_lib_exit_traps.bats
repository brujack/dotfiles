#!/usr/bin/env bats
#
# scripts/check-lib-exit-traps.sh enumerates every `trap ... EXIT` in
# lib/*.sh and ratchets the per-file count against a reasoned allowlist
# embedded in the script. It does NOT infer subshell/brace containment --
# see the script's own header comment and shell.md's "trap ... RETURN is
# not function-scoped" pitfall for why that inference was deliberately left
# out after the run-tmpdir EXIT trap regression (Task 1 on this branch).
#
# Every fixture here drives the _OVERRIDE_LIB_TRAP_SCOPE seam so real lib/
# is never mutated -- the seam points at a fixture root whose own lib/
# subdirectory is globbed exactly like `git ls-files 'lib/*.sh'` would be
# for the real repo, which is what lets a fixture named lib/developer.sh
# land on the real allowlist key without a second seam for the allowlist
# itself.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/check-lib-exit-traps.sh"
  # tests/mocks/git would shadow the real binary the real-lib case needs for
  # real (shell.md PATH-mock shadowing pitfall) -- strip it for every call.
  CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  # Test isolation (tdd.md pitfall A): a leaked GIT_DIR from whatever
  # invoked bats (e.g. a push from a worktree, per ci.md) must not change
  # what the real-lib case resolves as its scope base.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

  FIXTURE="${BATS_TEST_TMPDIR}/fixture"
  mkdir -p "${FIXTURE}/lib"
}

teardown() {
  unset _OVERRIDE_LIB_TRAP_SCOPE
}

_run_script() {
  PATH="${CLEAN_PATH}" run bash "${SCRIPT}"
}

@test "an un-allowlisted function-scope trap is reported, exit 1" {
  cat > "${FIXTURE}/lib/workflows.sh" <<'EOF'
#!/usr/bin/env bash
_run_update() {
  trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
}
EOF
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"lib/workflows.sh 1"* ]]
}

@test "the allowlisted file at its allowlisted count is clean, exit 0" {
  cat > "${FIXTURE}/lib/developer.sh" <<'EOF'
#!/usr/bin/env bash
_aws_verify_zip() {
  (
    trap 'gpgconf --homedir "${_ring}" --kill all >/dev/null 2>&1; rm -rf "${_ring}"' EXIT
  )
}
EOF
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "${status}" -eq 0 ]
}

@test "a trap inside a ( ) subshell is STILL reported -- no containment inference" {
  cat > "${FIXTURE}/lib/other.sh" <<'EOF'
#!/usr/bin/env bash
_something() {
  (
    trap 'cleanup' EXIT
  )
}
EOF
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  # lib/other.sh carries no allowlist entry (expected 0). If a future
  # "improvement" started treating a subshell-contained trap as safe and
  # excluded it from the count, this would read 0, match the expected 0,
  # and the script would report clean -- exactly the regression this test
  # exists to catch.
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"lib/other.sh 1"* ]]
}

@test "a count change in an allowlisted file is reported (allowlisted at 1, fixture has 2)" {
  cat > "${FIXTURE}/lib/developer.sh" <<'EOF'
#!/usr/bin/env bash
_one() {
  (
    trap 'cleanup_one' EXIT
  )
}
_two() {
  (
    trap 'cleanup_two' EXIT
  )
}
EOF
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"lib/developer.sh 2"* ]]
  [[ "${output}" == *"expected 1"* ]]
}

@test "empty scope exits 2, not 1, and says WHICH 2" {
  # Two branches return 2 -- an unresolvable base and an empty derived scope --
  # so `status -eq 2` alone does not pin which one fired. Mutation-confirmed:
  # rewording the empty-scope branch left a status-only assertion green, so it
  # was not pinning that branch at all. Assert the message too.
  rmdir "${FIXTURE}/lib"
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"derived scope is EMPTY"* ]]
}

@test "an unresolvable base exits 2 with its own message, not the empty-scope one" {
  # The other exit-2 branch, which had no test at all. Run with no override from
  # a directory outside any git repo, so `git rev-parse --show-toplevel` fails
  # and the base cannot be resolved. Asserting the two messages are distinct is
  # what stops a future refactor collapsing both branches into one verdict a
  # caller cannot act on.
  local _outside="${BATS_TEST_TMPDIR}/outside"
  mkdir -p "${_outside}"
  unset _OVERRIDE_LIB_TRAP_SCOPE
  run env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    bash -c "cd '${_outside}' && PATH='${CLEAN_PATH}' bash '${SCRIPT}'"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"could not resolve a scope base directory"* ]]
  [[ "${output}" != *"derived scope is EMPTY"* ]]
}

@test "the real lib/ is clean against the real allowlist, exit 0, and scanned a non-empty set" {
  unset _OVERRIDE_LIB_TRAP_SCOPE
  _run_script
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ OK\ \(([0-9]+)\ files ]]
  local _n="${BASH_REMATCH[1]}"
  [ -n "${_n}" ]
  [ "${_n}" -gt 0 ]
}

@test "a trap on signal 0 is counted -- signal 0 IS EXIT" {
  # The regression this ratchet exists to prevent, spelled with the numeric
  # signal instead of the name. Verified independently that `trap 'echo X' 0`
  # fires at exit, so a scanner matching only the word EXIT lets the identical
  # defect through with no allowlist edit and no diff a reviewer would flag.
  printf 'f() {\n  trap %s 0\n}\n' "'unset _X'" > "${FIXTURE}/lib/newthing.sh"
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib/newthing.sh 1"* ]]
}

@test "a trap that is not the first word on its line is counted" {
  # `[[ ... ]] && trap ... EXIT` and `if ...; then trap ... EXIT; fi` are real
  # installs. An earlier revision anchored the match to line start, on a header
  # premise that "a real statement always starts the line with the word trap" --
  # true of today's lib/ and false in general.
  {
    printf 'f() {\n'
    printf '  [[ -n "${d}" ]] && trap %s EXIT\n' "'unset _X'"
    printf '}\n'
  } > "${FIXTURE}/lib/newthing.sh"
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib/newthing.sh 1"* ]]
}

@test "prose about a trap is still not counted" {
  # The counterpart to the two above: widening the match must not start
  # flagging lib/developer.sh's own header comment, which is what the
  # line-start anchor used to buy.
  {
    printf '# The whole body runs in a ( ) subshell with an EXIT trap -- NOT\n'
    printf '#   trap %s 0\n' "'unset _X'"
    printf 'f() { :; }\n'
  } > "${FIXTURE}/lib/newthing.sh"
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "$status" -eq 0 ]
}

@test "make lint actually RUNS the scanner, not just mentions it" {
  # Without this the ratchet can be disabled with no test noticing: the guard
  # predicate was `[ -x ... ]` while the invocation is `bash ...`, so clearing
  # the exec bit sent lint down the skip branch and `make lint` still exited 0.
  #
  # Two ways to write this that do NOT work, both measured:
  #   - `make -n lint` prints the recipe including BOTH branches of the `if`,
  #     so grepping it for the script name passes with the bug present.
  #   - grepping real `make lint` output for "check-lib-exit-traps" also passes,
  #     because the skip message contains that string too.
  # Only the scanner's own success line is unreachable from the skip branch.
  run make --no-print-directory lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-lib-exit-traps: OK"* ]]
}

@test "every allowlist key names a tracked file, by count" {
  # Step 4d: the fixture-driven tests create lib/developer.sh themselves so it
  # lands on the real allowlist key -- which means none of them can detect an
  # entry naming a file that does not exist. The scanner iterates the derived
  # scope and looks entries UP, so a typo'd or retired key is never consulted
  # and never reported: a silent dead entry.
  #
  # Assert a COUNT, not membership. A membership check passes on a partial
  # parse; a count fails when the parse degrades as well as when a key is wrong.
  local _keys _tracked=0 _total=0
  _keys=$(grep -oE '\["lib/[^"]+"\]' "${SCRIPT}" | tr -d '["]' | sort -u)
  [ -n "${_keys}" ]
  while IFS= read -r _k; do
    [[ -n "${_k}" ]] || continue
    _total=$((_total + 1))
    if PATH="${CLEAN_PATH}" env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
         git -C "${REPO_ROOT}" ls-files --error-unmatch "${_k}" >/dev/null 2>&1; then
      _tracked=$((_tracked + 1))
    fi
  done <<< "${_keys}"
  [ "${_total}" -gt 0 ]
  [ "${_tracked}" -eq "${_total}" ]
}
