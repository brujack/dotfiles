#!/usr/bin/env bats

# _update_git_pull (the tfenv, oh-my-zsh, tpm and zsh-autosuggestions sections of
# -t update) against real git: a bare origin, the checkout under test, and a peer
# clone that pushes upstream commits. tests/mocks/git cannot model a pull.

load '../helpers/common.bash'

setup() {
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}/run"
  mkdir -p "${_DOTFILES_RUN_TMPDIR}"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example.com"
  export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example.com"
}

# _clone_with_upstream NAME DIR: clones a fresh origin into DIR, then pushes one
# commit (adding NAME.txt) from a peer, so a pull of DIR has exactly one commit to take.
_clone_with_upstream() {
  local _name="$1" _dir="$2"
  local _origin="${BATS_TEST_TMPDIR}/${_name}-origin.git" _peer="${BATS_TEST_TMPDIR}/${_name}-peer"
  git init -q --bare -b master "${_origin}"
  git clone -q "${_origin}" "${_peer}" 2>/dev/null
  git -C "${_peer}" commit -q --allow-empty -m base
  git -C "${_peer}" push -q -u origin master
  mkdir -p "$(dirname "${_dir}")"
  git clone -q "${_origin}" "${_dir}"
  printf '%s\n' "${_name}" > "${_peer}/${_name}.txt"
  git -C "${_peer}" add "${_name}.txt"
  git -C "${_peer}" commit -q -m "upstream ${_name}"
  git -C "${_peer}" push -q origin master
}

_origin_head() {
  git -C "${BATS_TEST_TMPDIR}/$1-origin.git" rev-parse master
}

# The decoy has a pullable upstream of its own, so a pull redirected into it exits 0
# and the section reads OK: the silent case, not a loud FAIL.
_make_decoy() {
  DECOY="${BATS_TEST_TMPDIR}/decoy"
  _clone_with_upstream decoy "${DECOY}"
  DECOY_HEAD="$(git -C "${DECOY}" rev-parse HEAD)"
}

# Each section's directory, as run_update passes it.
_section_dir() {
  case "$1" in
    tfenv) printf '%s' "${HOME}/.tfenv" ;;
    oh-my-zsh) printf '%s' "${HOME}/.oh-my-zsh" ;;
    tpm) printf '%s' "${HOME}/.tmux/plugins/tpm" ;;
    zsh-autosuggestions) printf '%s' "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ;;
  esac
}

# git -C does not override an exported GIT_DIR (dotfiles#380): the pull went to the
# decoy, rc 0, and the pre/post snapshots read the decoy too, so the row said OK.
_assert_gitdir_leak_contained() {
  local _section="$1" _dir
  _dir="$(_section_dir "${_section}")"
  _clone_with_upstream "${_section}" "${_dir}"
  _make_decoy

  GIT_DIR="${DECOY}/.git" run _update_git_pull "${_section}" "${_dir}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${_dir}" rev-parse HEAD)" = "$(_origin_head "${_section}")" ]
  [ "$(git -C "${DECOY}" rev-parse HEAD)" = "${DECOY_HEAD}" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_${_section}")" = "OK" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_${_section}")" = "1 commit(s)" ]
}

@test "test_bug_update_git_env: a leaked GIT_DIR does not redirect the tfenv pull or snapshot" {
  _assert_gitdir_leak_contained tfenv
}

@test "test_bug_update_git_env: a leaked GIT_DIR does not redirect the oh-my-zsh pull or snapshot" {
  _assert_gitdir_leak_contained oh-my-zsh
}

@test "test_bug_update_git_env: a leaked GIT_DIR does not redirect the tpm pull or snapshot" {
  _assert_gitdir_leak_contained tpm
}

@test "test_bug_update_git_env: a leaked GIT_DIR does not redirect the zsh-autosuggestions pull or snapshot" {
  _assert_gitdir_leak_contained zsh-autosuggestions
}

# Each of the other three variables redirects git on its own (dotfiles#381), so
# each gets its own test; one section stands for all four, which share the helper.
@test "test_bug_update_git_env: a leaked GIT_WORK_TREE does not receive the pulled files" {
  local _dir
  _dir="$(_section_dir tpm)"
  _clone_with_upstream tpm "${_dir}"
  _make_decoy

  GIT_WORK_TREE="${DECOY}" run _update_git_pull tpm "${_dir}"
  [ "$status" -eq 0 ]
  [ "$(cat "${_dir}/tpm.txt")" = "tpm" ]
  [ ! -e "${DECOY}/tpm.txt" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_tpm")" = "1 commit(s)" ]
}

@test "test_bug_update_git_env: a leaked GIT_COMMON_DIR does not redirect the pull or snapshot" {
  local _dir
  _dir="$(_section_dir tpm)"
  _clone_with_upstream tpm "${_dir}"
  _make_decoy

  GIT_COMMON_DIR="${DECOY}/.git" run _update_git_pull tpm "${_dir}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${_dir}" rev-parse HEAD)" = "$(_origin_head tpm)" ]
  [ "$(git -C "${DECOY}" rev-parse HEAD)" = "${DECOY_HEAD}" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_tpm")" = "1 commit(s)" ]
}

@test "test_bug_update_git_env: a leaked GIT_INDEX_FILE is not rewritten by the pull" {
  local _dir
  _dir="$(_section_dir tpm)"
  _clone_with_upstream tpm "${_dir}"
  _make_decoy
  cp "${DECOY}/.git/index" "${BATS_TEST_TMPDIR}/index.before"

  GIT_INDEX_FILE="${DECOY}/.git/index" run _update_git_pull tpm "${_dir}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${_dir}" rev-parse HEAD)" = "$(_origin_head tpm)" ]
  cmp "${DECOY}/.git/index" "${BATS_TEST_TMPDIR}/index.before"
}

# Without a .git of its own the directory resolves to the nearest ancestor checkout,
# here a HOME tracked in git, so the section pulled HOME and reported OK.
_assert_non_clone_skipped() {
  local _section="$1" _dir
  _dir="$(_section_dir "${_section}")"
  _clone_with_upstream home "${HOME}.tmp"
  mv "${HOME}.tmp/.git" "${HOME}/.git"
  local _home_head
  _home_head="$(git -C "${HOME}" rev-parse HEAD)"
  mkdir -p "${_dir}"

  run _update_git_pull "${_section}" "${_dir}"
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_${_section}")" = "SKIP" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_${_section}")" = "not a git checkout — reinstall to enable updates" ]
  [ "$(git -C "${HOME}" rev-parse HEAD)" = "${_home_head}" ]
}

@test "test_bug_update_git_env: a tfenv dir that is not a clone is skipped, not resolved to an ancestor" {
  _assert_non_clone_skipped tfenv
}

@test "test_bug_update_git_env: an oh-my-zsh dir that is not a clone is skipped, not resolved to an ancestor" {
  _assert_non_clone_skipped oh-my-zsh
}

@test "test_bug_update_git_env: a tpm dir that is not a clone is skipped, not resolved to an ancestor" {
  _assert_non_clone_skipped tpm
}
