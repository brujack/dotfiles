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
    # Sorted concatenation equal to the full list means every file appeared exactly once.
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

@test "default handicap is 40, not 39 or 41" {
  stage_fixture bracket
  export BATS_WEIGHTS="${FIXTURES}/bracket/weights.tsv"
  shard 1 2
  [ "${status}" -eq 0 ]
  [ "${output}" = "tests/z.bats" ]
  BATS_SHARD_HANDICAP=39 shard 1 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/y.bats\ntests/z.bats' ]
  BATS_SHARD_HANDICAP=41 shard 1 2
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

# score_shard <table> <counts>: stdin is a shard list; prints its CPU weight. A file
# with no table row weighs its @test count times the live rows' CPU s per test
# (dead rows, absent from the counts, are excluded),
# the packer's own fallback, so a missing row is not scored as free.
score_shard() {
  awk -F'\t' '
    FILENAME == ARGV[1] { if ($0 !~ /^#/) row[$1] = $2; next }
    FILENAME == ARGV[2] { cnt[$1] = $2; next }
    FNR == 1 && !rated { for (f in row) if (f in cnt) { c += cnt[f]; t += row[f] } rate = t / c; rated = 1 }
    { s += ($0 in row) ? row[$0] : cnt[$0] * rate }
    END { print s + 0 }
  ' "$1" "$2" -
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
    BATS_WEIGHTS="${_table}" run --separate-stderr bash -c 'cd "$1" && bash "$2" "$3" 3' _ "${REPO_ROOT}" "${SCRIPT}" "${_i}"
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    [ -z "${stderr}" ]
    _w="$(printf '%s\n' "${output}" | score_shard "${_table}" "${_counts}")"
    awk -v a="${_w}" -v b="${_cpu_max}" 'BEGIN{exit !(a>b)}' && _cpu_max="${_w}"
    BATS_WEIGHTS="${_counts}" run --separate-stderr bash -c 'cd "$1" && bash "$2" "$3" 3' _ "${REPO_ROOT}" "${SCRIPT}" "${_i}"
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    [ -z "${stderr}" ]
    _w="$(printf '%s\n' "${output}" | score_shard "${_table}" "${_counts}")"
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

@test "a dead row's weight never enters the fallback rate" {
  stage_fixture fallback-dead
  export BATS_WEIGHTS="${FIXTURES}/fallback-dead/weights.tsv" BATS_SHARD_HANDICAP=0
  # Live rows: a, b = 10 s over 4 tests -> 5 s per test; new (1 test) weighs 5 s,
  # lighter than a or b. Counting gone.bats (100 s) would make it 30 s and heaviest.
  shard 1 2
  [ "${status}" -eq 0 ]
  [ "${output}" = $'tests/a.bats\ntests/new.bats' ]
  shard 2 2
  [ "${status}" -eq 0 ]
  [ "${output}" = "tests/b.bats" ]
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
    [[ "${stderr}" == "bats-shard: "* ]]
  done
}

@test "a non-numeric handicap exits 2 with empty stdout" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=abc
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: "* ]]
}

@test "an unreadable weights file exits 2 with empty stdout" {
  stage_fixture golden
  export BATS_WEIGHTS="${BATS_TEST_TMPDIR}/does-not-exist.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: "* ]]
}

@test "a table with no live rows exits 2 with empty stdout" {
  stage_fixture golden
  printf '# only dead rows\ntests/gone.bats\t5\n' > "${BATS_TEST_TMPDIR}/dead-only.tsv"
  export BATS_WEIGHTS="${BATS_TEST_TMPDIR}/dead-only.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *"no live rows"* ]]
}

@test "live rows whose files hold no @test exit 2 with empty stdout" {
  printf '# no tests here\n' > "${WORK}/tests/empty.bats"
  printf 'tests/empty.bats\t5\n' > "${BATS_TEST_TMPDIR}/zero.tsv"
  export BATS_WEIGHTS="${BATS_TEST_TMPDIR}/zero.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: "* ]]
}

@test "a malformed table line exits 2 with empty stdout" {
  stage_fixture golden
  local _bad
  for _bad in 'tests/a.bats\tabc' 'tests/a.bats' 'tests/a.bats\t-3' 'tests/a.bats\t1\t2' \
    'tests/a.bats\t5\r' 'tests/a.bats\t1.' '' 'tests/a.bats\t5\ntests/a.bats\t6'; do
    { printf '# header\n'; printf "${_bad}\n"; printf 'tests/b.bats\t4\n'; } > "${BATS_TEST_TMPDIR}/bad.tsv"
    BATS_WEIGHTS="${BATS_TEST_TMPDIR}/bad.tsv" shard 1 2
    [ "${status}" -eq 2 ]
    [ -z "${output}" ]
    [[ "${stderr}" == "bats-shard: "* ]]
  done
}

@test "a CRLF table line is reported as CRLF and names the table" {
  stage_fixture golden
  printf 'tests/a.bats\t5\r\n' > "${BATS_TEST_TMPDIR}/crlf.tsv"
  BATS_WEIGHTS="${BATS_TEST_TMPDIR}/crlf.tsv" shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: "*"CRLF"* ]]
  [[ "${stderr}" == *"${BATS_TEST_TMPDIR}/crlf.tsv"* ]]
}

@test "a duplicate table row exits 2 and names the row" {
  stage_fixture golden
  printf 'tests/a.bats\t5\ntests/a.bats\t6\n' > "${BATS_TEST_TMPDIR}/dup.tsv"
  BATS_WEIGHTS="${BATS_TEST_TMPDIR}/dup.tsv" shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: "*"duplicate"*"tests/a.bats"* ]]
}

@test "leading-zero arguments mean the same shard as plain ones" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=0
  shard 1 2
  local _plain="${output}"
  [ -n "${_plain}" ]
  shard 01 02
  [ "${status}" -eq 0 ]
  [ "${output}" = "${_plain}" ]
}

@test "leading zeros are decimal: 08 of 09 is shard 8, and 09 of 08 is out of range" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=0
  shard 8 9
  local _plain="${output}"
  [ "${status}" -eq 0 ]
  shard 08 09
  [ "${status}" -eq 0 ]
  [ "${output}" = "${_plain}" ]
  shard 09 08
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: index must be within 1..count"* ]]
}

@test "a zero-byte .bats file with a table row lands in exactly one shard, no dead row" {
  stage_fixture zero
  export BATS_WEIGHTS="${FIXTURES}/zero/weights.tsv" BATS_SHARD_HANDICAP=0
  shard 1 2
  [ "${status}" -eq 0 ]
  [ -z "${stderr}" ]
  local _s1="${output}"
  shard 2 2
  [ "${status}" -eq 0 ]
  [ -z "${stderr}" ]
  [ "$(printf '%s\n%s\n' "${_s1}" "${output}" | command grep -c '^tests/z.bats$')" -eq 1 ]
  [ "$(printf '%s\n%s\n' "${_s1}" "${output}" | command grep -c '^tests/a.bats$')" -eq 1 ]
}

@test "an empty shard prints no bytes and exits 0" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv" BATS_SHARD_HANDICAP=0
  # Six files over eight shards: shard 8 is empty.
  run bash -c 'cd "$1" && bash "$2" 8 8 > "$3"' _ "${WORK}" "${SCRIPT}" "${BATS_TEST_TMPDIR}/out"
  [ "${status}" -eq 0 ]
  [ -f "${BATS_TEST_TMPDIR}/out" ]
  [ ! -s "${BATS_TEST_TMPDIR}/out" ]
}

@test "a find error exits 2 with empty stdout even when find printed files" {
  stage_fixture golden
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv"
  mkdir "${WORK}/tests/locked"
  chmod 000 "${WORK}/tests/locked"
  shard 1 2
  chmod 755 "${WORK}/tests/locked"
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *"bats-shard: "* ]]
}

@test "an empty tree exits 2 with empty stdout" {
  export BATS_WEIGHTS="${FIXTURES}/golden/weights.tsv"
  shard 1 2
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
  [[ "${stderr}" == "bats-shard: no .bats files under tests/" ]]
}

@test "the committed weights table is a commented, C-sorted list of numeric rows" {
  local _table="${REPO_ROOT}/tests/bats-weights.tsv" _rows
  [[ "$(head -n 1 "${_table}")" == "# CPU s"* ]]
  _rows="$(command grep -v '^#' "${_table}")"
  [ -n "${_rows}" ]
  [ "$(printf '%s\n' "${_rows}" | wc -l)" -gt 80 ]
  [ "${_rows}" = "$(printf '%s\n' "${_rows}" | LC_ALL=C sort)" ]
  # No path appears twice.
  [ -z "$(printf '%s\n' "${_rows}" | cut -f1 | LC_ALL=C sort | uniq -d)" ]
  # Every row is <tests/...bats> TAB <non-negative number>.
  ! printf '%s\n' "${_rows}" | command grep -qvE '^tests/[^	]+\.bats	[0-9]+(\.[0-9]+)?$'
}
