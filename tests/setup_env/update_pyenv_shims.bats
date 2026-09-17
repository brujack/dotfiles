#!/usr/bin/env bats

# Covers run_update's pyenv-shims section (lib/workflows.sh) and its
# _UPDATE_SECTION_ORDER entry (lib/update_summary.sh).
#
# See docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md,
# Part 2: brew upgrade pyenv (macOS/Linux) is what can retire
# install_pyenv_rehash_hook's fix for the uutils sort -u collation defect,
# and that happens inside -t update -- so the check has to run in the same
# command that can break it, not only at setup_user time. (pyenv update
# itself runs only inside setup_ansible, lib/developer.sh, reached by
# -t developer/-t ansible -- not by -t update. The brew half alone is why
# this section belongs here.) The section runs whenever brew or pip might
# have run (_run_all || UPDATE_BREW || UPDATE_PIP), and resolves pyenv
# itself rather than relying on the pip block's exports, because under
# --brew-only the pip block never runs at all.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  # PYENV_ROOT is exported by this developer session's own pyenv shell
  # integration and is checked BEFORE HOME in every fallback chain the
  # functions under test use -- a missing unset here reaches the operator's
  # real ~/.pyenv (tdd.md E2).
  unset PYENV_ROOT
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  # bats sets BATS_TEST_TMPDIR but leaves TMPDIR at the system temp dir;
  # run_update's _dotfiles_run_tmpdir_setup uses TMPDIR, so without this
  # every invocation leaks a real dotfiles-run.* dir there.
  export TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MACOS=1
  unset LINUX UBUNTU HAS_AWS HAS_DEVTOOLS
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  # Every test below points this at a fixture root explicitly (via
  # _make_venv_bin, or left absent for the no-venv case) -- it is set here
  # only so a test that forgets to call _make_venv_bin fails closed on "no
  # ansible venv" rather than silently resolving the operator's real one.
  export _OVERRIDE_PYENV_ROOT="${BATS_TEST_TMPDIR}/pyenv_root"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Builds versions/ansible/bin and shims under _OVERRIDE_PYENV_ROOT, matching
# _pyenv_ansible_venv_bin's resolution (lib/helpers.sh).
_make_venv_bin() {
  mkdir -p "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin" "${_OVERRIDE_PYENV_ROOT}/shims"
}

# Rewrites PATH so `pyenv` genuinely cannot be found -- WITHOUT removing any
# other mock, most critically tests/mocks/git. Stripping tests/mocks wholesale
# (this file's first attempt) removes the git mock along with pyenv, so
# ensure_state_ledger's `git clone` (called by every run_update, unconditionally,
# before any flag gate) stops being intercepted and clones the REAL
# git@github.com:brujack/state-ledger.git; the ledger.py it clones then
# symlinks a REAL, fully-functional `ledger` to ${HOME}/.local/bin/ledger
# (HOME redirected, but the clone's git remote is not), and ledger_write_entry
# finds and runs it for real. Reproduced and confirmed live: this shape
# pushed two throwaway entries to the real repo's main branch (b6ebd86,
# 624c6f9) before being caught. Never repeat the wholesale-strip form.
#
# Builds a shim dir holding a symlink to every OTHER file in tests/mocks/,
# prepends it, and then walks the REST of PATH excluding tests/mocks itself
# and any directory that contains a file literally named pyenv -- so
# git/ledger/curl/etc. all still resolve to their mocks (from the shim dir,
# or from wherever they already lived on PATH), and only pyenv is genuinely
# absent. A name-pattern filter (e.g. grep -v '\.pyenv') is NOT enough: this
# machine's real pyenv is a plain Homebrew install at /opt/homebrew/bin,
# which matches no ".pyenv"-shaped pattern at all and was found anyway on
# the first version of this helper.
_path_without_pyenv() {
  local _shim_dir="${BATS_TEST_TMPDIR}/mocks_no_pyenv"
  mkdir -p "${_shim_dir}"
  local _f _name
  for _f in "${REPO_ROOT}/tests/mocks"/*; do
    _name="$(basename "${_f}")"
    [[ "${_name}" == "pyenv" ]] && continue
    ln -sf "${_f}" "${_shim_dir}/${_name}"
  done
  local _dir _out="${_shim_dir}"
  while IFS= read -r _dir; do
    [[ -z "${_dir}" ]] && continue
    [[ "${_dir}" == "${REPO_ROOT}/tests/mocks" ]] && continue
    [[ -e "${_dir}/pyenv" ]] && continue
    _out="${_out}:${_dir}"
  done < <(printf '%s' "${PATH}" | tr ':' '\n')
  printf '%s' "${_out}"
}

# ── (a) call order: hook install before pyenv rehash ──────────────────────

@test "pyenv-shims: installs the rehash hook before running pyenv rehash" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_PIP=1
  # A presence-only assertion (both lines appear in MOCK_CALLS_FILE) passes
  # on the broken order too -- assert relative line position instead.
  install_pyenv_rehash_hook() { printf 'hook-install\n' >> "${MOCK_CALLS_FILE}"; }
  run_update
  local _hook_line _rehash_line
  _hook_line="$(grep -n '^hook-install$' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  _rehash_line="$(grep -n '^pyenv rehash$' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  [ -n "${_hook_line}" ]
  [ -n "${_rehash_line}" ]
  [ "${_hook_line}" -lt "${_rehash_line}" ]
}

# ── (b) a failing rehash is non-fatal ──────────────────────────────────────

@test "pyenv-shims: a failing pyenv rehash still reaches the missing-shim check and does not FAIL the section" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_PIP=1
  export MOCK_PYENV_EXIT=1
  run_update
  # The rehash genuinely ran (not merely skipped because pyenv couldn't be
  # resolved) and its non-zero rc reaches the SUMMARY's detail block via
  # _update_write_detail_from_err -- asserting on the scratch err_ file
  # directly (as this test did before) still passes with that call deleted,
  # since the tee/printf lines write it regardless of whether anything ever
  # promotes it into detail_pyenv-shims, which is the only copy the
  # rendered summary and ~/.dotfiles-update.log ever read.
  grep -q '^pyenv rehash$' "${MOCK_CALLS_FILE}"
  [ -f "${_DOTFILES_RUN_TMPDIR}/detail_pyenv-shims" ]
  grep -q 'exited 1' "${_DOTFILES_RUN_TMPDIR}/detail_pyenv-shims"
  # Not fatal: the section's own status is never FAIL from a rehash failure
  # alone (venv is fully shimmed here, so there is nothing to WARN about
  # either -- this asserts specifically that record_end forced rc 0).
  refute_grep '^FAIL$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
}

@test "pyenv-shims: pyenv not found on PATH WARNs instead of silently rendering OK" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_PIP=1
  # DRY_RUN=1 is defense in depth, not the isolation mechanism itself: it
  # short-circuits ledger_write_entry's push specifically, on top of (not
  # instead of) _path_without_pyenv keeping the git mock in place -- see
  # that helper's comment for why the git mock is the part that actually
  # matters here.
  export DRY_RUN=1
  export PATH
  PATH="$(_path_without_pyenv)"
  run_update
  grep -q '^WARN$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q 'pyenv not found' "${_DOTFILES_RUN_TMPDIR}/result_pyenv-shims"
  [ -f "${_DOTFILES_RUN_TMPDIR}/detail_pyenv-shims" ]
}

# ── (c) WARN naming a missing shim ─────────────────────────────────────────

@test "pyenv-shims: WARNs and names a missing shim" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  # Deliberately no shims/pytest, and deliberately NOT MOCK_PYENV_REHASH_LINKS
  # -- the mock's rehash performs no real linking here by design, so this
  # case is a WARN whether the missing-shim check runs before OR after the
  # rehash (tdd.md E5: a post-condition satisfiable by more than one state
  # cannot discriminate between them). Its job is to pin the WARN's CONTENT
  # (status + the shim's name), not the ordering -- ordering is pinned
  # separately, by the call-order test above and by the
  # MOCK_PYENV_REHASH_LINKS case below, which goes red under the broken
  # order specifically because it is NOT inert. Do not "fix" this case by
  # turning MOCK_PYENV_REHASH_LINKS on; that would invert which order it
  # tolerates rather than which order it requires.
  export UPDATE_PIP=1
  run_update
  grep -q '^WARN$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q 'pytest' "${_DOTFILES_RUN_TMPDIR}/result_pyenv-shims"
}

@test "pyenv-shims: the rehash itself links the missing shim, proving it runs before the check" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  # shims/pytest does not exist yet. MOCK_PYENV_REHASH_LINKS=1 makes the
  # mock's own `pyenv rehash` create it -- so this only passes if the
  # section rehashes BEFORE checking for missing shims. Reordering the
  # check ahead of the rehash (the class of bug the call-order test above
  # pins structurally) makes this go red on the OUTCOME as well, because
  # the check would then run before the shim exists.
  [ ! -e "${_OVERRIDE_PYENV_ROOT}/shims/pytest" ]
  export MOCK_PYENV_REHASH_LINKS=1
  export UPDATE_PIP=1
  run_update
  [ -e "${_OVERRIDE_PYENV_ROOT}/shims/pytest" ]
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
}

@test "pyenv-shims: an ansible venv that vanishes between the SKIP gate and the check WARNs by name, not OK" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_PIP=1
  # _pyenv_missing_shims returns rc 2 with EMPTY stdout for "no venv" --
  # identical to its empty-stdout "nothing missing" case. Stubbing it
  # directly is the only way to reach that branch deterministically; the
  # real function's rc 2 is otherwise gated out by the SKIP check at
  # _pyenv_shims_bin before _update_record_start even runs.
  #
  # Called as `run_update || true`, not bare -- bats runs test bodies under
  # `set -e`, and a bare `x="$(stubbed_fn)"` assignment where the stub
  # returns 2 aborts the calling shell at that line (bash's own errexit
  # behaviour for a failing command substitution used as an assignment's
  # RHS -- verified: `bash -c 'set -e; f(){ return 2; }; x="$(f)"; echo
  # unreached'` exits without printing). `run run_update` would dodge that
  # too, but bats forks it into a subshell, and _DOTFILES_RUN_TMPDIR
  # (exported inside run_update) never makes it back -- verified the same
  # way: the grep below fails on an empty path. `|| true` on the bare call
  # protects the whole chain (a function's internal errexit is suppressed
  # when the call itself sits in a checked context) while staying in this
  # shell. Production is unaffected either way: lib/workflows.sh declares
  # no `set -e` of its own (shell.md).
  _pyenv_missing_shims() { return 2; }
  run_update || true
  grep -q '^WARN$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q 'disappeared' "${_DOTFILES_RUN_TMPDIR}/result_pyenv-shims"
}

@test "pyenv-shims: rehashes and checks the SAME root the hook was installed into, not a hardcoded HOME/.pyenv" {
  # P1 regression pin. Deliberately does NOT set _OVERRIDE_PYENV_ROOT --
  # that wins in every resolution call the dotfiles helpers make and would
  # mask this bug entirely, since it is never touched by the mutation
  # below. The bug lived in a hardcoded `export PYENV_ROOT="$HOME/.pyenv"`
  # that silently retargeted every call AFTER it (PATH, the rehash, the
  # missing-shim check) at a root the hook was never installed into and
  # this fixture's venv never lived in.
  #
  # pyenv itself is placed ONLY inside the fixture root's own bin/. PATH is
  # rewritten via _path_without_pyenv (git/ledger/etc. mocks preserved --
  # see that helper's comment for why a wholesale strip is dangerous) plus
  # every real .pyenv dir this developer session's shell already carries
  # removed -- so this also catches the degenerate "fix" of simply deleting
  # the two export lines: without a correctly exported PATH prepend,
  # `command -v pyenv` would find nothing at all (there is nothing else on
  # PATH named pyenv to fall back to), and the section would WARN "pyenv
  # not found", not "missing shim(s)".
  local _real_root="${BATS_TEST_TMPDIR}/real_pyenv"
  mkdir -p "${_real_root}/versions/ansible/bin" "${_real_root}/bin"
  : > "${_real_root}/versions/ansible/bin/pytest"
  cp "${REPO_ROOT}/tests/mocks/pyenv" "${_real_root}/bin/pyenv"
  chmod +x "${_real_root}/bin/pyenv"
  # DRY_RUN=1 is defense in depth on top of _path_without_pyenv, not a
  # substitute for it -- see the WARN test above for why both matter.
  export DRY_RUN=1
  export PATH
  PATH="$(_path_without_pyenv)"
  unset _OVERRIDE_PYENV_ROOT
  export PYENV_ROOT="${_real_root}"
  export UPDATE_PIP=1
  run_update
  grep -q '^WARN$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q 'pytest' "${_DOTFILES_RUN_TMPDIR}/result_pyenv-shims"
}

# ── (d) OK when nothing is missing ─────────────────────────────────────────

@test "pyenv-shims: OK when the venv bin is fully shimmed" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_PIP=1
  run_update
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
}

# ── (e) SKIP when there is no ansible venv ─────────────────────────────────

@test "pyenv-shims: SKIPs 'no ansible venv' when the venv bin does not exist" {
  # _OVERRIDE_PYENV_ROOT points at a root with no versions/ansible/bin at all.
  export UPDATE_PIP=1
  run_update
  grep -q '^SKIP$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q 'no ansible venv' "${_DOTFILES_RUN_TMPDIR}/result_pyenv-shims"
}

# ── (f) SKIP under --gems-only ──────────────────────────────────────────────

@test "pyenv-shims: SKIPs 'flag not set' under --gems-only" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_GEMS=1
  run_update
  grep -q '^SKIP$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q 'flag not set' "${_DOTFILES_RUN_TMPDIR}/result_pyenv-shims"
}

# ── (g) runs under --brew-only, where the pip block never runs ────────────

@test "pyenv-shims: runs under --brew-only, where the pip block is skipped" {
  # This does NOT prove the block's own PATH prepend is what resolves
  # pyenv -- load_mocks already puts tests/mocks on PATH regardless of
  # anything this section exports, so `command -v pyenv` would succeed here
  # even with the export/PATH lines deleted outright. What it pins is
  # narrower and still real: that the section RUNS AT ALL (calls rehash)
  # under --brew-only, which is the reason it has its own
  # `|| UPDATE_BREW` disjunct rather than living inside the run_all-only
  # block below it. The P1 regression-pin test separately isolates PATH so
  # resolution genuinely depends on this section's own export.
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  : > "${_OVERRIDE_PYENV_ROOT}/shims/pytest"
  export UPDATE_BREW=1
  unset UPDATE_PIP
  run_update
  # The pip block itself is skipped -- this is the case the block placement
  # (after pip, gated on _run_all || UPDATE_BREW || UPDATE_PIP) exists for.
  grep -q '^SKIP$' "${_DOTFILES_RUN_TMPDIR}/status_pip"
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q '^pyenv rehash$' "${MOCK_CALLS_FILE}"
}
