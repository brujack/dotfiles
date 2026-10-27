#!/usr/bin/env bats

# setup_ai_config against real git: a bare origin, the checkout under test, and a
# peer clone that pushes upstream changes. tests/mocks/git cannot model a pull.

load '../helpers/common.bash'

setup() {
  load_setup_env
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
