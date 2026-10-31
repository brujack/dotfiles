#!/usr/bin/env bats
#
# scripts/bats-shard.sh packs every .bats file into N shards by CPU weight
# (tests/bats-weights.tsv), heaviest first, onto the lightest shard. Fixture
# trees live in tests/fixtures/bats-shard/ as *.bats.fixture so the real suite
# and the real `find` never see them; each test copies one into a scratch
# tests/ directory as *.bats and runs the script from there.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # SCRIPT_UNDER_TEST lets a mutation run point this suite at a scratch copy.
  SCRIPT="${SCRIPT_UNDER_TEST:-${REPO_ROOT}/scripts/bats-shard.sh}"
  FIXTURES="${REPO_ROOT}/tests/fixtures/bats-shard"
  WORK="${BATS_TEST_TMPDIR}/work"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  unset BATS_WEIGHTS BATS_SHARD_HANDICAP
  mkdir -p "${WORK}/tests"
}

# stage_fixture <name>: copy fixtures/<name>/*.bats.fixture into WORK/tests/ as *.bats.
stage_fixture() {
  local _src _base
  for _src in "${FIXTURES}/$1"/*.bats.fixture; do
    _base="$(basename "${_src}" .fixture)"
    cp "${_src}" "${WORK}/tests/${_base}" || return 1
  done
}

# shard <i> <n>: run the script from WORK (the script runs `find tests`).
shard() {
  run --separate-stderr bash -c 'cd "$1" && shift && bash "$@"' _ "${WORK}" "${SCRIPT}" "$@"
}

@test "real tree: shards for N in 1..4 are non-empty, disjoint and cover every .bats file" {
  local _n _i _all _got
  _all="$(cd "${REPO_ROOT}" && find tests -name '*.bats' | LC_ALL=C sort)"
  [ "$(printf '%s\n' "${_all}" | wc -l)" -gt 80 ]
  for _n in 1 2 3 4; do
    _got=""
    for _i in $(seq 1 "${_n}"); do
      run --separate-stderr bash -c 'cd "$1" && shift && bash "$@"' _ "${REPO_ROOT}" "${SCRIPT}" "${_i}" "${_n}"
      [ "${status}" -eq 0 ]
      [ -n "${output}" ]
      _got+="${output}"$'\n'
    done
    # sort -u equal to sort means no file appeared twice; equality with _all means full cover.
    [ "$(printf '%s' "${_got}" | LC_ALL=C sort)" = "${_all}" ]
  done
}

@test "golden: tied weights, handicap 0 gives exact shards" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=0
  shard 1 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/a.bats\ntests/c.bats\ntests/f.bats' ]
  shard 2 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/b.bats\ntests/d.bats\ntests/e.bats' ]
}

@test "golden: a non-zero handicap changes the exact shards" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=7
  shard 1 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/b.bats\ntests/d.bats\ntests/f.bats' ]
  shard 2 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/a.bats\ntests/c.bats\ntests/e.bats' ]
}

@test "default handicap is 40: shard 1 of 2 gets only the lightest file" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv"
  shard 1 2
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  # 40 outweighs every file, so shard 2 takes a,b,c,d,e before shard 1 gets f.
  [ "${output}" = "tests/f.bats" ]
}

@test "weights by CPU seconds beat count-packing on the real tree" {
  local _i _cpu_max=0 _cnt_max=0 _w
  local _counts="${BATS_TEST_TMPDIR}/counts.tsv"
  local _table="${REPO_ROOT}/tests/bats-weights.tsv"
  (cd "${REPO_ROOT}" && find tests -name '*.bats' | LC_ALL=C sort | while IFS= read -r _f; do
    printf '%s\t%s\n' "${_f}" "$(command grep -c '^@test' "${_f}")"
  done) > "${_counts}"
  export BATS_SHARD_HANDICAP=0
  for _i in 1 2 3; do
    BATS_WEIGHTS="${_table}" run bash -c 'cd "$1" && bash "$2" "$3" 3' _ "${REPO_ROOT}" "${SCRIPT}" "${_i}"
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    _w="$(printf '%s\n' "${output}" | awk -F'\t' 'NR==FNR{if($0!~/^#/)w[$1]=$2;next}{s+=w[$0]}END{print s+0}' "${_table}" -)"
    awk -v a="${_w}" -v b="${_cpu_max}" 'BEGIN{exit !(a>b)}' && _cpu_max="${_w}"
    BATS_WEIGHTS="${_counts}" run bash -c 'cd "$1" && bash "$2" "$3" 3' _ "${REPO_ROOT}" "${SCRIPT}" "${_i}"
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    _w="$(printf '%s\n' "${output}" | awk -F'\t' 'NR==FNR{if($0!~/^#/)w[$1]=$2;next}{s+=w[$0]}END{print s+0}' "${_table}" -)"
    awk -v a="${_w}" -v b="${_cnt_max}" 'BEGIN{exit !(a>b)}' && _cnt_max="${_w}"
  done
  # Both heaviest shards scored in CPU seconds with the committed table.
  awk -v a="${_cpu_max}" 'BEGIN{exit !(a>0)}'
  awk -v a="${_cpu_max}" -v b="${_cnt_max}" 'BEGIN{exit !(a<b)}'
}

@test "a file with no table row weighs its @test count times CPU seconds per test" {
  stage_fixture fallback
  export BATS_WEIGHTS="${FIXTURES}/fallback/weights.tsv" BATS_SHARD_HANDICAP=0
  # new.bats = 3 tests * 5 s = 15 s, heavier than a or b (10 s), so it takes shard 1 alone.
  shard 1 2
  [ "${status}" -eq 0 ]
  [ "${output}" = "tests/new.bats" ]
  shard 2 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/a.bats\ntests/b.bats' ]
}

@test "a dead row is named on stderr and changes neither output nor exit" {
  stage_fixture dead
  export BATS_SHARD_HANDICAP=0
  local _clean="${BATS_TEST_TMPDIR}/clean.tsv"
  command grep -v gone "${FIXTURES}/dead/weights.tsv" > "${_clean}"
  BATS_WEIGHTS="${_clean}" shard 1 2
  local _status_clean="${status}" _out_clean="${output}"
  [ "${_status_clean}" -eq 0 ]
  [ -n "${_out_clean}" ]
  [ -z "${stderr}" ]
  BATS_WEIGHTS="${FIXTURES}/dead/weights.tsv" shard 1 2
  [ "${status}" -eq "${_status_clean}" ]
  [ "${output}" = "${_out_clean}" ]
  [ "${stderr}" = "bats-shard: dead row: tests/gone.bats" ]
}

@test "bad arguments exit 2 with empty stdout and a message on stderr" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv"
  local _args
  for _args in "0 3" "4 3" "x 3" "1 0" "1 x" "1" "" "1 2 3"; do
    # shellcheck disable=SC2086 # word splitting of the argument pair is the point
    shard ${_args}
    [ "${status}" -eq 2 ]
    [ -z "${output}" ]
    [ -n "${stderr}" ]
  done
}

@test "a non-numeric handicap exits 2 with empty stdout" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=abc
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [ -n "${stderr}" ]
}

@test "an unreadable weights file exits 2 with empty stdout" {
  stage_fixture golden
  export BATS_WEIGHTS="${BATS_TEST_TMPDIR}/does-not-exist.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [ -n "${stderr}" ]
}

@test "a table with no live rows exits 2 with empty stdout" {
  stage_fixture golden
  printf '# only dead rows\ntests/gone.bats\t5\n' > "${BATS_TEST_TMPDIR}/dead-only.tsv"
  export BATS_WEIGHTS="${BATS_TEST_TMPDIR}/dead-only.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [ -n "${stderr}" ]
}

@test "live rows whose files hold no @test exit 2 with empty stdout" {
  printf '# no tests here\n' > "${WORK}/tests/empty.bats"
  printf 'tests/empty.bats\t5\n' > "${BATS_TEST_TMPDIR}/zero.tsv"
  export BATS_WEIGHTS="${BATS_TEST_TMPDIR}/zero.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [ -n "${stderr}" ]
}

@test "a malformed table line exits 2 with empty stdout" {
  stage_fixture golden
  local _bad
  for _bad in 'tests/a.bats\tabc' 'tests/a.bats' 'tests/a.bats\t-3' 'tests/a.bats\t1\t2'; do
    { printf '# header\n'; printf "${_bad}\n"; printf 'tests/b.bats\t4\n'; } > "${BATS_TEST_TMPDIR}/bad.tsv"
    BATS_WEIGHTS="${BATS_TEST_TMPDIR}/bad.tsv" shard 1 2
    [ "${status}" -eq 2 ]
    [ -z "${output}" ]
    [ -n "${stderr}" ]
  done
}

@test "an empty tree exits 2 with empty stdout" {
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [ -n "${stderr}" ]
}

@test "the committed weights table is a commented, C-sorted list of numeric rows" {
  local _table="${REPO_ROOT}/tests/bats-weights.tsv" _rows
  [[ "$(head -n 1 "${_table}")" == "# CPU s"* ]]
  _rows="$(command grep -v '^#' "${_table}")"
  [ -n "${_rows}" ]
  [ "$(printf '%s\n' "${_rows}" | wc -l)" -gt 80 ]
  [ "${_rows}" = "$(printf '%s\n' "${_rows}" | LC_ALL=C sort)" ]
  # Every row is <tests/...bats> TAB <non-negative number>.
  ! printf '%s\n' "${_rows}" | command grep -qvE '^tests/[^	]+\.bats	[0-9]+(\.[0-9]+)?$'
}
