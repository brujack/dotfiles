#!/usr/bin/env bats
#
# scripts/list-shell-files.sh derives its file set from FIRST-LINE shebang
# content, not from a filename pathspec (see the script's own header
# comment and shell.md's "A git ls-files pathspec cannot express 'every
# tracked shell script'" pitfall). Every fixture here is a real git repo —
# the script's own git calls, including its two `env -u` strips, are
# exercised for real rather than mocked.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/list-shell-files.sh"
  # tests/mocks/git would shadow the real binary this suite needs for real
  # (shell.md PATH-mock shadowing pitfall) -- strip it for every call below.
  CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  # Test isolation (tdd.md pitfall A): start every test from a known-clean
  # ambient state so a leak from whatever invoked bats (e.g. a push from a
  # worktree, per ci.md) can't change what a "no leaked git env" test sees.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

  FIXTURE="${BATS_TEST_TMPDIR}/fixture"
  mkdir -p "${FIXTURE}"
  PATH="${CLEAN_PATH}" git -C "${FIXTURE}" init --quiet
  PATH="${CLEAN_PATH}" git -C "${FIXTURE}" config user.email "test@test.com"
  PATH="${CLEAN_PATH}" git -C "${FIXTURE}" config user.name "Test"
}

# Writes ${FIXTURE}/${1} with exact content ${2} (no implicit newline --
# callers that want one must include it), then stages and commits it.
_commit_file() {
  local _name="$1" _content="$2"
  printf '%s' "${_content}" > "${FIXTURE}/${_name}"
  PATH="${CLEAN_PATH}" git -C "${FIXTURE}" add "${_name}"
  PATH="${CLEAN_PATH}" git -C "${FIXTURE}" commit --quiet -m "add ${_name}"
}

_run_script() {
  run bash -c "cd '${FIXTURE}' && PATH='${CLEAN_PATH}' bash '${SCRIPT}'"
}

@test "includes a file with #!/usr/bin/env bash" {
  _commit_file "a.sh" "#!/usr/bin/env bash
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "a.sh" ]
}

@test "includes a file with #!/bin/bash" {
  _commit_file "a.sh" "#!/bin/bash
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "a.sh" ]
}

@test "includes a file with #!/bin/bash -e" {
  _commit_file "a.sh" "#!/bin/bash -e
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "a.sh" ]
}

@test "includes a file with #!/bin/sh" {
  _commit_file "a.sh" "#!/bin/sh
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "a.sh" ]
}

@test "includes a file with #!/usr/bin/env sh" {
  _commit_file "a.sh" "#!/usr/bin/env sh
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "a.sh" ]
}

@test "excludes a file with #!/usr/bin/env zsh" {
  _commit_file "a.zsh" "#!/usr/bin/env zsh
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "excludes a file with #!/bin/zsh" {
  _commit_file "a.zsh" "#!/bin/zsh
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "excludes a file with #!/usr/bin/zsh -f" {
  _commit_file "a.zsh" "#!/usr/bin/zsh -f
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "excludes a file with #!/usr/bin/env fish" {
  _commit_file "a.fish" "#!/usr/bin/env fish
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "excludes a file with #!/usr/bin/env python3" {
  _commit_file "a.py" "#!/usr/bin/env python3
print('hi')
"
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "excludes a file whose first line is a plain comment, not a shebang" {
  _commit_file "a.sh" "# not a shebang
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "includes a single-line bash shebang file with no trailing newline" {
  _commit_file "a.sh" "#!/usr/bin/env bash"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "a.sh" ]
}

@test "excludes an empty file" {
  _commit_file "a.sh" ""
  _run_script
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "excludes an untracked file even if it carries a bash shebang" {
  # A committed, unrelated file keeps the repo non-empty so this case is
  # distinguished from "the repo has no tracked files at all".
  _commit_file "placeholder.txt" "not a script
"
  printf '#!/usr/bin/env bash\necho hi\n' > "${FIXTURE}/untracked.sh"
  _run_script
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"untracked.sh"* ]]
}

@test "includes an extensionless tracked file with a bash shebang" {
  _commit_file "myscript" "#!/usr/bin/env bash
echo hi
"
  _run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "myscript" ]
}

@test "resolves against the real repo, not a leaked GIT_DIR pointed at a decoy" {
  decoy="${BATS_TEST_TMPDIR}/decoy"
  mkdir -p "${decoy}"
  PATH="${CLEAN_PATH}" git -C "${decoy}" init --quiet
  PATH="${CLEAN_PATH}" git -C "${decoy}" config user.email "test@test.com"
  PATH="${CLEAN_PATH}" git -C "${decoy}" config user.name "Test"
  printf '#!/usr/bin/env bash\necho decoy\n' > "${decoy}/decoy.sh"
  PATH="${CLEAN_PATH}" git -C "${decoy}" add decoy.sh
  PATH="${CLEAN_PATH}" git -C "${decoy}" commit --quiet -m "decoy"

  _commit_file "real.sh" "#!/usr/bin/env bash
echo real
"

  # A leaked GIT_DIR is exactly what the script's own `env -u GIT_DIR ...`
  # prefixes exist to survive (ci.md: git exports GIT_DIR into the pre-push
  # hook when the push originates from a worktree; shell.md: `-C` does not
  # override an exported GIT_DIR). If either prefix is dropped from the
  # script, this resolves against the decoy repo's single decoy.sh instead
  # of the real repo's real.sh.
  run env GIT_DIR="${decoy}/.git" PATH="${CLEAN_PATH}" \
    bash -c "cd '${FIXTURE}' && bash '${SCRIPT}'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "real.sh" ]
}

@test "exits non-zero and emits nothing outside a git repository" {
  local _outside="${BATS_TEST_TMPDIR}/not-a-repo"
  mkdir -p "${_outside}"
  run bash -c "cd '${_outside}' && PATH='${CLEAN_PATH}' bash '${SCRIPT}'"
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

@test "exits non-zero when git ls-files fails after a successful rev-parse" {
  [ "$(id -u)" -ne 0 ] || skip "running as root; chmod 000 does not block access"
  _commit_file "a.sh" "#!/usr/bin/env bash
echo hi
"
  # Positive control, and it is load-bearing: the same invocation must SUCCEED
  # before the index is made unreadable. Without it, the `status -ne 0` below is
  # satisfied just as well by a missing or unrunnable script (exit 127) as by
  # the git ls-files failure it exists to pin. Mutation-confirmed -- pointing
  # SCRIPT at a nonexistent path left this test green while 17 of the other 18
  # went red.
  run bash -c "cd '${FIXTURE}' && PATH='${CLEAN_PATH}' bash '${SCRIPT}'"
  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" | grep -qxF "a.sh"

  chmod 000 "${FIXTURE}/.git/index"
  run bash -c "cd '${FIXTURE}' && PATH='${CLEAN_PATH}' bash '${SCRIPT}'"
  chmod 644 "${FIXTURE}/.git/index"
  [ "${status}" -ne 0 ]
}
