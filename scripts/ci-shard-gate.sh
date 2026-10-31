#!/usr/bin/env bash
# Check that the shards' file lists cover the suite exactly once.
#
# Usage: ci-shard-gate.sh [--with-traces] <dir>   (run from the repo root)
#
# Reads every <dir>/shard-*.files, one path per line, and checks:
#   coverage      the union of the lists equals an independent
#                 `find tests -name '*.bats' | LC_ALL=C sort` (equality, so a
#                 blank line, an extra path or a path split at a space fails);
#   disjointness  no path appears twice, within or across lists.
# Both checks run and both are reported before exiting.
#
# With --with-traces (once, before <dir>) a pairing check runs first: every
# shard-<i>.files needs a regular, non-empty shard-<i>.trace and every
# shard-*.trace needs its .files. A violation prints `pairing:` and one line
# per offending shard, then exits 1 without running the other checks.
#
# Exit 0 pass; 1 a check failed; 2 usage or input error (missing argument or
# directory, no shard-*.files, unreadable list, carriage return in a list,
# find failure). The find list is computed here, never by bats-shard.sh or make.

gate_die() {
  printf 'ci-shard-gate: %s\n' "$1" >&2
  return 2
}

# Append every non-blank line of the list files to the global _GATE_ALL and
# count blank lines in _GATE_BLANKS (a blank line is never a path, so coverage
# reports it as an extra entry).
# Returns 2 after naming the problem when a list is unreadable or holds a CR.
gate_collect() {
  local _file _line _n
  _GATE_ALL=""
  _GATE_BLANKS=0
  for _file in "$@"; do
    if [[ ! -r "${_file}" || -d "${_file}" ]]; then
      gate_die "cannot read list file: ${_file}" || return 2
    fi
    _n=0
    while IFS= read -r _line || [[ -n "${_line}" ]]; do
      _n=$((_n + 1))
      if [[ "${_line}" == *$'\r'* ]]; then
        gate_die "carriage return in ${_file} at line ${_n}" || return 2
      fi
      if [[ -z "${_line}" ]]; then
        _GATE_BLANKS=$((_GATE_BLANKS + 1))
      else
        _GATE_ALL+="${_line}"$'\n'
      fi
    done < "${_file}"
  done
}

# Print one line per shard that breaks the list/trace pairing in <dir>.
# Returns 1 when any line was printed.
gate_pairing() {
  local _dir="$1" _f _name _bad=0
  for _f in "${_dir}"/shard-*.files; do
    [[ -e "${_f}" || -L "${_f}" ]] || continue
    _name="$(basename "${_f}" .files)"
    if [[ ! -f "${_dir}/${_name}.trace" ]]; then
      printf '%s: missing %s.trace\n' "${_name}" "${_name}"
      _bad=1
    elif [[ ! -s "${_dir}/${_name}.trace" ]]; then
      printf '%s: empty %s.trace\n' "${_name}" "${_name}"
      _bad=1
    fi
  done
  for _f in "${_dir}"/shard-*.trace; do
    [[ -e "${_f}" || -L "${_f}" ]] || continue
    _name="$(basename "${_f}" .trace)"
    if [[ ! -e "${_dir}/${_name}.files" && ! -L "${_dir}/${_name}.files" ]]; then
      printf '%s: orphan %s.trace has no %s.files\n' "${_name}" "${_name}" "${_name}"
      _bad=1
    fi
  done
  return "${_bad}"
}

main() {
  local _dir _found _expected _union _missing _extra _dups _rc=0
  local _lists=() _f _with_traces=0 _pairing
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-traces)
        if [[ ${_with_traces} -eq 1 ]]; then
          gate_die "--with-traces given more than once" || return 2
        fi
        _with_traces=1
        shift
        ;;
      -*)
        gate_die "unknown option: $1" || return 2
        ;;
      *)
        break
        ;;
    esac
  done
  if [[ $# -ne 1 ]]; then
    gate_die "usage: ci-shard-gate.sh [--with-traces] <dir>" || return 2
  fi
  _dir="$1"
  if [[ ! -d "${_dir}" ]]; then
    gate_die "not a directory: ${_dir}" || return 2
  fi
  for _f in "${_dir}"/shard-*.files; do
    [[ -e "${_f}" || -L "${_f}" ]] && _lists+=("${_f}")
  done
  if [[ ${#_lists[@]} -eq 0 ]]; then
    gate_die "no shard-*.files in ${_dir}" || return 2
  fi
  if [[ ${_with_traces} -eq 1 ]]; then
    _pairing="$(gate_pairing "${_dir}")" || {
      printf 'pairing: shard lists and traces do not pair\n'
      printf '%s\n' "${_pairing}"
      return 1
    }
  fi
  # find's own status is checked: a pipeline would report sort's.
  _found="$(find tests -name '*.bats')" || {
    gate_die "find tests failed" || return 2
  }
  if [[ -z "${_found}" ]]; then
    gate_die "no .bats files under tests/" || return 2
  fi
  _expected="$(printf '%s\n' "${_found}" | LC_ALL=C sort)"
  gate_collect "${_lists[@]}" || return 2
  _union="$(printf '%s' "${_GATE_ALL}" | LC_ALL=C sort -u)"

  _missing="$(LC_ALL=C comm -23 <(printf '%s\n' "${_expected}") <(printf '%s\n' "${_union}"))"
  _extra="$(LC_ALL=C comm -13 <(printf '%s\n' "${_expected}") <(printf '%s\n' "${_union}"))"
  if [[ -n "${_missing}" || -n "${_extra}" || ${_GATE_BLANKS} -gt 0 ]]; then
    _rc=1
    printf 'coverage: the lists do not equal the find list\n'
    if [[ -n "${_missing}" ]]; then printf '%s\n' "${_missing}" | sed 's/^/missing: /'; fi
    if [[ -n "${_extra}" ]]; then printf '%s\n' "${_extra}" | sed 's/^/extra: /'; fi
    if [[ ${_GATE_BLANKS} -gt 0 ]]; then printf 'extra: \n'; fi
  fi

  _dups="$(printf '%s' "${_GATE_ALL}" | LC_ALL=C sort | LC_ALL=C uniq -d)"
  if [[ -n "${_dups}" ]]; then
    _rc=1
    printf 'disjointness: a path appears more than once\n'
    printf '%s\n' "${_dups}" | sed 's/^/duplicate: /'
  fi

  if [[ ${_rc} -eq 0 ]]; then
    printf 'ci-shard-gate: PASS %s files across %s lists\n' \
      "$(printf '%s\n' "${_expected}" | wc -l | tr -d ' ')" "${#_lists[@]}"
  fi
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
