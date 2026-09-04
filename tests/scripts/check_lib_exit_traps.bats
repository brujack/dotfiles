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

@test "empty scope exits 2, not 1" {
  rmdir "${FIXTURE}/lib"
  export _OVERRIDE_LIB_TRAP_SCOPE="${FIXTURE}"
  _run_script
  [ "${status}" -eq 2 ]
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
