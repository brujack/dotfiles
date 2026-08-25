#!/usr/bin/env bats

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/lib/renovate_cadence.sh"
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
  ! command grep -q '__DOTFILES__\|__HOME__' "${_RHN_AGENT_DIR}/com.brucejackson.renovate-held.plist"
}

@test "the installed plist points at a script that exists" {
  export PROFILE="mac_workstation" HOSTNAME_SHORT="studio"
  run install_renovate_held_agent
  local _p
  _p=$(sed -n 's|.*<string>\(/.*renovate-held-notify.sh\)</string>.*|\1|p' \
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
