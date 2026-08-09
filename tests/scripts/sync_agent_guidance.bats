#!/usr/bin/env bats

load '../helpers/common.bash'

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

@test "sync-agent-guidance.sh -h prints usage and exits 0" {
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "sync-agent-guidance.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "sync-agent-guidance.sh check exits 1 when CLAUDE.md is missing" {
  rm -f "${_OVERRIDE_CLAUDE_MD_PATH}"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required file"* ]]
  [[ "$output" != *"drift"* ]]
}

@test "sync-agent-guidance.sh check exits 1 when an imported standard file is missing" {
  rm -f "${_OVERRIDE_STANDARDS_DIR}/shell.md"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing imported standard"* ]]
}

@test "sync-agent-guidance.sh sync overwrites previous content rather than appending" {
  bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  grep -q "Use shellcheck\." "${_OVERRIDE_TARGET_PATH}"

  printf '## Shell Scripts\n\nUse shfmt instead.\n' > "${_OVERRIDE_STANDARDS_DIR}/shell.md"
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 0 ]

  grep -q "Use shfmt instead\." "${_OVERRIDE_TARGET_PATH}"
  refute_grep "Use shellcheck\." "${_OVERRIDE_TARGET_PATH}"
}

@test "sync-agent-guidance.sh sync writes multiple imported standards in order" {
  printf '## PowerShell\n\nUse PSScriptAnalyzer.\n' > "${_OVERRIDE_STANDARDS_DIR}/powershell.md"
  printf '# CLAUDE.md\n\n@~/.claude/standards/shell.md\n@~/.claude/standards/powershell.md\n' \
    > "${_OVERRIDE_CLAUDE_MD_PATH}"

  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  [ "$status" -eq 0 ]

  grep -q "Use shellcheck\." "${_OVERRIDE_TARGET_PATH}"
  grep -q "Use PSScriptAnalyzer\." "${_OVERRIDE_TARGET_PATH}"

  local shell_line powershell_line
  shell_line="$(grep -n "standards/shell.md\`" "${_OVERRIDE_TARGET_PATH}" | tail -1 | cut -d: -f1)"
  powershell_line="$(grep -n "standards/powershell.md\`" "${_OVERRIDE_TARGET_PATH}" | tail -1 | cut -d: -f1)"
  [ "${shell_line}" -lt "${powershell_line}" ]
}

@test "sync-agent-guidance.sh check is idempotent and does not mutate the target" {
  bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" sync
  local first_sum
  first_sum="$(shasum "${_OVERRIDE_TARGET_PATH}")"

  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 0 ]
  run bash "${REPO_ROOT}/scripts/sync-agent-guidance.sh" check
  [ "$status" -eq 0 ]

  local second_sum
  second_sum="$(shasum "${_OVERRIDE_TARGET_PATH}")"
  [ "${first_sum}" = "${second_sum}" ]
}
