#!/usr/bin/env bats
# .ssh/config routing for claude and workstation, resolved by the real `ssh -G`
# (no connection is made). HOME points at a fixture holding a stub
# home-lan-probe, `uname` is a stub on a PATH prefix, and SHELL is pinned because
# Match exec runs under "$SHELL -c".

bats_require_minimum_version 1.5.0

CLAUDE_IP=192.168.51.17
CLAUDE_FPR='SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY'
WS_IP=192.168.51.12
WS_FPR='SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o'

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CONFIG="${REPO_ROOT}/.ssh/config"

  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.local/bin" "${BATS_TEST_TMPDIR}/bin"
  PROBE_LOG="${BATS_TEST_TMPDIR}/probe.log"
  export SHELL=/bin/sh

  # Probe stub: records argv, exits with the PROBE_EXIT knob (default 0).
  cat > "${HOME}/.local/bin/home-lan-probe" << STUBEOF
#!/bin/sh
printf '%s\n' "\$*" >> "${PROBE_LOG}"
exit "\${PROBE_EXIT:-0}"
STUBEOF
  chmod +x "${HOME}/.local/bin/home-lan-probe"

  # uname stub: prints the platform named by FAKE_UNAME.
  cat > "${BATS_TEST_TMPDIR}/bin/uname" << 'STUBEOF'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Linux}"
STUBEOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/uname"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# resolve <platform> <host>: run ssh -G for host with the given fake platform.
# `run` strips the trailing newline, so it is restored (and a leading one added)
# to let every assertion match a whole line as *$'\nline\n'*.
resolve() {
  FAKE_UNAME="$1" run ssh -G -F "${CONFIG}" "$2"
  output="${output:+$'\n'${output}$'\n'}"
}

@test "Darwin, probe exit 1: claude goes direct IP plus Cloudflare chain" {
  export PROBE_EXIT=1
  resolve Darwin claude
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'\nhostname 192.168.51.17\n'* ]]
  [[ "${output}" == *$'\nhostkeyalias claude\n'* ]]
  [[ "${output}" == *$'\nproxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca\n'* ]]
}

@test "Darwin, probe exit 1: workstation goes direct IP plus Cloudflare hop" {
  export PROBE_EXIT=1
  resolve Darwin workstation
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'\nhostname 192.168.51.12\n'* ]]
  [[ "${output}" == *$'\nhostkeyalias workstation\n'* ]]
  [[ "${output}" == *$'\nproxyjump home-secure.conecrazy.ca\n'* ]]
}

@test "Darwin, probe exit 1 under zsh as SHELL: Cloudflare chain still applies" {
  command -v zsh > /dev/null || skip "zsh not installed"
  export PROBE_EXIT=1
  SHELL="$(command -v zsh)"
  export SHELL
  resolve Darwin claude
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'\nhostname 192.168.51.17\n'* ]]
  [[ "${output}" == *$'\nhostkeyalias claude\n'* ]]
  [[ "${output}" == *$'\nproxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca\n'* ]]
}

@test "Darwin, probe exit 0: direct, no proxyjump" {
  export PROBE_EXIT=0
  local host ip alias
  for host in claude workstation; do
    ip="${CLAUDE_IP}"
    [[ "${host}" == workstation ]] && ip="${WS_IP}"
    alias="${host}"
    resolve Darwin "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname '"${ip}"$'\n'* ]]
    [[ "${output}" == *$'\nhostkeyalias '"${alias}"$'\n'* ]]
    [[ "${output}" == *$'\nuser bruce\n'* ]]
    [[ "${output}" == *$'\nidentityfile '*'/.ssh/home'$'\n'* ]]
    [[ "${output}" != *proxyjump* ]]
  done
}

@test "Darwin, probe absent: direct, no proxyjump" {
  rm -f "${HOME}/.local/bin/home-lan-probe"
  local host ip
  for host in claude workstation; do
    ip="${CLAUDE_IP}"
    [[ "${host}" == workstation ]] && ip="${WS_IP}"
    resolve Darwin "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname '"${ip}"$'\n'* ]]
    [[ "${output}" == *$'\nhostkeyalias '"${host}"$'\n'* ]]
    [[ "${output}" != *proxyjump* ]]
  done
}

@test "Linux, probe exit 1: names unchanged and the probe is never called" {
  export PROBE_EXIT=1
  local host
  for host in claude workstation; do
    resolve Linux "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname '"${host}"$'\n'* ]]
    [[ "${output}" != *hostkeyalias* ]]
    [[ "${output}" != *proxyjump* ]]
  done
  [ ! -e "${PROBE_LOG}" ]
}

@test "Darwin: probe argv is exactly the pinned IP and fingerprint" {
  export PROBE_EXIT=1
  resolve Darwin claude
  [ "${status}" -eq 0 ]
  [ "$(cat "${PROBE_LOG}")" = "${CLAUDE_IP} ${CLAUDE_FPR}" ]
  rm -f "${PROBE_LOG}"
  resolve Darwin workstation
  [ "${status}" -eq 0 ]
  [ "$(cat "${PROBE_LOG}")" = "${WS_IP} ${WS_FPR}" ]
}

@test "no -home-tmux Host pattern and no RemoteCommand remain" {
  run ! command grep -qE '^[[:space:]]*Host[[:space:]].*-home-tmux' "${CONFIG}"
  run ! command grep -qi 'RemoteCommand' "${CONFIG}"
}

@test "controlmaster resolves false for claude and workstation" {
  local plat host
  for plat in Darwin Linux; do
    for host in claude workstation workstation.home.conecrazy.ca; do
      resolve "${plat}" "${host}"
      [ "${status}" -eq 0 ]
      [[ "${output}" == *$'\ncontrolmaster false\n'* ]]
    done
  done
}

@test "userknownhostsfile adds known_hosts_home on Darwin only" {
  local host nl=$'\n'
  local re="${nl}userknownhostsfile [^${nl}]*/.ssh/known_hosts [^${nl}]*/.ssh/known_hosts_home${nl}"
  for host in claude workstation workstation.home.conecrazy.ca; do
    resolve Darwin "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname '*$'\n'* ]]
    [[ "${output}" =~ ${re} ]]
    resolve Linux "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname '*$'\n'* ]]
    [[ "${output}" != *known_hosts_home* ]]
  done
}

@test "Darwin direct blocks refuse an unknown host key; Linux and the jump hop are unchanged" {
  local host
  for host in claude workstation; do
    resolve Darwin "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nstricthostkeychecking true\n'* ]]
    resolve Linux "${host}"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *$'\nstricthostkeychecking true\n'* ]]
  done
  resolve Darwin workstation.home.conecrazy.ca
  [ "${status}" -eq 0 ]
  [[ "${output}" != *$'\nstricthostkeychecking true\n'* ]]
}

@test "N4: Darwin changes only userknownhostsfile and its derived updatehostkeys for the jump hop" {
  resolve Darwin workstation.home.conecrazy.ca
  [ "${status}" -eq 0 ]
  local darwin="${output}"
  resolve Linux workstation.home.conecrazy.ca
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'\nhostname workstation.home.conecrazy.ca\n'* ]]
  # Keys of every line that differs between the platforms (ssh derives
  # updatehostkeys from a custom UserKnownHostsFile).
  local keys
  keys="$(diff <(printf '%s\n' "${darwin}") <(printf '%s\n' "${output}") | awk '/^[<>]/ {print $2}' | LC_ALL=C sort -u | tr '\n' ' ')"
  [ "${keys}" = "updatehostkeys userknownhostsfile " ]
}

@test "N4: -home aliases keep their ProxyJump on Darwin and Linux" {
  export PROBE_EXIT=0
  local plat
  for plat in Darwin Linux; do
    resolve "${plat}" claude-home
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname claude.home.conecrazy.ca\n'* ]]
    [[ "${output}" == *$'\nproxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca\n'* ]]
    resolve "${plat}" workstation-home
    [ "${status}" -eq 0 ]
    [[ "${output}" == *$'\nhostname workstation.home.conecrazy.ca\n'* ]]
    [[ "${output}" == *$'\nproxyjump home-secure.conecrazy.ca\n'* ]]
  done
}

@test "tracked keys: exactly three ed25519 entries with the pinned fingerprints" {
  local file="${REPO_ROOT}/.ssh/known_hosts_home"
  [ "$(wc -l < "${file}")" -eq 3 ]
  run ssh-keygen -lf "${file}"
  [ "${status}" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == *"${CLAUDE_FPR} claude (ED25519)" ]]
  [[ "${lines[1]}" == *"${WS_FPR} workstation (ED25519)" ]]
  [[ "${lines[2]}" == *"${WS_FPR} workstation.home.conecrazy.ca (ED25519)" ]]
}

@test "tracked keys: fingerprints equal the ones pinned in the Match lines" {
  run command grep -o 'SHA256:[A-Za-z0-9+/]*' "${CONFIG}"
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | LC_ALL=C sort -u)" = "$(printf '%s\n%s\n' "${CLAUDE_FPR}" "${WS_FPR}" | LC_ALL=C sort -u)" ]
}
