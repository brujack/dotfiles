#!/usr/bin/env bash
# Report a bats run from its log and check the suite actually ran.
#
# Usage: ci-suite-report.sh <log-file> <tests-dir>
#
# Prints the executed and declared test counts. Exit 0 only when they are
# equal and non-zero, so a run that stopped early or found no tests cannot pass.

count_executed() {
  local _log="$1"
  grep -cE '^(ok|not ok) ' "${_log}"
}

count_declared() {
  local _dir="$1"
  find "${_dir}" -name '*.bats' -type f -exec cat {} + | grep -c '^@test'
}

print_failures() {
  local _log="$1"
  # A not ok line plus the "#" diagnostic lines bats prints right after it.
  awk '/^not ok /{p=1; print; next} /^#/{if(p) print; next} {p=0}' "${_log}"
}

main() {
  local _log="$1" _dir="$2" _executed _declared
  if [[ ! -r "${_log}" || -d "${_log}" ]]; then
    printf 'ci-suite-report: cannot read log file: %s\n' "${_log}" >&2
    return 2
  fi
  if [[ ! -d "${_dir}" ]]; then
    printf 'ci-suite-report: tests dir not found: %s\n' "${_dir}" >&2
    return 2
  fi
  print_failures "${_log}"
  _executed="$(count_executed "${_log}")"
  _declared="$(count_declared "${_dir}")"
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
