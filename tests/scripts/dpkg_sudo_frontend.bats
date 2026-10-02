#!/usr/bin/env bats
# Every sudo call that runs dpkg must carry DEBIAN_FRONTEND=noninteractive on the
# sudo command line itself. needrestart's apt Post-Invoke hook raises a debconf
# dialog when stdout is not a tty (run_update tees it), and sudo does not pass the
# caller's value through, so a call without the assignment can hang the update.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  # tests/mocks shadows awk and git, and returns nothing for either.
  _CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
}

# Prints `<file>:<line>:ok` or `<file>:<line>:bad` for every dpkg-running sudo
# call in the given files. A logical command is a run of physical lines joined by
# trailing backslashes, reported at its first line. Whole-line comments are skipped.
_dpkg_sudo_calls() {
  PATH="${_CLEAN_PATH}" awk '
    function flush(   body) {
      if (cmd == "") return
      body = cmd
      if (body ~ /sudo[^|;]*[[:space:]](apt|apt-get|nala)[[:space:]]+(-[A-Za-z-]+[[:space:]]+)*(install|full-upgrade|dist-upgrade|upgrade|autoremove|remove|purge)([[:space:]]|$)/ ||
          body ~ /sudo[^|;]*[[:space:]]dpkg[[:space:]]+(-i|--install)([[:space:]]|$)/) {
        printf "%s:%d:%s\n", fname, start, (body ~ /DEBIAN_FRONTEND=noninteractive/ ? "ok" : "bad")
      }
      cmd = ""
    }
    FNR == 1 { flush(); fname = FILENAME }
    /^[[:space:]]*#/ { flush(); next }
    {
      if (cmd == "") start = FNR
      line = $0
      if (line ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, " ", line); cmd = cmd line; next }
      cmd = cmd line
      flush()
    }
    END { flush() }
  ' "$@"
}

_tracked_shell_files() {
  PATH="${_CLEAN_PATH}" env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    git -C "${REPO_ROOT}" ls-files -- 'lib/*.sh' 'setup_env.sh' 'scripts/*.sh' \
    | sed "s|^|${REPO_ROOT}/|"
}

@test "every dpkg-running sudo call in tracked shell carries DEBIAN_FRONTEND=noninteractive" {
  local _files=() _f
  while IFS= read -r _f; do _files+=("${_f}"); done < <(_tracked_shell_files)
  [ "${#_files[@]}" -gt 0 ]
  local _calls
  _calls="$(_dpkg_sudo_calls "${_files[@]}")"
  # An empty enumeration must fail, not pass: it would mean the detector is blind.
  [ "$(printf '%s\n' "${_calls}" | grep -c ':ok$')" -gt 0 ]
  local _bad
  _bad="$(printf '%s\n' "${_calls}" | grep ':bad$' | sed "s|^${REPO_ROOT}/||" || true)"
  if [[ -n "${_bad}" ]]; then
    printf 'sudo dpkg call without DEBIAN_FRONTEND=noninteractive:\n%s\n' "${_bad}" >&2
    return 1
  fi
}

# Positive control: the same detector must flag a bad line, or the test above
# proves nothing about a regression.
@test "the detector reports exactly the bad call in a fixture" {
  local _fx="${BATS_TEST_TMPDIR}/fixture.sh"
  printf '%s\n' \
    'good() {' \
    '  sudo -H DEBIAN_FRONTEND=noninteractive apt install foo -y' \
    '  sudo -H apt install foo -y' \
    '}' > "${_fx}"
  run _dpkg_sudo_calls "${_fx}"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s:2:ok\n%s:3:bad' "${_fx}" "${_fx}")" ]
}

@test "the detector joins backslash continuations and skips comments" {
  local _fx="${BATS_TEST_TMPDIR}/fixture.sh"
  printf '%s\n' \
    '# sudo -H apt install commented -y' \
    'sudo apt-get install -y \' \
    '  libfoo libbar' \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \' \
    '  libbaz' \
    'sudo -H apt update' > "${_fx}"
  run _dpkg_sudo_calls "${_fx}"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s:2:bad\n%s:4:ok' "${_fx}" "${_fx}")" ]
}
