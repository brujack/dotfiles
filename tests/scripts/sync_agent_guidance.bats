#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WORKDIR="${BATS_TEST_TMPDIR}/sync-agent-guidance"
  mkdir -p "${WORKDIR}/standards"

  export _OVERRIDE_CLAUDE_MD_PATH="${WORKDIR}/CLAUDE.md"
  export _OVERRIDE_STANDARDS_DIR="${WORKDIR}/standards"
  export _OVERRIDE_TARGET_PATH="${WORKDIR}/global-claude-standards.mdc"

  printf '# CLAUDE.md\n\n@~/.claude/standards/shell.md\n' > "${_OVERRIDE_CLAUDE_MD_PATH}"
  printf '## Shell Scripts\n\nUse shellcheck.\n' > "${_OVERRIDE_STANDARDS_DIR}/shell.md"
}

teardown() {
  unset _OVERRIDE_CLAUDE_MD_PATH _OVERRIDE_STANDARDS_DIR _OVERRIDE_TARGET_PATH
}

@test "sync-agent-guidance.sh exits 1 and prints usage when no mode given" {
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "sync-agent-guidance.sh exits 1 and prints usage for an unknown mode" {
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "sync-agent-guidance.sh sync generates the target file with imported standard content" {
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 0 ]
  [ -f "${_OVERRIDE_TARGET_PATH}" ]
  grep -q "alwaysApply: true" "${_OVERRIDE_TARGET_PATH}"
  grep -q "Use shellcheck." "${_OVERRIDE_TARGET_PATH}"
}

@test "sync-agent-guidance.sh sync is idempotent across repeated runs" {
  bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  local first_sum
  first_sum="$(shasum "${_OVERRIDE_TARGET_PATH}")"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 0 ]
  local second_sum
  second_sum="$(shasum "${_OVERRIDE_TARGET_PATH}")"
  [ "${first_sum}" = "${second_sum}" ]
}

@test "sync-agent-guidance.sh check exits 0 when target already matches source" {
  bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]]
}

@test "sync-agent-guidance.sh check exits 1 when target is missing" {
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"* ]]
}

@test "sync-agent-guidance.sh check exits 1 when source standard changed after last sync" {
  bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  printf '## Shell Scripts\n\nUse shellcheck and bash -n.\n' > "${_OVERRIDE_STANDARDS_DIR}/shell.md"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"* ]]
}

@test "sync-agent-guidance.sh sync fails when CLAUDE.md is missing" {
  rm -f "${_OVERRIDE_CLAUDE_MD_PATH}"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 1 ]
}

@test "sync-agent-guidance.sh sync fails when an imported standard file is missing" {
  rm -f "${_OVERRIDE_STANDARDS_DIR}/shell.md"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 1 ]
}

@test "sync-agent-guidance.sh sync fails when CLAUDE.md has no standards imports" {
  printf '# CLAUDE.md\n\nNo imports here.\n' > "${_OVERRIDE_CLAUDE_MD_PATH}"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 1 ]
}
