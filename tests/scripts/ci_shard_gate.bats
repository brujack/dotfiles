#!/usr/bin/env bats
#
# scripts/ci-shard-gate.sh is the aggregation gate for the sharded macOS job:
# it checks the shards' file lists against an independent find (coverage,
# equality) and against each other (disjointness). Tests run it through its
# command line only; fixture trees live in BATS_TEST_TMPDIR.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # SCRIPT_UNDER_TEST lets a mutation run point this suite at a scratch copy.
  SCRIPT="${SCRIPT_UNDER_TEST:-${REPO_ROOT}/scripts/ci-shard-gate.sh}"
  TREE="${BATS_TEST_TMPDIR}/tree"
  LISTS="${TREE}/lists"
  mkdir -p "${TREE}/tests/sub" "${LISTS}"
  printf '@test "a" {\n  true\n}\n' > "${TREE}/tests/a.bats"
  printf '@test "b" {\n  true\n}\n' > "${TREE}/tests/sub/b.bats"
  printf '@test "c" {\n  true\n}\n' > "${TREE}/tests/c.bats"
  printf 'not a bats file\n' > "${TREE}/tests/notes.txt"
}

# Run the gate with cwd at <dir>; remaining arguments go to the gate.
run_gate_in() {
  local _cwd="$1"
  shift
  run bash -c 'cd "$1" && shift && bash "$@"' _ "${_cwd}" "${SCRIPT}" "$@"
}

good_partition() {
  printf 'tests/a.bats\ntests/sub/b.bats\n' > "${LISTS}/shard-1.files"
  printf 'tests/c.bats\n' > "${LISTS}/shard-2.files"
}

@test "correct fixture partition passes and prints a summary with counts" {
  good_partition
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PASS"* ]]
  [[ "${output}" == *"3 files"* ]]
  [[ "${output}" == *"2 lists"* ]]
}

@test "a file missing from every list fails coverage and names it" {
  printf 'tests/a.bats\n' > "${LISTS}/shard-1.files"
  printf 'tests/c.bats\n' > "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"coverage:"* ]]
  [[ "${output}" == *"missing: tests/sub/b.bats"* ]]
  [[ "${output}" != *"disjointness:"* ]]
}

@test "a path the find does not list fails coverage as extra" {
  good_partition
  printf 'tests/ghost.bats\n' >> "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"coverage:"* ]]
  [[ "${output}" == *"extra: tests/ghost.bats"* ]]
}

@test "a blank line fails coverage as an extra entry" {
  good_partition
  printf '\n' >> "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"coverage:"* ]]
  [[ "${output}" == *"extra: "* ]]
}

@test "a path split at a space fails coverage" {
  printf 'tests/a.bats\ntests/sub/b.bats\n' > "${LISTS}/shard-1.files"
  printf 'tests/c.bats extra\n' > "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"missing: tests/c.bats"* ]]
  [[ "${output}" == *"extra: tests/c.bats extra"* ]]
}

@test "a file in two lists fails disjointness and names it" {
  good_partition
  printf 'tests/a.bats\n' >> "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"disjointness:"* ]]
  [[ "${output}" == *"duplicate: tests/a.bats"* ]]
  [[ "${output}" != *"coverage:"* ]]
}

@test "both failing checks are reported before exiting" {
  printf 'tests/a.bats\ntests/a.bats\n' > "${LISTS}/shard-1.files"
  printf 'tests/c.bats\n' > "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"coverage:"* ]]
  [[ "${output}" == *"missing: tests/sub/b.bats"* ]]
  [[ "${output}" == *"disjointness:"* ]]
  [[ "${output}" == *"duplicate: tests/a.bats"* ]]
}

@test "a carriage return in a list is a usage error naming file and line" {
  good_partition
  printf 'tests/c.bats\r\n' > "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ci-shard-gate:"* ]]
  [[ "${output}" == *"shard-2.files"* ]]
  [[ "${output}" == *"line 1"* ]]
}

@test "a missing directory exits 2 with the prefixed message" {
  run_gate_in "${TREE}" no-such-dir
  [ "${status}" -eq 2 ]
  [[ "${output}" == "ci-shard-gate: "* ]]
}

@test "a directory with no shard-*.files exits 2" {
  printf 'tests/a.bats\n' > "${LISTS}/other.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == "ci-shard-gate: "* ]]
}

@test "no argument exits 2 with a usage message" {
  run_gate_in "${TREE}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == "ci-shard-gate: usage"* ]]
}

@test "an unreadable list exits 2" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  good_partition
  chmod 000 "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"cannot read"* ]]
}

@test "a tree with no tests directory exits 2 because find fails" {
  good_partition
  rm -rf "${TREE}/tests"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"find"* ]]
}

@test "real 3-shard output written by bats-shard.sh passes" {
  local _i
  for _i in 1 2 3; do
    bash "${REPO_ROOT}/scripts/bats-shard.sh" "${_i}" 3 > "${LISTS}/shard-${_i}.files"
    [ -s "${LISTS}/shard-${_i}.files" ]
  done
  run_gate_in "${REPO_ROOT}" "${LISTS}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PASS"* ]]
}

@test "dropping one line from the real 3-shard output fails coverage naming it" {
  local _i _dropped
  for _i in 1 2 3; do
    bash "${REPO_ROOT}/scripts/bats-shard.sh" "${_i}" 3 > "${LISTS}/shard-${_i}.files"
  done
  _dropped="$(sed -n '1p' "${LISTS}/shard-2.files")"
  [ -n "${_dropped}" ]
  sed -i '1d' "${LISTS}/shard-2.files"
  run_gate_in "${REPO_ROOT}" "${LISTS}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"coverage:"* ]]
  [[ "${output}" == *"missing: ${_dropped}"* ]]
}

@test "a dangling symlink list exits 2 as unreadable instead of being ignored" {
  good_partition
  ln -s "${TREE}/nowhere" "${LISTS}/shard-3.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"cannot read list file"* ]]
  [[ "${output}" == *"shard-3.files"* ]]
}

@test "a list that is a directory exits 2" {
  good_partition
  mkdir "${LISTS}/shard-3.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"cannot read list file"* ]]
}

@test "a tree with no .bats files exits 2 with the prefixed message" {
  good_partition
  rm -f "${TREE}/tests/a.bats" "${TREE}/tests/c.bats" "${TREE}/tests/sub/b.bats"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 2 ]
  [[ "${output}" == "ci-shard-gate: "* ]]
  [[ "${output}" == *"no .bats files"* ]]
}

@test "a list with no trailing newline still passes" {
  printf 'tests/a.bats\ntests/sub/b.bats' > "${LISTS}/shard-1.files"
  printf 'tests/c.bats' > "${LISTS}/shard-2.files"
  run_gate_in "${TREE}" lists
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PASS"* ]]
  [[ "${output}" == *"3 files"* ]]
}
