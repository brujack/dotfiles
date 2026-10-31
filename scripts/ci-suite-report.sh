#!/usr/bin/env bash
# Report a bats run from its log and check the suite actually ran.
#
# Usage: ci-suite-report.sh <log-file> <tests-dir>
#        ci-suite-report.sh <log-file> --files <list-file>
#
# Prints the executed and declared test counts. Exit 0 only when they are
# equal and non-zero, so a run that stopped early or found no tests cannot pass.
# Declared tests are counted over every *.bats under <tests-dir>, or, with
# --files, over the paths listed one per line in <list-file> (a shard list).
# A blank line or an unreadable path in the list is a usage error (exit 2).

count_executed() {
  local _log="$1"
  grep -cE '^(ok|not ok) ' "${_log}"
}

count_declared() {
  local _dir="$1"
  find "${_dir}" -name '*.bats' -type f -exec cat {} + | grep -c '^@test'
}

# Sum '^@test' over the paths in a list file. Prints the total; returns 2 after
# naming the problem on stderr when the list or a listed path is unusable.
count_declared_from_list() {
  local _list="$1" _path _total=0 _n
  if [[ ! -r "${_list}" || -d "${_list}" ]]; then
    printf 'ci-suite-report: cannot read list file: %s\n' "${_list}" >&2
    return 2
  fi
  while IFS= read -r _path || [[ -n "${_path}" ]]; do
    if [[ -z "${_path}" ]]; then
      printf 'ci-suite-report: blank line in list file: %s\n' "${_list}" >&2
      return 2
    fi
    if [[ ! -r "${_path}" || -d "${_path}" ]]; then
      printf 'ci-suite-report: cannot read listed file: %s\n' "${_path}" >&2
      return 2
    fi
    # grep -c exits 1 on zero matches but still prints 0: that is not an error.
    _n="$(grep -c '^@test' "${_path}")"
    _total=$((_total + _n))
  done < "${_list}"
  printf '%s\n' "${_total}"
}

print_failures() {
  local _log="$1"
  # A not ok line plus the "#" diagnostic lines bats prints right after it.
  awk '/^not ok /{p=1; print; next} /^#/{if(p) print; next} {p=0}' "${_log}"
}

main() {
  local _log="$1" _dir="$2" _executed _declared _rc
  if [[ ! -r "${_log}" || -d "${_log}" ]]; then
    printf 'ci-suite-report: cannot read log file: %s\n' "${_log}" >&2
    return 2
  fi
  if [[ "${_dir}" == "--files" ]]; then
    _declared="$(count_declared_from_list "${3:-}")"
    _rc=$?
    [[ "${_rc}" -eq 0 ]] || return "${_rc}"
  elif [[ ! -d "${_dir}" ]]; then
    printf 'ci-suite-report: tests dir not found: %s\n' "${_dir}" >&2
    return 2
  else
    _declared="$(count_declared "${_dir}")"
  fi
  print_failures "${_log}"
  _executed="$(count_executed "${_log}")"
  printf 'executed=%s declared=%s\n' "${_executed}" "${_declared}"
  if [[ "${_declared}" -eq 0 || "${_executed}" -ne "${_declared}" ]]; then
    printf 'suite did not run completely: executed=%s declared=%s\n' \
      "${_executed}" "${_declared}" >&2
    return 1
  fi
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
