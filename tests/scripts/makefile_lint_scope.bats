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
  # own `env -u MAKEFLAGS` load-bearing rather than decorative. Case 5
  # normalizes its own MAKEFLAGS explicitly instead, per-call -- see its
  # comment for why it needs a different mechanism.
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
  [ -n "${output}" ]
  # bats strips $output's trailing newline, so `printf '%s\n' "$output" | wc -l`
  # floors at 1 even for genuinely empty output -- `wc -l` cannot see the
  # difference between "one line" and "no output at all". The `lines` array
  # bats also populates has no such floor: it is length 0 for empty output.
  _lt4_count="${#lines[@]}"

  run env -u MAKEFLAGS PATH="${CLEAN_PATH}" "${_make_ge4}" -C "${REPO_ROOT}" print-ZSH_FILES
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  _ge4_count="${#lines[@]}"

  # Equality alone would also pass if both arms emitted nothing -- assert
  # nonzero (via lines[], which is genuinely 0 for empty output, unlike
  # wc -l above) first so a vacuous pass can't hide behind the equality
  # check.
  [ "${_lt4_count}" -gt 0 ]
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
# MAKEFLAGS directive exists to fix. This case's own `env -u MAKEFLAGS` is
# load-bearing too, but by a different, complementary mechanism to Case 1's:
# this is a single *asymmetric* check, not a two-arm comparison, so a leaked
# MAKEFLAGS that this guard fails to strip would pollute its one arm
# directly -- the >=4 make's directory lines would end up inside `$output`
# and the exact string match would fail (red), not pass unnoticed (blind),
# which is the opposite failure mode from Case 1's symmetric masking.
# Mutation-checked directly, though only from the Makefile side: with the
# Makefile directive removed, Case 1's `env -u` also removed, and an ambient
# leaked MAKEFLAGS present, this case (its own `env -u` left intact) still
# caught the missing directive and went red while Case 1 stayed green blind
# -- proving this guard is doing real, case-specific work. Each case's own
# `env -u MAKEFLAGS` protects that case alone; neither is a canary for the
# other, and no case's guard substitutes for another's.
@test "print-BATS_MISSING returns the exact configured message under a >=4 make" {
  local _make_ge4 _expected
  _make_ge4="$(_find_make_ge4)" \
    || skip "no >=4 arm: no make/gmake >=4 found on PATH"

  run env -u MAKEFLAGS PATH="${CLEAN_PATH}" "${_make_ge4}" -C "${REPO_ROOT}" print-BATS_MISSING
  [ "${status}" -eq 0 ]
  _expected="bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux). Durable fix: ./setup_env.sh -t setup_user (full provisioning re-run)"
  [ "${output}" = "${_expected}" ]
}

# Case 5 (numbered per the plan -- 3/4/6 belong to a later task): a control,
# not a canary for the other cases. It establishes the baseline Case 1 and
# Case 2 depend on -- that a directive-free Makefile run under a >=4 make,
# with nothing suppressing the output, genuinely shows "Entering directory" /
# "Leaving directory". Unlike Case 1/2, this deliberately does NOT prefix its
# make invocation with `env -u MAKEFLAGS`. It instead sets `MAKEFLAGS=` to an
# explicit empty value -- "inherited", per the plan, meaning the parent's
# MAKEFLAGS is left alone rather than stripped, while THIS invocation is
# normalized to the value a genuinely clean environment would have. That
# normalization guards this case's own baseline only; it says nothing about,
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
