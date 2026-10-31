#!/usr/bin/env bash
# Print the .bats files one CI shard runs, packed by CPU weight.
#
# Usage: bats-shard.sh <index> <count>      (index is 1-based)
#
# Environment:
#   BATS_WEIGHTS         weights table, default tests/bats-weights.tsv
#   BATS_SHARD_HANDICAP  CPU seconds shard 1 starts with, default 40 (it also
#                        runs the `make test` prerequisites)
#
# Every `find tests -name '*.bats'` file is weighted from the table (a file
# with no row weighs its @test count times the table's CPU seconds per test),
# visited heaviest first (ties by path) and given to the lightest shard (ties
# by lowest index). Run from the repo root. Every error prints a message on
# stderr, nothing on stdout, and exits 2.

readonly _SHARD_DEFAULT_HANDICAP=40

shard_die() {
  printf 'bats-shard: %s\n' "$1" >&2
  return 2
}

# The packing itself. Input files: the weights table, then every .bats file.
# Prints the selected shard's paths in path order, or a message on stderr and
# exit 2 from awk.
shard_pack() {
  local _weights="$1" _index="$2" _count="$3" _handicap="$4"
  shift 4
  # LC_ALL=C: string comparison (path ties, dead-row order) and decimal parsing
  # must not depend on the caller's locale. ARGV is the weights table then every
  # .bats path, so a zero-byte file (no records) is still a file.
  LC_ALL=C awk -F'\t' -v idx="${_index}" -v n="${_count}" -v hc="${_handicap}" '
    function fail(msg) { printf "bats-shard: %s\n", msg > "/dev/stderr"; failed = 1; exit 2 }
    BEGIN {
      wfile = ARGV[1]
      for (i = 2; i < ARGC; i++) { nfiles++; path[nfiles] = ARGV[i]; known[ARGV[i]] = 1 }
    }
    FILENAME == wfile {
      if ($0 ~ /^#/) next
      if ($0 ~ /\r$/) fail(wfile ": line " FNR " is a CRLF line")
      if (NF != 2 || $2 !~ /^[0-9]+(\.[0-9]+)?$/) fail(wfile ": malformed line " FNR ": " $0)
      if ($1 in row) fail(wfile ": duplicate row at line " FNR ": " $1)
      row[$1] = $2 + 0
      next
    }
    /^@test/ { tests[FILENAME]++ }
    END {
      if (failed) exit 2
      live = 0; cpu = 0; cnt = 0
      for (r in row) {
        if (r in known) { live++; cpu += row[r]; cnt += tests[r] + 0 }
        else dead[++nd] = r
      }
      # Name dead rows in path order so stderr is deterministic.
      for (a = 2; a <= nd; a++) { v = dead[a]; b = a - 1; while (b >= 1 && dead[b] > v) { dead[b + 1] = dead[b]; b-- } dead[b + 1] = v }
      for (a = 1; a <= nd; a++) printf "bats-shard: dead row: %s\n", dead[a] > "/dev/stderr"
      if (live == 0) fail(wfile ": no live rows")
      if (cnt == 0) fail(wfile ": live rows hold no @test lines")
      per = cpu / cnt
      for (i = 1; i <= nfiles; i++) w[i] = (path[i] in row) ? row[path[i]] : (tests[path[i]] + 0) * per
      # Order: heaviest first, ties by path ascending (insertion sort; ~90 files).
      for (i = 1; i <= nfiles; i++) ord[i] = i
      for (i = 2; i <= nfiles; i++) {
        v = ord[i]; j = i - 1
        while (j >= 1 && (w[ord[j]] < w[v] || (w[ord[j]] == w[v] && path[ord[j]] > path[v]))) { ord[j + 1] = ord[j]; j-- }
        ord[j + 1] = v
      }
      for (s = 1; s <= n; s++) load[s] = 0
      load[1] = hc + 0
      for (i = 1; i <= nfiles; i++) {
        f = ord[i]; best = 1
        for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
        load[best] += w[f]; owner[f] = best
      }
      for (i = 1; i <= nfiles; i++) if (owner[i] == idx + 0) print path[i]
    }
  ' "${_weights}" "$@" || return 1
}

main() {
  local _index="${1:-}" _count="${2:-}" _weights _handicap _found _files _out _rc
  if [[ $# -ne 2 ]]; then
    shard_die "usage: bats-shard.sh <index> <count>" || return 2
  fi
  if [[ ! "${_index}" =~ ^[0-9]+$ || ! "${_count}" =~ ^[0-9]+$ ]]; then
    shard_die "index and count must be integers: '${_index}' '${_count}'" || return 2
  fi
  if (( 10#${_count} < 1 || 10#${_index} < 1 || 10#${_index} > 10#${_count} )); then
    shard_die "index must be within 1..count: '${_index}' of '${_count}'" || return 2
  fi
  _weights="${BATS_WEIGHTS:-tests/bats-weights.tsv}"
  _handicap="${BATS_SHARD_HANDICAP:-${_SHARD_DEFAULT_HANDICAP}}"
  if [[ ! "${_handicap}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    shard_die "BATS_SHARD_HANDICAP must be a non-negative number: '${_handicap}'" || return 2
  fi
  if [[ ! -f "${_weights}" || ! -r "${_weights}" ]]; then
    shard_die "weights file unreadable: ${_weights}" || return 2
  fi
  # find's own status is checked: a pipeline would report sort's.
  _found="$(find tests -name '*.bats')" || {
    shard_die "find tests failed" || return 2
  }
  _files="$(printf '%s\n' "${_found}" | LC_ALL=C sort)"
  if [[ -z "${_found}" ]]; then
    shard_die "no .bats files under tests/" || return 2
  fi
  # One path per line, split on newline only; set -f stops a glob character in a
  # path expanding. Paths with a newline are not supported.
  # shellcheck disable=SC2086 # deliberate newline word-splitting with globbing off
  _out="$(set -f; IFS=$'\n'; shard_pack "${_weights}" "$((10#${_index}))" "$((10#${_count}))" "${_handicap}" ${_files})"
  _rc=$?
  if [[ ${_rc} -ne 0 ]]; then
    return 2
  fi
  # An empty shard prints nothing; make refuses the empty list downstream.
  if [[ -n "${_out}" ]]; then
    printf '%s\n' "${_out}"
  fi
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
