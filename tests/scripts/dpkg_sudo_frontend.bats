#!/usr/bin/env bats
# Every sudo call that runs dpkg must carry DEBIAN_FRONTEND=noninteractive on the
# sudo command line itself, between `sudo` (and its flags) and the command.
# needrestart's apt Post-Invoke hook raises a debconf dialog when stdout is not a
# tty (run_update tees it), and sudo resets the caller's environment, so a call
# without the assignment in that position can hang the update.
#
# A second verdict, using the same tokenizer, covers conffile prompts: a call that
# configures packages (apt/apt-get/nala install|reinstall|upgrade|full-upgrade|
# dist-upgrade|build-dep, dpkg -i|--install|--configure) must carry
# "${APT_CONFFILE_OPTS[@]}" or both --force-confdef and --force-confold, else
# dpkg asks about a modified conffile and a tee'd run hangs. The blind-spot list
# below applies to that verdict too.
#
# Known blind spots. NOT detected, so a dpkg call in one of these forms is unguarded:
#   sudo sh -c '...apt install...'    sudo "${VAR}" install    sudo /usr/bin/apt install
#   sudo -u user apt install          (any sudo flag that takes an argument)
#   sudo env|nice|command apt install (a wrapper between sudo and the tool)
#   verbs and flags absent from the tables in classify() (apt satisfy, dpkg --unpack,
#   apt-get --option X=Y install, combined dpkg flags such as -Ei)
#   an unquoted ${APT_CONFFILE_OPTS[@]} before the verb (read as the verb, so
#   neither verdict judges the call; quote it, or put it after the verb)
# The confmiss record names only the LAST .deb of a dpkg call that installs several.
# Falsely reported `bad`: `sudo apt install` text inside a string, heredoc or trailing
# comment, and a quoted value (DEBIAN_FRONTEND="noninteractive").
# On a false positive, reword the line (unquote the value, move the text to a
# whole-line comment). Do not teach the tokenizer a new shell form: add it to this
# list instead. The per-function frontend_probe_stub_path tests are the backstop.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  # tests/mocks shadows awk and git, and returns nothing for either.
  _CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
}

# Mode `frontend` (see _dpkg_sudo_calls) prints `<file>:<line>:ok` or
# `<file>:<line>:bad` for every dpkg-running sudo call in the given files, one record per call (a line holding two calls yields
# two records). A logical command is a run of physical lines joined by trailing
# backslashes, reported at its first line. Whole-line comments are skipped.
# A call is `ok` only if DEBIAN_FRONTEND=noninteractive follows `sudo` and its
# option flags directly, before the command. Written for mawk and BWK awk: POSIX
# classes only, no gawk extensions.
# Mode `conffile` prints the second verdict instead: `<file>:<line>:conffile:ok|bad`
# for each configuring call, and `<file>:<line>:confmiss:yes|no:<deb basename or ->`
# for each configuring call too (deb is `-` for apt-family calls).
_dpkg_awk() {
  local _mode="$1"
  shift
  PATH="${_CLEAN_PATH}" awk -v mode="${_mode}" '
    # Does token t[i..n] start a dpkg-running command? Prints nothing; sets hit.
    function classify(t, n, i,   j, tool, verb) {
      tool = t[i]
      hit = 0
      cfg = 0
      if (tool == "apt" || tool == "apt-get" || tool == "nala") {
        j = i + 1
        while (j <= n && (t[j] ~ /^-/ || t[j] == CONFFILE_ARR)) {
          # -o/-c/-t take a value; skip it or the value is read as the verb.
          if (t[j] == "-o" || t[j] == "-c" || t[j] == "-t") j++
          j++
        }
        verb = t[j]
        if (verb ~ /^(install|reinstall|upgrade|full-upgrade|dist-upgrade|build-dep)$/) cfg = 1
        if (verb ~ /^(install|reinstall|build-dep|full-upgrade|dist-upgrade|upgrade|autoremove|autopurge|remove|purge)$/) hit = 1
      } else if (tool == "dpkg") {
        for (j = i + 1; j <= n && t[j] ~ /^-/; j++) {
          if (t[j] ~ /^(-i|--install|-r|--remove|-P|--purge|--configure)$/) hit = 1
          if (t[j] ~ /^(-i|--install|--configure)$/) cfg = 1
        }
      } else if (tool == "dpkg-reconfigure") {
        hit = 1
      }
    }
    function judge(seg,   t, n, i, has, k, conf, def, old, miss, deb, b, v, apt) {
      # A trailing comment is not part of the call.
      sub(/[[:space:]]#.*$/, "", seg)
      n = split(seg, t, /[[:space:]]+/)
      i = 1
      while (i <= n && t[i] == "") i++
      # sudo own flags (-H, -E). A flag that takes an argument is a listed blind spot.
      while (i <= n && t[i] ~ /^-/) i++
      has = 0
      # Only the VAR=value run directly before the command reaches the child.
      while (i <= n && t[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        if (t[i] == "DEBIAN_FRONTEND=noninteractive") has = 1
        i++
      }
      classify(t, n, i)
      if (mode == "frontend") {
        if (hit) printf "%s:%d:%s\n", fname, start, (has ? "ok" : "bad")
        return
      }
      if (!cfg) return
      def = 0; old = 0; miss = 0; conf = 0; deb = "-"
      apt = (t[i] != "dpkg")
      for (k = i; k <= n; k++) {
        if (t[k] == CONFFILE_ARR) conf = 1
        # apt takes the options only as Dpkg::Options::=..., dpkg only as bare flags.
        v = t[k]
        gsub("[\"\047]", "", v)
        if (apt) sub(/^Dpkg::Options::=/, "dpkg-opt:", v)
        if (v == (apt ? "dpkg-opt:--force-confdef" : "--force-confdef")) def = 1
        if (v == (apt ? "dpkg-opt:--force-confold" : "--force-confold")) old = 1
        if (v == (apt ? "dpkg-opt:--force-confmiss" : "--force-confmiss")) miss = 1
        if (t[k] ~ /\.deb"?$/) { b = t[k]; sub(/"$/, "", b); sub(/.*\//, "", b); deb = b }
      }
      printf "%s:%d:conffile:%s\n", fname, start, ((conf || (def && old)) ? "ok" : "bad")
      printf "%s:%d:confmiss:%s:%s\n", fname, start, (miss ? "yes" : "no"), deb
    }
    function flush(   rest, seg, cut) {
      if (cmd == "") return
      rest = cmd
      while (match(rest, sudo_re)) {
        seg = substr(rest, RSTART + RLENGTH)
        rest = seg
        cut = seg
        # A call ends at the first | ; & so the next command is not read as this one.
        if (match(cut, /[|;&]/)) cut = substr(cut, 1, RSTART - 1)
        judge(cut)
      }
      cmd = ""
    }
    # The leading class keeps visudo, my_sudo and path/sudo from matching.
    BEGIN { CONFFILE_ARR = "\"${APT_CONFFILE_OPTS[@]}\""; sudo_re = "(^|[^A-Za-z0-9_./-])sudo[[:space:]]+" }
    # A continuation must not join across files.
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

_dpkg_sudo_calls() { _dpkg_awk frontend "$@"; }
_conffile_calls() { _dpkg_awk conffile "$@"; }

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

@test "every dpkg-running sudo call in lib/, setup_env.sh and scripts/ carries DEBIAN_FRONTEND=noninteractive" {
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
    printf 'False positive? See the blind-spot note at the top of %s.\n' "${BATS_TEST_FILENAME##*/}" >&2
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
    'lib/helpers.sh|sudo.*dpkg --install' \
    'scripts/bootstrap_linux.sh|sudo.*apt-get install'; do
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
    'sudo apt install foo -y # DEBIAN_FRONTEND=noninteractive' \
    'sudo DEBIAN_FRONTEND=dialog apt install foo -y'; do
    _expect_single bad "${_line}"
  done
}

@test "the detector accepts the assignment after sudo and its flags" {
  local _line
  for _line in \
    'sudo -H DEBIAN_FRONTEND=noninteractive apt install foo -y' \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y foo' \
    'sudo FOO=1 DEBIAN_FRONTEND=noninteractive apt install foo -y' \
    'sudo DEBIAN_FRONTEND=noninteractive FOO=1 apt install foo -y' \
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
    'sudo dpkg --remove foo' \
    'sudo dpkg -P foo' \
    'sudo apt -c /etc/apt/x.conf install foo' \
    'sudo apt -t noble install foo' \
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
    'pseudosudo apt install foo' \
    'my_sudo apt install foo' \
    'sudo tee /etc/apt/sources.list.d/x.list'; do
    [ -z "$(_detect_fixture "${_line}")" ]
  done
}

# ---- Conffile verdict ------------------------------------------------------
# Second verdict, same tokenizer: a call that configures packages (apt install and
# friends, dpkg -i/--install/--configure) must answer conffile prompts unattended.

# Print the conffile and confmiss records for the given lines, fixture path stripped.
_detect_conffile() {
  local _fx="${BATS_TEST_TMPDIR}/fixture.sh"
  printf '%s\n' "$@" > "${_fx}"
  _conffile_calls "${_fx}" | sed "s|^${_fx}:||"
}

# Only the conffile verdict records, for tests that do not look at confmiss.
_detect_verdicts() {
  _detect_conffile "$@" | grep ':conffile:'
}

@test "the conffile detector accepts the shared array after the verb" {
  run _detect_verdicts 'sudo -H DEBIAN_FRONTEND=noninteractive apt install x "${APT_CONFFILE_OPTS[@]}" -y'
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:ok" ]
}

@test "the conffile detector accepts the shared array before the verb and the frontend verdict still judges it" {
  local _line='sudo DEBIAN_FRONTEND=noninteractive apt "${APT_CONFFILE_OPTS[@]}" install x -y'
  run _detect_verdicts "${_line}"
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:ok" ]
  # The array token must be skipped by classify(), or the verb is never found.
  _expect_single ok "${_line}"
}

@test "the conffile detector accepts the literal option pair" {
  run _detect_verdicts \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y x'
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:ok" ]
}

@test "the conffile detector rejects a configuring call with no options" {
  run _detect_verdicts 'sudo DEBIAN_FRONTEND=noninteractive apt install x -y'
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:bad" ]
}

@test "the conffile detector rejects confdef without confold" {
  run _detect_verdicts \
    'sudo DEBIAN_FRONTEND=noninteractive apt -o Dpkg::Options::=--force-confdef install x -y'
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:bad" ]
}

@test "the conffile detector accepts dpkg -i with both flags after the deb" {
  run _detect_conffile \
    'sudo DEBIAN_FRONTEND=noninteractive dpkg -i ./x.deb --force-confdef --force-confold'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:conffile:ok\n1:confmiss:no:x.deb')" ]
}

@test "the conffile detector rejects dpkg -i with only one flag" {
  run _detect_conffile 'sudo DEBIAN_FRONTEND=noninteractive dpkg -i ./x.deb --force-confold'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:conffile:bad\n1:confmiss:no:x.deb')" ]
}

@test "the conffile detector reports confmiss and the deb basename" {
  run _detect_conffile \
    'sudo -H DEBIAN_FRONTEND=noninteractive dpkg -i "${HOME}"/dl/x.deb --force-confdef --force-confold --force-confmiss'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:conffile:ok\n1:confmiss:yes:x.deb')" ]
}

@test "the conffile detector rejects bare confdef/confold flags on apt" {
  run _detect_verdicts 'sudo DEBIAN_FRONTEND=noninteractive apt install x --force-confdef --force-confold -y'
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:bad" ]
}

@test "the conffile detector ignores options that sit in a trailing comment" {
  run _detect_verdicts \
    'sudo DEBIAN_FRONTEND=noninteractive apt install x # --force-confdef --force-confold' \
    'sudo DEBIAN_FRONTEND=noninteractive apt install y # -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:conffile:bad\n2:conffile:bad')" ]
}

@test "the conffile detector rejects near-miss and unconfigured forms" {
  local _line
  for _line in \
    'sudo DEBIAN_FRONTEND=noninteractive dpkg -i x.deb --force-confdefault --force-confold' \
    'sudo DEBIAN_FRONTEND=noninteractive apt install x ${APT_CONFFILE_OPTS[@]} -y' \
    'sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a' \
    'sudo DEBIAN_FRONTEND=noninteractive nala install x -y' \
    'sudo DEBIAN_FRONTEND=noninteractive apt reinstall x -y' \
    'sudo DEBIAN_FRONTEND=noninteractive apt build-dep x -y'; do
    run _detect_conffile "${_line}"
    if ! printf '%s\n' "${output}" | grep -qx '1:conffile:bad'; then
      printf 'expected 1:conffile:bad for: %s\ngot: %s\n' "${_line}" "${output}" >&2
      return 1
    fi
  done
}

@test "the conffile detector accepts a quoted option value" {
  run _detect_verdicts \
    'sudo DEBIAN_FRONTEND=noninteractive apt install x -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y'
  [ "$status" -eq 0 ]
  [ "$output" = "1:conffile:ok" ]
}

@test "the conffile detector judges the configuring call on line 2 and not the removal on line 1" {
  run _detect_verdicts \
    'sudo DEBIAN_FRONTEND=noninteractive apt remove x -y' \
    'sudo DEBIAN_FRONTEND=noninteractive apt install y -y'
  [ "$status" -eq 0 ]
  [ "$output" = "2:conffile:bad" ]
}

@test "the conffile detector reports confmiss on apt-family calls with no deb" {
  run _detect_conffile \
    'sudo DEBIAN_FRONTEND=noninteractive apt install x -y -o Dpkg::Options::=--force-confmiss' \
    'sudo DEBIAN_FRONTEND=noninteractive apt install y -y'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:conffile:bad\n1:confmiss:yes:-\n2:conffile:bad\n2:confmiss:no:-')" ]
}

@test "the conffile detector accepts single-quoted option values" {
  run _detect_conffile \
    "sudo DEBIAN_FRONTEND=noninteractive apt install x -o 'Dpkg::Options::=--force-confdef' -o 'Dpkg::Options::=--force-confold' -y"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1:conffile:ok\n1:confmiss:no:-')" ]
}

@test "every configuring apt/dpkg sudo call carries the conffile options" {
  local _files=() _f _calls _bad
  while IFS= read -r _f; do _files+=("${_f}"); done < <(_tracked_shell_files)
  [ "${#_files[@]}" -gt 0 ]
  _calls="$(_conffile_calls "${_files[@]}")"
  # An empty enumeration must fail, not pass: it would mean the detector is blind.
  [ "$(printf '%s\n' "${_calls}" | grep -c ':conffile:')" -gt 0 ]
  _bad="$(printf '%s\n' "${_calls}" | grep ':conffile:bad$' | sed "s|^${REPO_ROOT}/||" || true)"
  if [[ -n "${_bad}" ]]; then
    printf 'configuring sudo apt/dpkg call without the conffile options:\n%s\n' "${_bad}" >&2
    printf 'Fix (apt/apt-get/nala): add "${APT_CONFFILE_OPTS[@]}" after the verb, or, in a file that\n' >&2
    printf '  cannot source lib/constants.sh, the two literal options:\n' >&2
    printf '  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold\n' >&2
    printf 'Fix (dpkg): add --force-confdef --force-confold.\n' >&2
    printf 'See dotfiles-apt-upgrade-hazards.md section 2 in ai-config/docs/knowledge/.\n' >&2
    printf 'False positive? See the blind-spot note at the top of %s.\n' "${BATS_TEST_FILENAME##*/}" >&2
    return 1
  fi
}

@test "--force-confmiss appears exactly at the three archive-setup debs" {
  local _files=() _f _calls _deb _n _line
  local _CONFMISS_DEBS=(packages-microsoft-prod.deb volian-archive-keyring_0.2.0_all.deb volian-archive-nala_0.2.0_all.deb)
  while IFS= read -r _f; do _files+=("${_f}"); done < <(_tracked_shell_files)
  _calls="$(_conffile_calls "${_files[@]}" | grep ':confmiss:' || true)"
  for _deb in "${_CONFMISS_DEBS[@]}"; do
    _n="$(printf '%s\n' "${_calls}" | grep -c ":confmiss:[a-z]*:${_deb}\$" || true)"
    if [ "${_n}" -ne 1 ]; then
      printf 'expected exactly one confmiss record for %s, found %s\n' "${_deb}" "${_n}" >&2
      return 1
    fi
    if ! printf '%s\n' "${_calls}" | grep -q ":confmiss:yes:${_deb}\$"; then
      printf '%s lacks --force-confmiss\n' "${_deb}" >&2
      return 1
    fi
  done
  while IFS= read -r _line; do
    [[ "${_line}" == *":confmiss:yes:"* ]] || continue
    _deb="${_line##*:confmiss:yes:}"
    case " ${_CONFMISS_DEBS[*]} " in
      *" ${_deb} "*) ;;
      *) printf -- '--force-confmiss on a deb outside the allow-set: %s\n' "${_line}" >&2; return 1 ;;
    esac
  done <<< "${_calls}"
}
