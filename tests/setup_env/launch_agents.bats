#!/usr/bin/env bats
#
# `run !` (negated run) needs bats >= 1.5.0. Declared rather than assumed:
# without it bats only warns, and on an older bats the negation would be
# mis-parsed silently -- tdd.md pitfall G, where the local toolchain cannot
# express the failure. CI installs 1.10.0 via apt; this box has 1.14.0.
bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/lib/launch_agents.sh"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export _RHN_AGENT_DIR="${HOME}/Library/LaunchAgents"
  export _RHN_LAUNCHCTL="${BATS_TEST_TMPDIR}/fake-launchctl"
  export _RHN_LAUNCHCTL_LOG="${BATS_TEST_TMPDIR}/lctl.log"
  mkdir -p "${_RHN_AGENT_DIR}"
  cat > "${_RHN_LAUNCHCTL}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${_RHN_LAUNCHCTL_LOG}"
EOF
  chmod +x "${_RHN_LAUNCHCTL}"
  export _OVERRIDE_DOTFILES_ROOT="${REPO_ROOT}"
  export _OVERRIDE_AI_CONFIG_ROOT="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_ROOT}/.claude/scripts"
  : > "${_OVERRIDE_AI_CONFIG_ROOT}/.claude/scripts/renovate_held_check.py"
  : > "${_OVERRIDE_AI_CONFIG_ROOT}/.claude/scripts/ledger_drift_check.sh"
}

@test "installs the agent on the studio profile" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_renovate_held_agent
  [ "$status" -eq 0 ]
  [ -f "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist" ]
}

@test "the installed plist carries no unsubstituted placeholder" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_renovate_held_agent
  [ "$status" -eq 0 ]
  run ! command grep -q '__DOTFILES__\|__HOME__' "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist"
}

@test "the installed plist points at a script that exists" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_renovate_held_agent
  local _p
  _p=$(sed -n 's|.*<string>\(/.*cadence-notify.sh\)</string>.*|\1|p' \
       "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist")
  [ -n "${_p}" ]
  [ -x "${_p}" ]
}

@test "does NOT install on a non-studio machine" {
  export PROFILE="personal_laptop" HOSTNAME_SHORT="laptop"
  run install_renovate_held_agent
  [ "$status" -eq 0 ]
  [ ! -f "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist" ]
}

@test "installing twice leaves exactly one agent and reloads it" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_renovate_held_agent; [ "$status" -eq 0 ]
  run install_renovate_held_agent; [ "$status" -eq 0 ]
  [ "$(find "${_RHN_AGENT_DIR}" -name '*renovate-held*' | wc -l | tr -d ' ')" -eq 1 ]
  command grep -q 'unload' "${_RHN_LAUNCHCTL_LOG}"
  command grep -q 'load' "${_RHN_LAUNCHCTL_LOG}"
}

@test "unload precedes load on reinstall — never load onto a live agent" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_renovate_held_agent
  [ "$(command grep -n 'unload' "${_RHN_LAUNCHCTL_LOG}" | head -1 | cut -d: -f1)" -lt \
    "$(command grep -n ' load\|^load' "${_RHN_LAUNCHCTL_LOG}" | head -1 | cut -d: -f1)" ]
}

@test "installs the ledger-drift agent, making the workflow's deferral true" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_ledger_drift_agent
  [ "$status" -eq 0 ]
  [ -f "${_RHN_AGENT_DIR}/com.brucejackson.ledger-drift.plist" ]
  run ! command grep -q '__NAME__\|__DETECTOR__\|__MINUTE__\|__DOTFILES__\|__HOME__' \
      "${_RHN_AGENT_DIR}/com.brucejackson.ledger-drift.plist"
}

@test "the two agents are separate jobs on separate minutes" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  install_renovate_held_agent
  install_ledger_drift_agent
  [ "$(find "${_RHN_AGENT_DIR}" -name 'com.brucejackson.*.plist' | wc -l | tr -d ' ')" -eq 2 ]
  local _a _b
  _a=$(sed -n 's|.*<key>Minute</key><integer>\([0-9]*\)</integer>.*|\1|p' \
       "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist")
  _b=$(sed -n 's|.*<key>Minute</key><integer>\([0-9]*\)</integer>.*|\1|p' \
       "${_RHN_AGENT_DIR}/com.brucejackson.ledger-drift.plist")
  [ -n "${_a}" ] && [ -n "${_b}" ] && [ "${_a}" != "${_b}" ]
}

@test "each agent passes its own name and detector to the shared wrapper" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  install_ledger_drift_agent
  command grep -q '<string>ledger-drift</string>' \
    "${_RHN_AGENT_DIR}/com.brucejackson.ledger-drift.plist"
  command grep -q 'ledger_drift_check.sh' \
    "${_RHN_AGENT_DIR}/com.brucejackson.ledger-drift.plist"
}

@test "an absent detector still installs — the run reports incomplete, not nothing" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  rm -f "${_OVERRIDE_AI_CONFIG_ROOT}/.claude/scripts/renovate_held_check.py"
  run install_renovate_held_agent
  [ "$status" -eq 0 ]
  [ -f "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist" ]
  [[ "$output" == *"detector absent"* ]]
}

@test "every lib sourced by setup_env.sh exists — a rename must update both" {
  # A renamed lib left a stale source line in setup_env.sh and took 1012 tests
  # down at once. The failure was loud, but nothing pointed at the cause, and a
  # compound command's exit code reported the whole run as green.
  local _missing=0 _f
  while IFS= read -r _f; do
    [[ -f "${REPO_ROOT}/${_f}" ]] || { printf 'missing: %s\n' "${_f}"; _missing=1; }
  done < <(command grep -oE 'lib/[a-z_]+\.sh' "${REPO_ROOT}/setup_env.sh" | sort -u)
  [ "${_missing}" -eq 0 ]
}

@test "the installer refuses a name or minute that would break the sed expression" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run _la_install_agent 'has|pipe' "${_OVERRIDE_AI_CONFIG_ROOT}/.claude/scripts/x.sh" 7
  [ "$status" -ne 0 ]
  run _la_install_agent 'ok-name' "${_OVERRIDE_AI_CONFIG_ROOT}/.claude/scripts/x.sh" '9|evil'
  [ "$status" -ne 0 ]
  [ "$(find "${_RHN_AGENT_DIR}" -name '*.plist' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "a path containing sed-meta characters still substitutes correctly" {
  # `&` in a sed REPLACEMENT means "the whole match", so s|__X__|a&b| yields
  # a__X__b -- a valid-XML plist pointing at a nonexistent path, installed and
  # silently failing weekly. Verified against a real `&` in the root path.
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  local _weird="${BATS_TEST_TMPDIR}/a&b|c"
  mkdir -p "${_weird}/scripts" "${_weird}/LaunchAgents"
  cp "${REPO_ROOT}/LaunchAgents/cadence.plist.template" "${_weird}/LaunchAgents/"
  cp "${REPO_ROOT}/scripts/cadence-notify.sh" "${_weird}/scripts/"
  chmod +x "${_weird}/scripts/cadence-notify.sh"
  export _OVERRIDE_DOTFILES_ROOT="${_weird}"
  run install_renovate_held_agent
  [ "$status" -eq 0 ]
  local _p="${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist"
  run ! command grep -q '__' "${_p}"
  command grep -qF "${_weird}/scripts/cadence-notify.sh" "${_p}"
}

@test "a missing plist template is an install failure, not a silent skip" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  local _root="${BATS_TEST_TMPDIR}/noTemplate"
  mkdir -p "${_root}/scripts"
  cp "${REPO_ROOT}/scripts/cadence-notify.sh" "${_root}/scripts/"
  chmod +x "${_root}/scripts/cadence-notify.sh"
  export _OVERRIDE_DOTFILES_ROOT="${_root}"
  run install_renovate_held_agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"template missing"* ]]
  [ ! -f "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist" ]
}

@test "a notify script that exists but is not executable is an install failure" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  local _root="${BATS_TEST_TMPDIR}/noExec"
  mkdir -p "${_root}/scripts" "${_root}/LaunchAgents"
  cp "${REPO_ROOT}/LaunchAgents/cadence.plist.template" "${_root}/LaunchAgents/"
  cp "${REPO_ROOT}/scripts/cadence-notify.sh" "${_root}/scripts/"
  chmod 000 "${_root}/scripts/cadence-notify.sh"
  export _OVERRIDE_DOTFILES_ROOT="${_root}"
  run install_renovate_held_agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not executable"* ]]
  chmod 644 "${_root}/scripts/cadence-notify.sh"
}

@test "a surviving placeholder aborts the install and removes the partial plist" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  local _root="${BATS_TEST_TMPDIR}/badTemplate"
  mkdir -p "${_root}/scripts" "${_root}/LaunchAgents"
  cp "${REPO_ROOT}/scripts/cadence-notify.sh" "${_root}/scripts/"
  chmod +x "${_root}/scripts/cadence-notify.sh"
  # a placeholder nothing substitutes -- an agent pointing somewhere unresolved
  # must never be installed
  sed 's|<key>RunAtLoad</key>|<key>__NEVER_SUBSTITUTED__</key>|' \
    "${REPO_ROOT}/LaunchAgents/cadence.plist.template" > "${_root}/LaunchAgents/cadence.plist.template"
  export _OVERRIDE_DOTFILES_ROOT="${_root}"
  run install_renovate_held_agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"placeholder survived"* ]]
  [ ! -f "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist" ]
}

@test "install_ledger_drift_agent is a no-op on a non-cadence host" {
  export PROFILE="personal_laptop" HOSTNAME_SHORT="laptop"
  run install_ledger_drift_agent
  [ "$status" -eq 0 ]
  [ ! -f "${_RHN_AGENT_DIR}/com.brucejackson.ledger-drift.plist" ]
}

@test "the studio wireless twin is also a cadence host" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio-1"
  run install_renovate_held_agent
  [ "$status" -eq 0 ]
  [ -f "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist" ]
}
