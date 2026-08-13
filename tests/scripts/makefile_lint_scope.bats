#!/usr/bin/env bats
#
# Verifies the Makefile's own ZSH_FILES/SHELL_FILES variables, not a
# re-derivation of the pathspec in the test — see the two `_make_print`
# helper vs. `_git_ls_clean` helper split below and the CLAUDE.md task
# writeup for why the completeness check must use an independently-derived
# regex rather than the same pathspec the Makefile uses.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # tests/mocks/git and tests/mocks/make would otherwise shadow the real
  # binaries this suite needs to invoke for real (shell.md PATH-mock
  # shadowing pitfall) -- strip the mocks dir from PATH for every call below.
  CLEAN_PATH="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  # Test isolation (tdd.md pitfall A): _make_print deliberately does NOT
  # strip these (see below) so the leaked-GIT_DIR test can prove the
  # Makefile's own env -u matters. Start every test from a known-clean
  # ambient state so an unrelated leak from whatever invoked bats can't
  # change what a "no GIT_DIR set" test observes.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  # MAKEFLAGS is deliberately left untouched here, unlike the GIT_* vars
  # above. make exports it into every recipe subshell automatically,
  # including this file's own `bats --recursive tests/` recipe under
  # `make test` -- so once the Makefile declares
  # `MAKEFLAGS += --no-print-directory`, that flag is genuinely live in this
  # process's environment under that invocation route. A blanket unset here
  # was tried first and rejected: it would have scrubbed MAKEFLAGS before any
  # test body ran, making every per-call `env -u MAKEFLAGS` below redundant
  # (nothing left to strip) rather than wrong -- Case 1 and Case 2 would
  # still have correctly reflected the Makefile's own state either way, but
  # their `env -u MAKEFLAGS` would never once have been exercised against a
  # real leak, so its necessity would go permanently unverified under the one
  # invocation route (`make test`) where the leak is real (ci.md: "a check
  # derived from the same decision as the thing it checks cannot falsify
  # it"). Leaving MAKEFLAGS alone here is what keeps each measuring case's
  # own `env -u MAKEFLAGS` load-bearing rather than decorative.
  #
  # Known, unreached tradeoff: this also removes defence-in-depth against
  # MAKEFLAGS content OTHER than --no-print-directory, for any case that
  # forgets its own guard. Reproduced this session against the real
  # print-ZSH_FILES target, no env -u:
  #   $ MAKEFLAGS='--no-print-directory -j4 --jobserver-auth=fifo:/nonexistent' \
  #       gmake -C <repo> print-ZSH_FILES
  #   gmake: cannot open jobserver /nonexistent: No such file or directory
  #   gmake: warning: jobserver unavailable: using -j1.  Add '+' to parent make rule.
  #   <the real file list>
  # Both warnings land on stderr, and bats' `run` merges stderr into
  # `$output`/`$lines` by default (confirmed this session) -- so under bats
  # this hostile value produces lines=3 instead of lines=1, which would break
  # a set-equality assertion built on `_sorted_lines_from_space_list`.
  # Nothing in this file's suite runs `make -j`, so this is not reachable
  # today; it is recorded here as a known decision, not fixed with code.
}

# GNU Make's `--version` first line is "GNU Make X.Y[.Z]"; every make this
# repo cares about (3.81 shipped by macOS, 4.x from Homebrew or apt) matches
# this. A candidate that fails to match (a look-alike binary with "make" in
# its name, e.g. cmake) is treated as absent, not as version 0.
_make_major_version() {
  local _mk="$1" _ver
  _ver="$("${_mk}" --version 2>/dev/null | head -1)"
  if [[ "${_ver}" =~ GNU\ Make\ ([0-9]+)\. ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Resolves the <4 arm from /usr/bin/make specifically, per the plan: that is
# the one path every mac in the fleet ships as 3.81 (shell.md pitfall G).
# Absent, or already >=4 (e.g. a Linux box where /usr/bin/make is current),
# the caller skips -- there is no other <4 candidate to fall back to.
_find_make_lt4() {
  local _mk="/usr/bin/make" _major
  [[ -x "${_mk}" ]] || return 1
  _major="$(_make_major_version "${_mk}")" || return 1
  [[ "${_major}" -lt 4 ]] || return 1
  printf '%s\n' "${_mk}"
}

# Resolves the >=4 arm by scanning PATH in order for a "make" or "gmake"
# binary whose *measured* version is >=4 -- never by assuming a name implies
# a version. Checking "make" as well as "gmake" is load-bearing: ubuntu-latest
# (the CI merge gate) ships no gmake at all, but its plain /usr/bin/make is
# already >=4. A helper that only looked for "gmake" would silently skip this
# case on the one runner where it must actually run (ci.md).
_find_make_ge4() {
  local _dir _name _candidate _major
  local -a _path_dirs
  IFS=':' read -ra _path_dirs <<< "${CLEAN_PATH}"
  for _dir in "${_path_dirs[@]}"; do
    [[ -d "${_dir}" ]] || continue
    for _name in make gmake; do
      _candidate="${_dir}/${_name}"
      [[ -x "${_candidate}" ]] || continue
      _major="$(_make_major_version "${_candidate}")" || continue
      if [[ "${_major}" -ge 4 ]]; then
        printf '%s\n' "${_candidate}"
        return 0
      fi
    done
  done
  return 1
}

# Reads a Makefile-derived variable through the Makefile's own `print-%`
# target. Deliberately does NOT strip GIT_DIR/GIT_WORK_TREE/GIT_COMMON_DIR/
# GIT_INDEX_FILE -- doing so would test the harness's own stripping instead
# of the Makefile's. The Makefile's `ZSH_FILES :=`/`SHELL_FILES :=`
# assignments carry their own `env -u ...` prefix (ci.md: GIT_DIR leaks into
# the pre-push hook from a worktree push) and that prefix is what must be
# proven to work -- see the "survives a leaked GIT_DIR" test below.
# --no-print-directory is load-bearing, not tidiness. GNU Make >= 4.0 emits
# "Entering directory"/"Leaving directory" on stdout whenever -C changes the
# working directory; 3.81 (which Apple still ships) does not. Without the flag
# those two lines are parsed as filenames, so the resolved set gains the same
# junk tokens for EVERY variable -- which makes the disjointness assertion below
# fail while the superset assertion still passes. Measured: 1 line of output
# under make 3.81, 3 lines under gmake 4.4.1, for the identical command.
_make_print() {
  PATH="${CLEAN_PATH}" make --no-print-directory -C "${REPO_ROOT}" "print-${1}"
}

_git_ls_clean() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    PATH="${CLEAN_PATH}" git -C "${REPO_ROOT}" ls-files "$@"
}

_sorted_lines_from_space_list() {
  printf '%s\n' "${1}" | tr ' ' '\n' | sort -u
}

@test "ZSH_FILES equals git ls-files over the zsh pathspecs, as a set" {
  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"
  expected="$(_git_ls_clean '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' | sort -u)"
  if [ "${resolved}" != "${expected}" ]; then
    printf 'ZSH_FILES resolved:\n%s\n--- expected:\n%s\n' "${resolved}" "${expected}" >&2
  fi
  [ "${resolved}" = "${expected}" ]
}

@test "every tracked zsh file, independently derived by name OR shebang, is present in ZSH_FILES" {
  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"

  # Filename arm: broad regex, deliberately NOT the Makefile's own pathspec
  # -- so a wrong/narrow Makefile pathspec (as happened twice already:
  # bruce.zsh-theme, then .zprofile) is caught rather than rubber-stamped by
  # a second copy of the same glob.
  by_name="$(_git_ls_clean | grep -E '\.zsh(-theme)?$|(^|/)\.z[a-z]+$' || true)"

  # Shebang arm: content-derived, orthogonal to any filename rule -- catches
  # a zsh script whose name is not zsh-shaped at all (this repo already
  # carries extensionless hook scripts for bash: scripts/pre-push,
  # scripts/commit-msg). Piped straight from `ls-files -z` into `xargs -0`,
  # never through `$(...)`, because command substitution silently drops the
  # NUL delimiters (shell.md).
  by_shebang="$(_git_ls_clean -z | xargs -0 grep -l '^#!.*[/ ]zsh' 2>/dev/null || true)"

  # Union, not either arm alone: .zshrc has no shebang, so the shebang arm
  # by itself would miss it -- the same lesson in the other direction from
  # the filename arm missing an extensionless script.
  broad="$(printf '%s\n%s\n' "${by_name}" "${by_shebang}" | grep -v '^$' | sort -u)"
  [ -n "${broad}" ]

  missing=""
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    printf '%s\n' "${resolved}" | grep -qxF "${f}" || missing="${missing}${f}\n"
  done <<< "${broad}"

  if [ -n "${missing}" ]; then
    printf 'missing from ZSH_FILES:\n%b' "${missing}" >&2
  fi
  [ -z "${missing}" ]
}

@test "SHELL_FILES and ZSH_FILES are disjoint" {
  run _make_print SHELL_FILES
  [ "${status}" -eq 0 ]
  shell_files="$(_sorted_lines_from_space_list "${output}")"

  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  zsh_files="$(_sorted_lines_from_space_list "${output}")"

  overlap="$(comm -12 <(printf '%s\n' "${shell_files}") <(printf '%s\n' "${zsh_files}"))"
  if [ -n "${overlap}" ]; then
    printf 'SHELL_FILES/ZSH_FILES overlap:\n%s\n' "${overlap}" >&2
  fi
  [ -z "${overlap}" ]
}

@test "SHELL_FILES and ZSH_FILES are both non-empty" {
  run _make_print SHELL_FILES
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "make print-ZSH_FILES survives a leaked GIT_DIR pointed at a decoy repo" {
  decoy="${BATS_TEST_TMPDIR}/decoy"
  mkdir -p "${decoy}"
  PATH="${CLEAN_PATH}" git -C "${decoy}" init --quiet
  PATH="${CLEAN_PATH}" git -C "${decoy}" config user.email "test@test.com"
  PATH="${CLEAN_PATH}" git -C "${decoy}" config user.name "Test"
  printf 'echo hi\n' > "${decoy}/a.zsh"
  PATH="${CLEAN_PATH}" git -C "${decoy}" add a.zsh
  PATH="${CLEAN_PATH}" git -C "${decoy}" commit --quiet -m "decoy"

  # A leaked GIT_DIR is exactly what the Makefile's `env -u GIT_DIR ...`
  # prefix exists to survive (ci.md: git exports GIT_DIR into the pre-push
  # hook when the push originates from a worktree). If that prefix is
  # deleted from the ZSH_FILES assignment, `git ls-files` here resolves
  # against the decoy repo's single a.zsh instead of the real repo's ten --
  # shell.md: `-C` does not override an exported GIT_DIR.
  # --no-print-directory for the same reason _make_print carries it: this
  # call cannot use that helper (it needs the GIT_DIR prefix), so the flag
  # has to be repeated here rather than inherited.
  run env GIT_DIR="${decoy}/.git" PATH="${CLEAN_PATH}" \
    make --no-print-directory -C "${REPO_ROOT}" print-ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"
  expected="$(_git_ls_clean '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' | sort -u)"
  if [[ "${resolved}" != "${expected}" ]]; then
    printf 'resolved:\n%s\nexpected:\n%s\n' "${resolved}" "${expected}" >&2
  fi
  [ "${resolved}" = "${expected}" ]
}

@test "make -n lint dry-run wires zsh -n to ZSH_FILES, not SHELL_FILES" {
  run env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    bash -c "PATH='${CLEAN_PATH}' make --no-print-directory -C '${REPO_ROOT}' -n lint"
  [ "${status}" -eq 0 ]

  count="$(printf '%s\n' "${output}" | grep -c 'zsh  -n')"
  [ "${count}" -eq 1 ]

  # The line immediately before `zsh  -n ...` is the `for` loop it lives
  # inside. It must be fed by ZSH_FILES -- bruce.zsh-theme is a name
  # SHELL_FILES's *.sh/*.bash/hook pathspec can never match -- and must NOT
  # be fed by SHELL_FILES -- lib/constants.sh is a bash file that must not
  # appear in a zsh -n loop.
  for_line="$(printf '%s\n' "${output}" | grep -B1 'zsh  -n' | head -1)"
  [[ "${for_line}" == *"bruce.zsh-theme"* ]]
  [[ "${for_line}" != *"lib/constants.sh"* ]]
}

# Case 1: MAKEFLAGS += --no-print-directory (Makefile:1) is what makes
# print-ZSH_FILES's line count identical whether the invoking make is < 4.0
# or >= 4.0. `env -u MAKEFLAGS` is mandatory here, not decoration -- but it
# guards this case alone, and only in one direction. This is a *symmetric*
# two-arm comparison: if `env -u MAKEFLAGS` is ever dropped and MAKEFLAGS
# leaks in with --no-print-directory (e.g. from `make test`'s own recipe
# subshell, which inherits it from the top-of-file directive), BOTH arms are
# masked identically -- the <4 arm was already unaffected (3.81 never prints
# these lines) and the >=4 arm now gets suppressed by the leak instead of by
# the Makefile. Line counts stay equal either way, so this case does not
# fail on the missing guard: it goes *blind*, quietly passing regardless of
# whether the Makefile's own directive is present. It cannot detect an
# environment leak; what it detects, given its own `env -u` intact, is the
# Makefile directive's absence (1 vs 3 -- measured directly, mutation-
# checked). Measuring the environment instead of the Makefile is exactly the
# failure mode ci.md warns about ("a check derived from the same decision as
# the thing it checks cannot falsify it") -- this case's own guard is what
# keeps it out of that trap, and nothing else in this file substitutes for
# it. The <4 arm cannot exist on ubuntu-latest -- its /usr/bin/make is
# already >=4 -- so this case skips there by design; a green CI run is not
# evidence for this specific case, only local runs on a mac (or any host
# still carrying a genuine <4 make) are.
@test "print-ZSH_FILES line count is equal and nonzero across a <4 make and a >=4 make" {
  local _make_lt4 _make_ge4 _lt4_count _ge4_count
  _make_lt4="$(_find_make_lt4)" \
    || skip "no <4 arm: /usr/bin/make is missing or already >=4 on this host"
  _make_ge4="$(_find_make_ge4)" \
    || skip "no >=4 arm: no make/gmake >=4 found on PATH"

  run env -u MAKEFLAGS PATH="${CLEAN_PATH}" "${_make_lt4}" -C "${REPO_ROOT}" print-ZSH_FILES
  [ "${status}" -eq 0 ]
  # bats strips $output's trailing newline, so `printf '%s\n' "$output" | wc -l`
  # floors at 1 even for genuinely empty output -- `wc -l` cannot see the
  # difference between "one line" and "no output at all". The `lines` array
  # bats also populates has no such floor -- confirmed this session with
  # `run printf ''`: output=[], -n output=no, lines=0. `lines` and `wc -l`
  # are also not interchangeable on non-empty output: confirmed this session
  # with `run printf 'a\n\nc\n'`, lines=2 but wc -l=3 -- bats' `lines` is a
  # non-blank-line count. This payload has no blank lines, so that gap does
  # not matter here, but the two counters are not substitutable in general.
  [ -n "${output}" ]
  _lt4_count="${#lines[@]}"

  run env -u MAKEFLAGS PATH="${CLEAN_PATH}" "${_make_ge4}" -C "${REPO_ROOT}" print-ZSH_FILES
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  _ge4_count="${#lines[@]}"

  # No separate nonzero assertion here: `[ -n "${output}" ]` above already
  # guarantees `${#lines[@]} >= 1` -- confirmed this session across three
  # cases (`run printf ''`, `run printf '\n\n\n'`, `run printf ' '`): every
  # case where `-n "${output}"` was true also had lines >= 1, and every case
  # where it was false had lines=0. A bare `-gt 0` on _lt4_count here would
  # be dead code duplicating that guarantee.
  if [ "${_lt4_count}" -ne "${_ge4_count}" ]; then
    printf '<4 (%s) line count %s != >=4 (%s) line count %s\n' \
      "${_make_lt4}" "${_lt4_count}" "${_make_ge4}" "${_ge4_count}" >&2
  fi
  [ "${_lt4_count}" -eq "${_ge4_count}" ]
}

# Case 2: print-% (Makefile:144) must return the exact configured value, not
# merely a nonzero/matching-length verdict -- otherwise Case 1's line-count
# equality could pass even if a >=4 make's "Entering directory" text had
# silently become part of the payload on some future GNU Make release that
# changes where it emits that text. Run through the >=4 arm specifically: on
# this repo's own default `make` (3.81 on every mac), the directory lines
# never appeared at all, so that arm alone would not exercise the case the
# MAKEFLAGS directive exists to fix. `env -u MAKEFLAGS` on this test's `run`
# line matters here too: with it present and the Makefile directive absent,
# confirmed this session that print-BATS_MISSING's raw output no longer
# equals the expected string (the directory lines land in `$output`) -- this
# case correctly goes red in that state. With this guard dropped AND an
# ambient leaked MAKEFLAGS containing --no-print-directory present, also
# confirmed this session: the leak itself suppresses the directory lines,
# output is clean, and the case goes blind (a false match) exactly like
# Case 1 does under the same condition -- there is no asymmetry between the
# two cases here.
@test "print-BATS_MISSING returns the exact configured message under a >=4 make" {
  local _make_ge4 _expected
  _make_ge4="$(_find_make_ge4)" \
    || skip "no >=4 arm: no make/gmake >=4 found on PATH"

  # GUARDED, not measuring -- and the reason is measured, not assumed.
  #
  # This case pins an exact derived value; it has no interest in directory
  # lines, so it takes the per-call flag like any other guarded invocation.
  # It previously used `env -u MAKEFLAGS` and passed on macOS while failing on
  # ubuntu-latest (dotfiles#214 CI). Measured on GNU Make 4.3 (Ubuntu 24.04,
  # the ubuntu-latest image) by a session on the Linux workstation:
  #
  #   in-Makefile `MAKEFLAGS += --no-print-directory`, invoked with -C
  #     4.3   -> 3 lines WITH the directive, 3 lines WITHOUT -- byte-identical,
  #              the directive is INERT because -C prints "Entering directory"
  #              before the Makefile is parsed
  #     4.4.1 -> 1 line with, 3 without -- suppressed
  #   per-call --no-print-directory  -> suppressed on BOTH
  #   inherited MAKEFLAGS in env     -> suppressed on BOTH
  #
  # So `env -u MAKEFLAGS` strips the one mechanism that works on 4.3 and
  # leaves the one that does not. The call-site flag works everywhere, which
  # is what tdd.md pitfall G prescribes in the first place.
  run env PATH="${CLEAN_PATH}" "${_make_ge4}" --no-print-directory \
    -C "${REPO_ROOT}" print-BATS_MISSING
  [ "${status}" -eq 0 ]
  # Derived from the Makefile rather than hand-typed: a literal here asserts
  # the transcription, not the file. Content-derived vs execution-derived are
  # different mechanisms, so this is not circular.
  _expected="$(sed -n 's/^BATS_MISSING := //p' "${REPO_ROOT}/Makefile")"
  [ -n "${_expected}" ]
  if [ "${output}" != "${_expected}" ]; then
    printf 'make: %s\n' "$("${_make_ge4}" --version | head -1)" >&2
    printf 'expected: [%s]\n' "${_expected}" >&2
    printf 'actual:   [%s]\n' "${output}" >&2
  fi
  [ "${output}" = "${_expected}" ]
}

# Case 5 (numbered per the plan -- 3/4/6 belong to a later task): a control,
# not a canary for the other cases. It establishes the baseline Case 1 and
# Case 2 depend on -- that a directive-free Makefile run under a >=4 make,
# with nothing suppressing the output, genuinely shows "Entering directory" /
# "Leaving directory". This uses `env MAKEFLAGS=` (an explicit empty value)
# rather than `env -u MAKEFLAGS`. Confirmed this session that the two forms
# are equivalent on both /usr/bin/make 3.81 and gmake 4.4.1, including
# against a hostile ambient MAKEFLAGS
# (`--no-print-directory -j4 --jobserver-auth=fifo:/nonexistent`) and with
# MAKELEVEL=1 inherited -- both forms gave identical line counts in every
# case tested. `MAKEFLAGS=` was chosen only to match the plan's own wording
# ("MAKEFLAGS inherited"), not because `env -u` would behave differently
# here. That normalization guards this case's own baseline only; it says nothing about,
# and cannot substitute for, Case 1's or Case 2's own `env -u MAKEFLAGS` --
# each measuring case's guard is load-bearing for that case alone (see their
# comments), and this one is no exception in the other direction: dropping
# it would only make Case 5 itself vulnerable to a leaked ambient MAKEFLAGS,
# not any other case. A blanket `unset MAKEFLAGS` in setup() was tried first
# and rejected: it would have made Case 1's and Case 2's own
# `env -u MAKEFLAGS` redundant (nothing left to strip), silently proving
# nothing regardless of whether their per-call guards were present. Left
# alone, setup() leaves MAKEFLAGS live under `make test` (which exports it
# once the Makefile carries the directive), which is what keeps Case 1's and
# Case 2's own guards meaningful; this case's `MAKEFLAGS=` is what keeps ITS
# baseline deterministic across both `bats tests/...` (no parent MAKEFLAGS to
# begin with) and `make test` (parent MAKEFLAGS carries --no-print-directory)
# invocation routes.
@test "a directive-free fixture Makefile emits directory lines under a >=4 make, MAKEFLAGS inherited" {
  local _make_ge4 _fixture_dir _lines_count
  _make_ge4="$(_find_make_ge4)" \
    || skip "no >=4 arm: no make/gmake >=4 found on PATH"

  _fixture_dir="${BATS_TEST_TMPDIR}/fixture"
  mkdir -p "${_fixture_dir}"
  cat > "${_fixture_dir}/Makefile" <<'FIXTURE_EOF'
FOO := bar
print-%:
	@printf '%s\n' "$($*)"
FIXTURE_EOF

  run env MAKEFLAGS= PATH="${CLEAN_PATH}" "${_make_ge4}" -C "${_fixture_dir}" print-FOO
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  [[ "${output}" == *"Entering directory"* ]]
  [[ "${output}" == *"Leaving directory"* ]]
  _lines_count="${#lines[@]}"
  [ "${_lines_count}" -eq 3 ]
}

# Case 3: the Makefile directive itself. Cases 1/2/5 above all reason about
# what happens once this line exists; nothing until now asserted the line is
# actually there. A `+=` (not `=`) is required verbatim -- `=` would still
# read as a plausible diff to someone editing the file, but Makefile's own
# comment at line 2 documents this as an append ("MAKEFLAGS is an exported
# environment variable... it removes print-directory variance at the source
# rather than repeating --no-print-directory at every -C call site"), and an
# unconditional `=` would discard whatever MAKEFLAGS the invoking shell
# already carried instead of adding to it.
@test "Makefile carries the MAKEFLAGS no-print-directory directive" {
  grep -qE '^MAKEFLAGS[[:space:]]*\+=[[:space:]]*--no-print-directory[[:space:]]*$' \
    "${REPO_ROOT}/Makefile"
}

# Case 4: the structural partition scanner. Every stdout-capturing `make -C`
# invocation in a test file must be either guarded (a per-call
# --no-print-directory) or measuring (env -u MAKEFLAGS, or the explicit
# empty MAKEFLAGS= assignment that Case 5 above establishes as
# behaviourally identical) -- never neither.
#
# What makes a line able to print Entering/Leaving at all is NOT simply
# "-C". Measured this session against a scratch fixture (FOO := bar;
# print-%: @printf '%s\n' "$($*)"), gmake 4.4.1:
#   $ gmake sub                # sub: recipe is "$(MAKE) print-FOO", no -C anywhere
#   gmake print-FOO
#   gmake[1]: Entering directory '/path/to/fixture2'
#   bar
#   gmake[1]: Leaving directory '/path/to/fixture2'
#   $ gmake -w print-FOO       # -w/--print-directory, no -C
#   gmake: Entering directory '/path/to/fixture2'
#   bar
#   gmake: Leaving directory '/path/to/fixture2'
# A recursive sub-make (via $(MAKE)) and an explicit -w/--print-directory
# both print the directory lines with no "-C" anywhere on the invoking
# line. This scanner's real boundary is therefore -C / -w / --print-directory
# at the call site -- a recursive sub-make cannot be seen by a line scanner
# at all, because whether a target recurses is a property of its recipe, not
# of the line that invokes make. Not reachable today: the root Makefile has
# zero $(MAKE) recipes and `make -n test` emits no sub-make (verified this
# session), but powershell/Makefile exists and is untouched by this
# scanner. Recorded as an accepted gap, not fixed here -- a line scanner
# cannot see recursion.
#
# Domain used to be a hardcoded two-file array, then every tracked *.bats
# file -- exactly tdd.md's Coverage Denominators failure shape each time: a
# hand-maintained/narrowly-typed list whose omissions are invisible because
# an excluded file is absent from numerator and denominator alike. It is now
# every tracked *.bats file AND *.bash file, derived through `_git_ls_clean
# 'tests/*.bats' 'tests/*.bash'` (the same env -u GIT_DIR/GIT_WORK_TREE/
# GIT_COMMON_DIR/GIT_INDEX_FILE strip the ZSH_FILES tests above use, and for
# the identical reason -- shell.md: `git -C` does not override an exported
# GIT_DIR). tests/helpers/common.bash is tracked and sourced by the suite,
# and was invisible to this scanner purely because of its extension.
# Measured this session it contributes zero candidates (`grep -n
# 'make\|-C ' tests/helpers/common.bash` -> no matches), so widening the
# domain moves domain_files but not candidates/guarded/measuring/neither.
#
# An independent review constructed five bypasses against the previous
# version of this scanner. Each was reproduced this session before being
# closed, and closing bypass 1 opened a sixth problem that needed its own
# fix (see below):
#
#   1. Case sensitivity. The final filter was a case-sensitive `grep 'make'`,
#      so a line whose invoked binary is held in a variable like
#      `${MAKE_BIN}` was invisible to it -- confirmed this session: piping a
#      synthetic `"${MAKE_BIN}" -C "$d" print-FOO` line through the old
#      three-grep chain produced zero output, purely because the suite's own
#      helper vars happen to be spelled lowercase ("${_make_lt4}"/
#      "${_make_ge4}"). Fixed by matching "make" case-insensitively.
#      Case-insensitivity alone creates a new false positive: `git -C
#      "${_wt_source}" add Makefile` (a real line in
#      tests/setup_env/git_hooks.bats) case-insensitively contains
#      "makefile", whose first four characters are "make" -- confirmed this
#      session this exact line was the sole "neither" hit produced by a
#      naive case-insensitive substring match, raising the real domain's
#      candidate count from 12 to 13. Closed by stripping literal
#      "makefile" occurrences before testing for "make": `git -C ... add
#      Makefile` has none left afterward; `"${_make_lt4}"`/`"${_make_ge4}"`/
#      `"${MAKE_BIN}"` still do.
#
#   2. Line continuations. A make/-C pair split across a shell continuation
#      (`run "${_make_ge4}" \` on one physical line, `-C "${d}" print-FOO`
#      on the next) was invisible: confirmed this session that run through
#      the old ' -C ' grep one raw line at a time, the continuation line has
#      no -C and the -C line has no make, so neither line matched and the
#      pair produced zero candidates. Fixed by joining any line ending in a
#      lone trailing backslash with the line(s) that follow before candidate
#      detection, tagged with its starting line number so reported
#      locations stay resolvable.
#
#   3. -C forms the pattern missed. Measured this session against the same
#      scratch fixture as above, gmake 4.4.1: `gmake -C"$d" print-FOO`
#      (packed, no space) and `gmake --directory="$d" print-FOO` (long form)
#      both print Entering/Leaving exactly like the space-separated form the
#      old ' -C ' pattern required. Fixed by widening the pattern to accept
#      -C followed by whitespace, a quote, or $-interpolation, or the
#      literal --directory.
#
#   4. First-match-wins. `run bash -c "make --no-print-directory -C a
#      print-X; make -C b print-Y"` classified as guarded outright under the
#      old check ("does --no-print-directory appear anywhere in the line") --
#      true for the FIRST invocation only; the second has no guard and was
#      never separately considered. Fixed by splitting each candidate line
#      on `;`, `&&`, and `|` and reclassifying each resulting segment that is
#      itself a make/-C candidate -- confirmed this session the sample line
#      above now yields one guarded segment and one neither segment, not one
#      guarded line. Known limitation: the split is a plain delimiter split,
#      not a shell parse, so a `;`/`&&`/`|` inside a quoted argument would be
#      mis-split -- not reachable in this domain today, no real candidate
#      line contains one.
#
#   5. The grep exclusion was over-broad. The old rule dropped any line
#      whose invoked command was `grep`, to exclude
#      tests/scripts/pre_push.bats's 27 lines of the shape `grep -qE "^make
#      -C .* test$" "${MOCK_CALLS_FILE}"` (string-matching a log of calls
#      already made to a *mocked* make, not invoking a real one). That same
#      blanket rule also dropped a grep line that performs a real invocation
#      through command or process substitution, e.g. `grep -q "^bar$"
#      <(make -C "${d}" print-FOO)`. Fixed by keeping the exclusion only
#      when the grep-led line contains none of `$(`, `<(`, or a backtick --
#      confirmed this session the mock-log-check shape (no substitution)
#      still excludes, and the process-substitution shape (a real
#      invocation) no longer does.
#
#   6. `env MAKEFLAGS=-w make -C "$d" ...` still prints the directory lines
#      (MAKEFLAGS=-w carries no --no-print-directory) but the old check --
#      "does the literal substring MAKEFLAGS= appear anywhere" -- classified
#      it as measuring regardless of the value. Fixed by requiring the value
#      after MAKEFLAGS= to be empty (immediately followed by whitespace, a
#      quote, or end of string) -- confirmed this session MAKEFLAGS=-w no
#      longer matches while MAKEFLAGS= and MAKEFLAGS="" still do.
#
# A seventh item, not itself a bypass but folded in for the same reason
# _git_ls_clean strips PATH: the candidate-extraction pipeline had no PATH
# scrubbing. Inert today -- tests/mocks/ has neither a `grep` nor an `awk`
# nor a `sed` -- but a live bug the day one is added (shell.md's PATH-mock-
# shadowing pitfall). Every external call this Case makes now runs under
# `PATH="${CLEAN_PATH}"`.
#
# Fixing bypass 2 (continuation joining) surfaced a self-inflicted eighth
# problem: joining the OLD five-line, backslash-continued grep pipeline that
# implemented this very scanner reunited its own literal ' -C ' pattern
# argument and its own literal 'make' pattern argument onto one logical
# line -- the scanner's former source became a candidate for itself.
# Confirmed this session by running the join step against the pre-fix
# source and observing the pipeline's own `done < <(grep -nE ' -C ' ...)`
# line appear in the candidate list. Rewriting the pipeline in bash, with
# the patterns held in `_MAKE_C_FORM_RE`/`_EMPTY_MAKEFLAGS_RE` and referenced
# by variable name rather than re-typed as a literal quoted pattern beside
# the word "make", removes the literal substrings that caused the
# collision -- confirmed this session the current source, scanned by
# itself, adds no extra candidate over the count reported below.
#
# Full-domain sweep of the finished implementation below, measured this
# session with `bats --show-output-of-passing-tests`: 33 tracked files (32
# *.bats + tests/helpers/common.bash, which contributes zero candidates),
# 12 candidates -- unchanged from the pre-fix baseline, because the
# makefile-collision false positive the case-insensitive match introduces
# (bypass 1, above) is closed by the same commit's stripping fix, and
# because this rewrite's own source contains no literal "-C"/"make" text
# for the continuation-join step to reunite into a spurious self-match
# (also bypass 1's collision fix, above -- the domain widening to *.bash
# separately adds zero). guarded=8 (tests/makefile_scope.bats:36,45,68,79,
# tests/scripts/makefile_lint_scope.bats:123,228,240, and
# tests/scripts/unit.bats:819), measuring=4
# (tests/scripts/makefile_lint_scope.bats:286,300,340,386), neither=0.
_join_continuations() {
  PATH="${CLEAN_PATH}" awk '
    {
      startline = NR
      line = $0
      while (line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, " ", line)
        if ((getline nextline) <= 0) { break }
        line = line nextline
      }
      print startline ":" line
    }
  ' "$1"
}

# Bypass 3: -C followed by whitespace/quote/$-interpolation, or the literal
# --directory. Verified live above against gmake 4.4.1.
readonly _MAKE_C_FORM_RE='(^|[[:space:]])(-C[[:space:]"'"'"'$]|--directory)'
# Bypass 6: MAKEFLAGS= only counts as measuring when the value is empty --
# immediately followed by whitespace, a quote, or end of string.
readonly _EMPTY_MAKEFLAGS_RE='MAKEFLAGS=([[:space:]"'"'"'$]|$)'

# A make/-C candidate: the widened -C form above AND "make" case-
# insensitively, with literal "makefile" occurrences stripped first so a
# line whose only "make"-shaped text is the filename Makefile is not
# mistaken for an invocation (bypass 1's own collision, see above).
_is_make_c_candidate() {
  local _text="$1" _lc _lc_stripped
  [[ "${_text}" =~ ${_MAKE_C_FORM_RE} ]] || return 1
  _lc="${_text,,}"
  _lc_stripped="${_lc//makefile/}"
  [[ "${_lc_stripped}" == *make* ]] || return 1
  return 0
}

@test "every stdout-capturing make -C invocation in-domain is guarded or measuring, both sets nonempty" {
  local -a _domain_files=()
  local _rel
  while IFS= read -r _rel; do
    [ -z "${_rel}" ] && continue
    _domain_files+=("${REPO_ROOT}/${_rel}")
  done < <(_git_ls_clean 'tests/*.bats' 'tests/*.bash')
  [ "${#_domain_files[@]}" -gt 0 ]

  local -a _candidates=()
  local _f _lineno _content
  for _f in "${_domain_files[@]}"; do
    while IFS=: read -r _lineno _content; do
      [ -z "${_lineno}" ] && continue
      _is_make_c_candidate "${_content}" || continue
      # comment line: only whitespace then '#' after the line number
      [[ "${_content}" =~ ^[[:space:]]*# ]] && continue
      # @test description line -- this Case's own @test line literally
      # contains the phrase "make -C invocation"
      [[ "${_content}" =~ ^@test ]] && continue
      # bypass 5: a grep-led line checking a mock call log, not performing
      # a real invocation -- UNLESS it does so via command or process
      # substitution
      if [[ "${_content}" =~ ^[[:space:]]*grep[[:space:]] ]] \
        && [[ "${_content}" != *'$('* ]] \
        && [[ "${_content}" != *'<('* ]] \
        && [[ "${_content}" != *'`'* ]]; then
        continue
      fi
      _candidates+=("${_f}:${_lineno}:${_content}")
    done < <(_join_continuations "${_f}")
  done
  [ "${#_candidates[@]}" -gt 0 ]

  local _guarded=0 _measuring=0 _neither=0 _c _rest _content _seg
  for _c in "${_candidates[@]}"; do
    # "file:lineno:content" -- content itself may contain colons, so only
    # the first two fields (file, lineno) are stripped off, not split on
    # every colon.
    _rest="${_c#*:}"
    _content="${_rest#*:}"
    # bypass 4: reclassify per `;`/`&&`/`|`-delimited segment, not per whole
    # line, so a second invocation sharing a line with a guarded first one
    # cannot hide behind the first one's guard.
    while IFS= read -r _seg; do
      _is_make_c_candidate "${_seg}" || continue
      if [[ "${_seg}" == *"--no-print-directory"* ]]; then
        _guarded=$((_guarded + 1))
      elif [[ "${_seg}" == *"env -u MAKEFLAGS"* || "${_seg}" =~ ${_EMPTY_MAKEFLAGS_RE} ]]; then
        _measuring=$((_measuring + 1))
      else
        _neither=$((_neither + 1))
        printf 'neither guarded nor measuring: %s -- segment: %s\n' "${_c}" "${_seg}" >&2
      fi
    done < <(PATH="${CLEAN_PATH}" sed -E 's/(&&|\|\||;|\|)/\n/g' <<< "${_content}")
  done
  printf 'domain_files=%s candidates=%s guarded=%s measuring=%s neither=%s\n' \
    "${#_domain_files[@]}" "${#_candidates[@]}" "${_guarded}" "${_measuring}" "${_neither}" >&2

  [ "${_neither}" -eq 0 ]
  [ "${_guarded}" -gt 0 ]
  [ "${_measuring}" -gt 0 ]
}

# Case 6: Makefile:81 in the plan's own numbering (Makefile:91 in the current
# file -- the plan was written against an earlier line count) is
# `test: lint test-python`. A plan or a later edit that trims the
# prerequisite list to just `lint` would silently drop the Python suite from
# `make test` while `make test` itself kept exiting 0 -- this guards that the
# dependency survives, independent of which line number it lives on.
@test "test still depends on both lint and test-python" {
  grep -qE '^test:[[:space:]]+.*\blint\b' "${REPO_ROOT}/Makefile"
  grep -qE '^test:[[:space:]]+.*\btest-python\b' "${REPO_ROOT}/Makefile"
}
