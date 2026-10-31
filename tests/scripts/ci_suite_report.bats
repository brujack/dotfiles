#!/usr/bin/env bats
#
# scripts/ci-suite-report.sh is the macOS CI job's receipt: it prints every
# failing test with its diagnostics and fails when the number of tests that
# ran differs from the number declared, so a suite that silently stopped
# early cannot pass. Tests run the script through its command line only.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # SCRIPT_UNDER_TEST lets a mutation run point this suite at a scratch copy.
  SCRIPT="${SCRIPT_UNDER_TEST:-${REPO_ROOT}/scripts/ci-suite-report.sh}"
  TESTS_DIR="${BATS_TEST_TMPDIR}/tests"
  LOG="${BATS_TEST_TMPDIR}/make-test.log"
  mkdir -p "${TESTS_DIR}/sub"
  # Three declared tests across two files. The non-bats file carries a string
  # containing "@test" that must not be counted (anchoring).
  printf '@test "one" {\n  true\n}\n@test "two" {\n  true\n}\n' > "${TESTS_DIR}/a.bats"
  printf '@test "three" {\n  true\n}\n' > "${TESTS_DIR}/sub/b.bats"
  printf 'mail test@test.com @test not a test\n@test "x" {\n' > "${TESTS_DIR}/notes.txt"
  printf '  @test "indented" {\nfoo @test "midline" {\n' >> "${TESTS_DIR}/sub/b.bats"
}

@test "equal executed and declared counts exit 0 and print both" {
  printf 'ok 1 one\nok 2 two\nok 3 three\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"executed=3 declared=3"* ]]
}

@test "a not ok line is printed with the diagnostic lines that follow it" {
  printf 'ok 1 one\n# diag after ok\nnot ok 2 two\n# (in test file x, line 3)\n#   detail here\nok 3 three\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  # Counts are equal: this script reports, make's own status fails the job.
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"not ok 2 two"* ]]
  [[ "${output}" == *"# (in test file x, line 3)"* ]]
  [[ "${output}" == *"#   detail here"* ]]
  [[ "${output}" != *"ok 3 three"* ]]
  [[ "${output}" != *"diag after ok"* ]]
}

@test "zero executed tests exits 1 and names both counts" {
  printf 'make: *** [test] Error 2\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executed=0 declared=3"* ]]
}

@test "executed fewer than declared exits 1" {
  printf 'ok 1 one\nok 2 two\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executed=2 declared=3"* ]]
}

@test "an empty tests dir exits 1 and names declared=0" {
  rm -rf "${TESTS_DIR}"
  mkdir -p "${TESTS_DIR}"
  : > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executed=0 declared=0"* ]]
}

@test "lint output lines that merely contain OK are not counted as tests" {
  printf 'bash -n OK (111 files)\nOK\nlint ok 12 files\n  ok 13 indented\nok 1 one\nok 2 two\nok 3 three\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"executed=3 declared=3"* ]]
}

@test "a skipped test line counts as executed" {
  printf 'ok 1 one\nok 2 two\nok 3 three # skip needs GNU ar\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"executed=3 declared=3"* ]]
}

@test "a missing log file exits 2 and names the file" {
  run bash "${SCRIPT}" "${BATS_TEST_TMPDIR}/nope.log" "${TESTS_DIR}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"nope.log"* ]]
}

@test "a missing tests dir exits 2 and names the dir" {
  printf 'ok 1 one\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${BATS_TEST_TMPDIR}/no-such-dir"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"no-such-dir"* ]]
}

@test "more executed than declared exits 1" {
  printf 'ok 1 one\nok 2 two\nok 3 three\nok 4 four\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" "${TESTS_DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executed=4 declared=3"* ]]
}

@test "a directory passed as the log exits 2" {
  run bash "${SCRIPT}" "${TESTS_DIR}" "${TESTS_DIR}"
  [ "${status}" -eq 2 ]
}

# --files mode: declared count comes from an explicit shard list, not a dir walk.
# The fixture list names a.bats (2 tests) and sub/b.bats (1 test); notes.txt and
# an unlisted c.bats (5 tests) must not count.

make_files_list() {
  LIST="${BATS_TEST_TMPDIR}/shard.files"
  printf '@test "c1" {\n}\n@test "c2" {\n}\n@test "c3" {\n}\n@test "c4" {\n}\n@test "c5" {\n}\n' > "${TESTS_DIR}/c.bats"
  printf '%s\n%s\n' "${TESTS_DIR}/a.bats" "${TESTS_DIR}/sub/b.bats" > "${LIST}"
}

@test "--files: executed equal to declared over the list exits 0" {
  make_files_list
  printf 'ok 1 one\nok 2 two\nok 3 three\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${LIST}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"executed=3 declared=3"* ]]
}

@test "--files: one short of the list exits 1 and names both counts" {
  make_files_list
  printf 'ok 1 one\nok 2 two\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${LIST}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executed=2 declared=3"* ]]
}

@test "--files: an empty list exits 1 with declared=0" {
  make_files_list
  : > "${LIST}"
  printf 'ok 1 one\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${LIST}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executed=1 declared=0"* ]]
}

@test "--files: an unreadable list file exits 2 and names it" {
  printf 'ok 1 one\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${BATS_TEST_TMPDIR}/no-such.files"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"no-such.files"* ]]
}

@test "--files: an unreadable listed path exits 2 and names it" {
  make_files_list
  printf '%s\n' "${TESTS_DIR}/ghost.bats" >> "${LIST}"
  printf 'ok 1 one\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${LIST}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ghost.bats"* ]]
}

@test "--files: a blank line in the list exits 2" {
  make_files_list
  printf '\n%s\n' "${TESTS_DIR}/a.bats" > "${LIST}"
  printf 'ok 1 one\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${LIST}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"blank line"* ]]
}

@test "--files: a listed file with no tests contributes 0" {
  make_files_list
  : > "${TESTS_DIR}/empty.bats"
  printf '%s\n' "${TESTS_DIR}/empty.bats" >> "${LIST}"
  printf 'ok 1 one\nok 2 two\nok 3 three\n' > "${LOG}"
  run bash "${SCRIPT}" "${LOG}" --files "${LIST}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"executed=3 declared=3"* ]]
}

@test "--files: a missing log exits 2 and names it" {
  make_files_list
  run bash "${SCRIPT}" "${BATS_TEST_TMPDIR}/nope.log" --files "${LIST}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"nope.log"* ]]
}
