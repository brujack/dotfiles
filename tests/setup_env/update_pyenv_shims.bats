#!/usr/bin/env bats

# Covers run_update's pyenv-shims section (lib/workflows.sh) and its
# _UPDATE_SECTION_ORDER entry (lib/update_summary.sh).
#
# See docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md,
# Part 2: brew upgrade pyenv (macOS/Linux) and pyenv update (a clone) are
# both events that can retire install_pyenv_rehash_hook's fix for the
# uutils sort -u collation defect, and both happen inside -t update -- so
# the check has to run in the same command that can break it, not only at
# setup_user time. The section runs whenever brew or pip might have run
# (_run_all || UPDATE_BREW || UPDATE_PIP), and resolves pyenv itself rather
# than relying on the pip block's exports, because under --brew-only the
# pip block never runs at all.

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
  # resolved) and its non-zero rc is recorded in the section's err file.
  grep -q '^pyenv rehash$' "${MOCK_CALLS_FILE}"
  grep -q 'exited 1' "${_DOTFILES_RUN_TMPDIR}/err_pyenv-shims"
  # Not fatal: the section's own status is never FAIL from a rehash failure
  # alone (venv is fully shimmed here, so there is nothing to WARN about
  # either -- this asserts specifically that record_end forced rc 0).
  refute_grep '^FAIL$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_pyenv-shims"
}

# ── (c) WARN naming a missing shim ─────────────────────────────────────────

@test "pyenv-shims: WARNs and names a missing shim" {
  _make_venv_bin
  : > "${_OVERRIDE_PYENV_ROOT}/versions/ansible/bin/pytest"
  # Deliberately no shims/pytest -- the mock pyenv rehash performs no real
  # linking, so this stays missing through the whole run.
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

@test "pyenv-shims: runs and resolves pyenv under --brew-only, where the pip block is skipped" {
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
