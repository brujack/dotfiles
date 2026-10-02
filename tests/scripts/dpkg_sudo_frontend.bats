#!/usr/bin/env bats
# Every sudo call that runs dpkg must carry DEBIAN_FRONTEND=noninteractive on the
# sudo command line itself, between `sudo` (and its flags) and the command.
# needrestart's apt Post-Invoke hook raises a debconf dialog when stdout is not a
# tty (run_update tees it), and sudo resets the caller's environment, so a call
# without the assignment in that position can hang the update.
#
# Known blind spots, not detected: `sudo sh -c '...apt install...'`, a command held
# in a variable (`sudo "${VAR}" install`), and an absolute-path tool
# (`sudo /usr/bin/apt install`). A dpkg call made by one of those is unguarded.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  # tests/mocks shadows awk and git, and returns nothing for either.
  _CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
}

# Prints `<file>:<line>:ok` or `<file>:<line>:bad` for every dpkg-running sudo
# call in the given files, one record per call (a line holding two calls yields
# two records). A logical command is a run of physical lines joined by trailing
# backslashes, reported at its first line. Whole-line comments are skipped.
# A call is `ok` only if DEBIAN_FRONTEND=noninteractive follows `sudo` and its
# option flags directly, before the command. Written for mawk and BWK awk: POSIX
# classes only, no gawk extensions.
_dpkg_sudo_calls() {
  PATH="${_CLEAN_PATH}" awk '
    # Does token t[i..n] start a dpkg-running command? Prints nothing; sets hit.
    function classify(t, n, i,   j, tool, verb) {
      tool = t[i]
      hit = 0
      if (tool == "apt" || tool == "apt-get" || tool == "nala") {
        j = i + 1
        while (j <= n && t[j] ~ /^-/) {
          if (t[j] == "-o" || t[j] == "-c" || t[j] == "-t") j++
          j++
        }
        verb = t[j]
        if (verb ~ /^(install|reinstall|build-dep|full-upgrade|dist-upgrade|upgrade|autoremove|autopurge|remove|purge)$/) hit = 1
      } else if (tool == "dpkg") {
        for (j = i + 1; j <= n && t[j] ~ /^-/; j++)
          if (t[j] ~ /^(-i|--install|-r|--remove|-P|--purge|--configure)$/) hit = 1
      } else if (tool == "dpkg-reconfigure") {
        hit = 1
      }
    }
    function judge(seg,   t, n, i, has) {
      n = split(seg, t, /[[:space:]]+/)
      i = 1
      while (i <= n && t[i] == "") i++
      while (i <= n && t[i] ~ /^-/) i++
      has = 0
      while (i <= n && t[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        if (t[i] == "DEBIAN_FRONTEND=noninteractive") has = 1
        i++
      }
      classify(t, n, i)
      if (hit) printf "%s:%d:%s\n", fname, start, (has ? "ok" : "bad")
    }
    function flush(   rest, seg, cut) {
      if (cmd == "") return
      rest = cmd
      while (match(rest, sudo_re)) {
        seg = substr(rest, RSTART + RLENGTH)
        rest = seg
        cut = seg
        if (match(cut, /[|;&]/)) cut = substr(cut, 1, RSTART - 1)
        judge(cut)
      }
      cmd = ""
    }
    BEGIN { sudo_re = "(^|[^A-Za-z0-9_./-])sudo[[:space:]]+" }
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

# Write the given lines to a fixture file and print what the detector reports for
# it, with the fixture path stripped to just `<line>:<status>`.
_detect_fixture() {
  local _fx="${BATS_TEST_TMPDIR}/fixture.sh"
  printf '%s\n' "$@" > "${_fx}"
  _dpkg_sudo_calls "${_fx}" | sed "s|^${_fx}:||"
}

# Assert a single-line fixture is reported once, with the given status.
_expect_single() {
  local _status="$1" _line="$2" _got
  _got="$(_detect_fixture "${_line}")"
  if [[ "${_got}" != "1:${_status}" ]]; then
    printf 'fixture: %s\nexpected: 1:%s\ngot: %s\n' "${_line}" "${_status}" "${_got}" >&2
    return 1
  fi
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
    printf 'sudo dpkg call without DEBIAN_FRONTEND=noninteractive after sudo:\n%s\n' "${_bad}" >&2
    printf 'Fix: put the assignment directly after sudo and its flags, before the command, e.g.\n' >&2
    printf '  sudo -H DEBIAN_FRONTEND=noninteractive apt install foo -y\n' >&2
    printf 'An assignment before sudo (DEBIAN_FRONTEND=... sudo ...) is dropped by sudo.\n' >&2
    printf 'See CLAUDE.md, Shell Scripts.\n' >&2
    return 1
  fi
}

# The enumeration must reach a known site of each tool family, matched by file and
# command text rather than line number. Dropping lib/*.sh from the scope, or a
# tool from the detector, empties one of these and fails here.
@test "the real-tree enumeration reaches a named site of each tool family" {
  local _files=() _f _calls _spec _file _pat _n _hits
  while IFS= read -r _f; do _files+=("${_f}"); done < <(_tracked_shell_files)
  _calls="$(_dpkg_sudo_calls "${_files[@]}")"
  for _spec in \
    'lib/linux_shared.sh|sudo.*nala full-upgrade' \
    'lib/linux_ubuntu.sh|sudo.*dpkg -i' \
    'lib/helpers.sh|sudo.*dpkg --install'; do
    _file="${_spec%%|*}"
    _pat="${_spec#*|}"
    _hits=0
    while IFS=: read -r _n _; do
      [[ -z "${_n}" ]] && continue
      _hits=$((_hits + 1))
      if ! printf '%s\n' "${_calls}" | grep -qx "${REPO_ROOT}/${_file}:${_n}:ok"; then
        printf 'not enumerated as ok: %s:%s (%s)\n' "${_file}" "${_n}" "${_pat}" >&2
        return 1
      fi
    done < <(grep -nE "^[^#]*${_pat}" "${REPO_ROOT}/${_file}")
    [ "${_hits}" -gt 0 ]
  done
}

# Positive control: the same detector must flag a bad line, or the test above
# proves nothing about a regression.
@test "the detector reports exactly the bad call in a fixture" {
  run _detect_fixture \
    'good() {' \
    '  sudo -H DEBIAN_FRONTEND=noninteractive apt install foo -y' \
    '  sudo -H apt install foo -y' \
    '}'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '2:ok\n3:bad')" ]
}

@test "the detector rejects a DEBIAN_FRONTEND that is not directly after sudo" {
  local _line
  for _line in \
    'DEBIAN_FRONTEND=noninteractive sudo apt install foo -y' \
    'export DEBIAN_FRONTEND=noninteractive; sudo apt install foo -y' \
    'sudo apt install foo -y # DEBIAN_FRONTEND=noninteractive'; do
    _expect_single bad "${_line}"
  done
}

@test "the detector accepts the assignment after sudo and its flags" {
  local _line
  for _line in \
    'sudo -H DEBIAN_FRONTEND=noninteractive apt install foo -y' \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y foo' \
    'xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install -y' \
    'if ! sudo -H DEBIAN_FRONTEND=noninteractive dpkg -i foo.deb; then'; do
    _expect_single ok "${_line}"
  done
}

@test "the detector checks each sudo call on a line separately" {
  run _detect_fixture \
    'sudo -H apt install foo -y && sudo DEBIAN_FRONTEND=noninteractive apt install bar -y'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:bad\n1:ok')" ]
}

@test "the detector joins backslash continuations and skips comments" {
  run _detect_fixture \
    '# sudo -H apt install commented -y' \
    'sudo apt-get install -y \' \
    '  libfoo libbar' \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \' \
    '  libbaz' \
    'sudo -H apt update'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '2:bad\n4:ok')" ]
}

# The join is what decides these in both directions: the verdict depends on text
# that sits on the second physical line, so a detector that does not join gives
# the wrong answer for one of them.
@test "the detector's continuation join decides the verdict in both directions" {
  run _detect_fixture \
    'sudo -H \' \
    '  DEBIAN_FRONTEND=noninteractive apt install x -y' \
    'sudo -H \' \
    '  apt install y -y' \
    'sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y \' \
    '  libfoo \' \
    '  libbar'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:ok\n3:bad\n5:ok')" ]
}

@test "the detector enumerates each dpkg-running verb and tool" {
  local _line
  for _line in \
    'sudo -H nala full-upgrade -y' \
    'sudo -H nala autoremove -y' \
    'sudo -H nala upgrade' \
    'sudo apt-get dist-upgrade -y' \
    'sudo apt purge foo' \
    'sudo apt remove foo' \
    'sudo -H dpkg -i foo.deb' \
    'sudo -H dpkg --install foo.deb' \
    'sudo -E apt install foo' \
    'sudo apt reinstall foo' \
    'sudo apt build-dep foo' \
    'sudo apt autopurge' \
    'sudo apt-get -y -o Dpkg::Options::=--force-confold install foo' \
    'sudo dpkg --configure -a' \
    'sudo dpkg -r foo' \
    'sudo dpkg --purge foo' \
    'sudo dpkg-reconfigure foo'; do
    _expect_single bad "${_line}"
  done
}

@test "the detector ignores sudo calls that run no dpkg operation" {
  local _line
  for _line in \
    'sudo -H apt update' \
    'sudo apt-get update -qq' \
    'sudo systemctl restart docker' \
    'sudo tee /etc/apt/sources.list.d/x.list'; do
    [ -z "$(_detect_fixture "${_line}")" ]
  done
}
