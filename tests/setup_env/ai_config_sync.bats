#!/usr/bin/env bats

# setup_ai_config against real git: a bare origin, the checkout under test, and a
# peer clone that pushes upstream changes. tests/mocks/git cannot model a pull.

load '../helpers/common.bash'

setup() {
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example.com"
  export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example.com"
  ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  PEER="${BATS_TEST_TMPDIR}/peer"
  git init -q --bare -b master "${ORIGIN}"
  git clone -q "${ORIGIN}" "${_OVERRIDE_AI_CONFIG_DIR}" 2>/dev/null
  printf '{"a": 1}\n' > "${_OVERRIDE_AI_CONFIG_DIR}/settings.json"
  printf 'notes\n' > "${_OVERRIDE_AI_CONFIG_DIR}/notes.md"
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" add . && git -C "${_OVERRIDE_AI_CONFIG_DIR}" commit -q -m base
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" push -q -u origin master
  git clone -q "${ORIGIN}" "${PEER}"
}

# Pushes an upstream change to FILE from the peer clone.
_upstream_change() {
  printf '%s\n' "$2" > "${PEER}/$1"
  git -C "${PEER}" commit -q -am "upstream $1" && git -C "${PEER}" push -q origin master
}

# Claude Code writes settings.json through its symlink, so a dirty settings.json is
# routine; an upstream change to the same file made the autostash pop conflict, and
# pull exited 0 with conflict markers in the file.
@test "test_bug_ai_config_autostash: overlapping local edits are left untouched and not pulled" {
  _upstream_change settings.json '{"a": 2}'
  printf '{"a": "local"}\n' > "${_OVERRIDE_AI_CONFIG_DIR}/settings.json"
  local _head_before
  _head_before="$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)"

  run setup_ai_config
  [ "$status" -eq 2 ]
  [ "$(cat "${_OVERRIDE_AI_CONFIG_DIR}/settings.json")" = '{"a": "local"}' ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "${_head_before}" ]
  [ -z "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" stash list)" ]
  [[ "$output" == *"settings.json"* ]]
}

@test "test_bug_ai_config_autostash: disjoint local edits are kept and the pull still happens" {
  _upstream_change notes.md 'upstream notes'
  printf '{"a": "local"}\n' > "${_OVERRIDE_AI_CONFIG_DIR}/settings.json"

  run setup_ai_config
  [ "$status" -eq 0 ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
  [ "$(cat "${_OVERRIDE_AI_CONFIG_DIR}/notes.md")" = "upstream notes" ]
  [ "$(cat "${_OVERRIDE_AI_CONFIG_DIR}/settings.json")" = '{"a": "local"}' ]
}

@test "test_bug_ai_config_autostash: a clean checkout fast-forwards" {
  _upstream_change settings.json '{"a": 2}'

  run setup_ai_config
  [ "$status" -eq 0 ]
  [ "$(cat "${_OVERRIDE_AI_CONFIG_DIR}/settings.json")" = '{"a": 2}' ]
}

# git -C does not override an exported GIT_DIR: the pull went to that repo instead.
@test "test_bug_ai_config_rm_rf: a leaked GIT_DIR does not redirect the pull" {
  _upstream_change notes.md 'upstream notes'
  local _decoy="${BATS_TEST_TMPDIR}/decoy"
  git init -q -b master "${_decoy}"
  git -C "${_decoy}" commit -q --allow-empty -m decoy

  GIT_DIR="${_decoy}/.git" run setup_ai_config
  [ "$status" -eq 0 ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
}

# Rename detection lists only the new path, so a staged rename plus an edit hid the
# overlap with an upstream edit to the old path, and the autostash pop conflicted.
@test "test_bug_ai_config_autostash: a staged rename of a file upstream edited counts as overlap" {
  # Twenty lines, one edited on each side, so git still pairs the rename.
  seq 1 20 > "${_OVERRIDE_AI_CONFIG_DIR}/notes.md"
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" commit -q -am "long notes"
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" push -q origin master
  git -C "${PEER}" pull -q
  sed 's/^10$/upstream ten/' "${PEER}/notes.md" > "${PEER}/notes.tmp" && mv "${PEER}/notes.tmp" "${PEER}/notes.md"
  git -C "${PEER}" commit -q -am "upstream notes" && git -C "${PEER}" push -q origin master
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" mv notes.md renamed.md
  sed 's/^10$/local ten/' "${_OVERRIDE_AI_CONFIG_DIR}/renamed.md" > "${BATS_TEST_TMPDIR}/r.tmp"
  mv "${BATS_TEST_TMPDIR}/r.tmp" "${_OVERRIDE_AI_CONFIG_DIR}/renamed.md"
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" add renamed.md
  local _head_before
  _head_before="$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)"

  run setup_ai_config
  [ "$status" -eq 2 ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "${_head_before}" ]
  [ "$(grep -c '^<<<<<<<' "${_OVERRIDE_AI_CONFIG_DIR}/renamed.md")" -eq 0 ]
  grep -qx 'local ten' "${_OVERRIDE_AI_CONFIG_DIR}/renamed.md"
  [[ "$output" == *"notes.md"* ]]
}

# Each of the four variables redirects git on its own (dotfiles#380, #381), so each
# gets a leak test of its own: the real checkout must reach origin's HEAD, and where
# the leak would write into the decoy (work tree, index) the decoy is checked too.
_make_decoy() {
  DECOY="${BATS_TEST_TMPDIR}/decoy"
  git init -q -b master "${DECOY}"
  printf 'decoy\n' > "${DECOY}/decoy.txt"
  git -C "${DECOY}" add decoy.txt && git -C "${DECOY}" commit -q -m decoy
}

@test "test_bug_ai_config_rm_rf: a leaked GIT_COMMON_DIR does not redirect the fetch or pull" {
  _upstream_change notes.md 'upstream notes'
  _make_decoy

  GIT_COMMON_DIR="${DECOY}/.git" run setup_ai_config
  [ "$status" -eq 0 ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
}

@test "test_bug_ai_config_rm_rf: a leaked GIT_WORK_TREE does not write upstream files into it" {
  _upstream_change notes.md 'upstream notes'
  _make_decoy

  GIT_WORK_TREE="${DECOY}" run setup_ai_config
  [ "$status" -eq 0 ]
  [ "$(cat "${_OVERRIDE_AI_CONFIG_DIR}/notes.md")" = "upstream notes" ]
  [ ! -e "${DECOY}/notes.md" ]
}

@test "test_bug_ai_config_rm_rf: a leaked GIT_INDEX_FILE is not rewritten" {
  _upstream_change notes.md 'upstream notes'
  _make_decoy
  cp "${DECOY}/.git/index" "${BATS_TEST_TMPDIR}/index.before"

  GIT_INDEX_FILE="${DECOY}/.git/index" run setup_ai_config
  [ "$status" -eq 0 ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
  cmp "${DECOY}/.git/index" "${BATS_TEST_TMPDIR}/index.before"
}

@test "test_bug_ai_config_rm_rf: ensure_state_ledger pulls its own checkout under a leaked GIT_DIR" {
  local _ledger="${BATS_TEST_TMPDIR}/ledger"
  git clone -q "${ORIGIN}" "${_ledger}"
  _upstream_change notes.md 'upstream notes'
  _make_decoy
  export _OVERRIDE_STATE_LEDGER_DIR="${_ledger}"

  GIT_DIR="${DECOY}/.git" run ensure_state_ledger
  [ "$status" -eq 0 ]
  [ "$(git -C "${_ledger}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
  [ -d "${_ledger}/.git" ]
}

@test "test_bug_ai_config_autostash: an upstream rename of a file edited locally counts as overlap" {
  seq 1 20 > "${_OVERRIDE_AI_CONFIG_DIR}/notes.md"
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" commit -q -am "long notes"
  git -C "${_OVERRIDE_AI_CONFIG_DIR}" push -q origin master
  git -C "${PEER}" pull -q
  git -C "${PEER}" mv notes.md moved.md
  sed 's/^3$/upstream three/' "${PEER}/moved.md" > "${PEER}/m.tmp" && mv "${PEER}/m.tmp" "${PEER}/moved.md"
  git -C "${PEER}" commit -q -am "upstream rename" && git -C "${PEER}" push -q origin master
  sed 's/^10$/local ten/' "${_OVERRIDE_AI_CONFIG_DIR}/notes.md" > "${BATS_TEST_TMPDIR}/n.tmp"
  mv "${BATS_TEST_TMPDIR}/n.tmp" "${_OVERRIDE_AI_CONFIG_DIR}/notes.md"
  local _head_before
  _head_before="$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)"

  run setup_ai_config
  [ "$status" -eq 2 ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "${_head_before}" ]
  grep -qx 'local ten' "${_OVERRIDE_AI_CONFIG_DIR}/notes.md"
}

# The audit's original scenario: a GIT_DIR pointing nowhere made rev-parse fail, so a
# healthy checkout read as invalid and was deleted. It must now be pulled in place.
@test "test_bug_ai_config_rm_rf: a GIT_DIR pointing nowhere does not move a healthy checkout aside" {
  _upstream_change notes.md 'upstream notes'

  GIT_DIR="${BATS_TEST_TMPDIR}/nonexistent/.git" run setup_ai_config
  [ "$status" -eq 0 ]
  local -a _aside=("${BATS_TEST_TMPDIR}"/ai-config.broken-*)
  [ ! -e "${_aside[0]}" ]
  [ "$(git -C "${_OVERRIDE_AI_CONFIG_DIR}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
}
