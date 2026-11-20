#!/usr/bin/env bats

# Warp launch configs for repo sessions (spec R14, N2). The session tabs must
# route each repo directory to the host that actually runs its tmux session.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WARP_DIR="${REPO_ROOT}/.warp/launch_configurations"
  CONFIGS=(studio laptop reception)
}

# Print "<host> <dir>" for every session tab exec line in a config.
tab_pairs() {
  awk '
    /exec: ssh -t [^ ]+ \.local\/bin\/repo-session / {
      for (i = 1; i <= NF; i++) if ($i == "-t") { host = $(i + 1) }
      print host, $NF
    }' "$1"
}

# Print "<host> <dir>" for every entry in config/repo-sessions.sh.
expected_pairs() {
  (
    # shellcheck disable=SC1091 # path resolved at runtime from REPO_ROOT
    source "${REPO_ROOT}/config/repo-sessions.sh" || exit 1
    local host dir
    for host in "${!REPO_SESSIONS[@]}"; do
      for dir in ${REPO_SESSIONS[${host}]}; do
        printf '%s %s\n' "${host}" "${dir}"
      done
    done
  )
}

@test "three configs exist and the old launch_config.yaml is gone" {
  local c
  for c in "${CONFIGS[@]}"; do
    [ -f "${WARP_DIR}/${c}.yaml" ]
  done
  [ ! -e "${WARP_DIR}/launch_config.yaml" ]
}

@test "every config parses as YAML" {
  python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not importable"
  local c
  for c in "${CONFIGS[@]}"; do
    run python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "${WARP_DIR}/${c}.yaml"
    [ "${status}" -eq 0 ]
  done
}

@test "each config's session tabs equal the (host, dir) pairs of repo-sessions.sh" {
  local c expected actual
  expected="$(expected_pairs | LC_ALL=C sort)"
  [ "$(printf '%s\n' "${expected}" | wc -l)" -eq 7 ]
  for c in "${CONFIGS[@]}"; do
    actual="$(tab_pairs "${WARP_DIR}/${c}.yaml" | LC_ALL=C sort)"
    [ "$(printf '%s\n' "${actual}" | wc -l)" -eq 7 ]
    [ "${actual}" = "${expected}" ]
  done
}

@test "no exec line names repo-session without the .local/bin/ prefix" {
  local c
  for c in "${CONFIGS[@]}"; do
    run awk '/exec:/ && /repo-session/ && !/\.local\/bin\/repo-session/ { print; bad = 1 } END { exit bad }' "${WARP_DIR}/${c}.yaml"
    [ "${status}" -eq 0 ]
  done
}

@test "N2: no exec line runs an update" {
  local c
  for c in "${CONFIGS[@]}"; do
    run awk '/exec:/ && (/-t update/ || /setup_env\.sh/) { print; bad = 1 } END { exit bad }' "${WARP_DIR}/${c}.yaml"
    [ "${status}" -eq 0 ]
  done
}

@test "update tabs: studio has four, laptop has update-laptop, reception has none" {
  local t
  for t in update-studio update-laptop update-workstation update-claude; do
    grep -qx "      - title: ${t}" "${WARP_DIR}/studio.yaml"
  done
  grep -qx "      - title: update-laptop" "${WARP_DIR}/laptop.yaml"
  ! command grep -q 'title: update-' "${WARP_DIR}/reception.yaml"
}

@test "remote PATH: repo-session resolves from a bare HOME via .local/bin" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  local fixture="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${fixture}/.local/bin"
  printf '#!/bin/sh\nprintf "stub-marker\\n"\n' > "${fixture}/.local/bin/repo-session"
  chmod +x "${fixture}/.local/bin/repo-session"
  run env -i HOME="${fixture}" PATH=/usr/bin:/bin zsh -c 'cd && .local/bin/repo-session dotfiles'
  [ "${status}" -eq 0 ]
  [ "${output}" = "stub-marker" ]
}
