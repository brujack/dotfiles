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
  local _awk_file
  _awk_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/bats_shard_pack.awk" || return 1
  if [[ ! -r "${_awk_file}" ]]; then
    shard_die "packer program unreadable: ${_awk_file}" || return 2
  fi
  LC_ALL=C awk -F'\t' -v idx="${_index}" -v n="${_count}" -v hc="${_handicap}" -f "${_awk_file}" "${_weights}" "$@" || return 1
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
