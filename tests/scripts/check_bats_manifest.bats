#!/usr/bin/env bats
#
# Tests for scripts/check-bats-manifest.sh. The CI suite gates take their file
# set from the same filesystem walk as the shard lists, so deleting a .bats
# file shrinks both sides and every check passes. tests/bats-files.txt is the
# anchor independent of that walk: the tracked .bats files must equal it.
#
# Each case builds its own git repository under BATS_TEST_TMPDIR and points the
# script at it; one case runs against this repository's committed manifest.

bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/check-bats-manifest.sh"
  export HOME="${BATS_TEST_TMPDIR}"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  R="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${R}/tests/sub" "${R}/tests/helpers"
  git -C "${R}" init -q
  : >"${R}/tests/a.bats"
  : >"${R}/tests/sub/b.bats"
  : >"${R}/tests/helpers/common.bash"
  git -C "${R}" add tests
  git -C "${R}" -c user.name=t -c user.email=t@t commit -q -m init
  M="${R}/tests/bats-files.txt"
  printf 'tests/a.bats\ntests/sub/b.bats\n' >"${M}"
}

@test "the tracked .bats files equal the manifest" {
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 0 ]
  [ "$output" = "bats manifest: 2 files match tests/bats-files.txt" ]
}

@test "a deleted file still listed fails and is named" {
  git -C "${R}" rm -q tests/sub/b.bats
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"listed in tests/bats-files.txt but not tracked: tests/sub/b.bats"* ]]
  [[ "$output" != *"match"* ]]
}

@test "a new tracked file not listed fails and is named" {
  : >"${R}/tests/c.bats"
  git -C "${R}" add tests/c.bats
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tracked but not listed in tests/bats-files.txt: tests/c.bats"* ]]
}

@test "an untracked .bats file on disk does not count" {
  : >"${R}/tests/scratch.bats"
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 0 ]
}

@test "the failure names the command that regenerates the manifest" {
  git -C "${R}" rm -q tests/sub/b.bats
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git ls-files '*.bats' | LC_ALL=C sort > tests/bats-files.txt"* ]]
}

@test "an unsorted manifest fails" {
  printf 'tests/sub/b.bats\ntests/a.bats\n' >"${M}"
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tests/bats-files.txt is not sorted (LC_ALL=C)"* ]]
}

@test "a duplicate line fails" {
  printf 'tests/a.bats\ntests/a.bats\ntests/sub/b.bats\n' >"${M}"
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate in tests/bats-files.txt: tests/a.bats"* ]]
}

@test "a missing or empty manifest is an input error" {
  rm -f "${M}"
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read tests/bats-files.txt"* ]]
  : >"${M}"
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/bats-files.txt is empty"* ]]
}

@test "a directory that is not a git repository is an input error" {
  mkdir -p "${BATS_TEST_TMPDIR}/plain/tests"
  printf 'tests/a.bats\n' >"${BATS_TEST_TMPDIR}/plain/tests/bats-files.txt"
  run "${SCRIPT}" "${BATS_TEST_TMPDIR}/plain"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git ls-files failed"* ]]
}

@test "an exported GIT_DIR naming another repository is ignored" {
  # git -C does not override GIT_DIR (shell-007): without the strip the script
  # would list the other repository's files.
  local other="${BATS_TEST_TMPDIR}/other"
  git init -q "${other}"
  export GIT_DIR="${other}/.git"
  run "${SCRIPT}" "${R}"
  [ "$status" -eq 0 ]
  [ "$output" = "bats manifest: 2 files match tests/bats-files.txt" ]
}

@test "this repository's committed manifest matches its tracked .bats files" {
  # Production path: no argument, the script's own repository.
  run "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == "bats manifest: "*" files match tests/bats-files.txt" ]]
}
