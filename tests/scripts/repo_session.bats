#!/usr/bin/env bats
# bin/repo-session: per-repo tmux session launcher. tmux is a recording stub
# reached through _TMUX_BIN; no test touches a real tmux server.

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/bin/repo-session"

  export HOME="${BATS_TEST_TMPDIR}/home"
  PERSONAL="${HOME}/git-repos/personal"
  mkdir -p "${PERSONAL}/dotfiles/config" "${PERSONAL}/etch-cli" \
    "${PERSONAL}/terraform_ansible/ansible" "${HOME}/.local/bin"

  TMUX_LOG="${BATS_TEST_TMPDIR}/tmux.log"
  HAS_SESSION_RC_FILE="${BATS_TEST_TMPDIR}/has_session_rc"
  NEW_SESSION_FAIL_FILE="${BATS_TEST_TMPDIR}/new_session_fail"
  : > "${TMUX_LOG}"
  printf '1\n' > "${HAS_SESSION_RC_FILE}"
  : > "${NEW_SESSION_FAIL_FILE}"

  # Logs one line per call (args joined by single spaces). has-session exit comes
  # from a knob file; new-session fails when its -s name is listed in a knob file.
  cat > "${BATS_TEST_TMPDIR}/tmux-stub" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TMUX_LOG}"
case "\$1" in
  has-session) exit "\$(cat "${HAS_SESSION_RC_FILE}")" ;;
  new-session)
    while [[ \$# -gt 0 ]]; do
      if [[ \$1 == -s ]]; then
        grep -qx -- "\$2" "${NEW_SESSION_FAIL_FILE}" && exit 1
      fi
      shift
    done
    exit 0 ;;
esac
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/tmux-stub"
  export _TMUX_BIN="${BATS_TEST_TMPDIR}/tmux-stub"

  export REPO_SESSIONS_FILE="${BATS_TEST_TMPDIR}/repo-sessions.sh"
  export _REPO_SESSION_HOST="testhost"
  cat > "${REPO_SESSIONS_FILE}" <<'LIST'
declare -A REPO_SESSIONS=(
  [testhost]="dotfiles etch-cli terraform_ansible/ansible"
  [otherhost]="etch-cli"
)
LIST
}

tmux_calls() { wc -l < "${TMUX_LOG}" | tr -d ' '; }

@test "attach mode: new-session -A with name and path from dir" {
  run "${SCRIPT}" dotfiles < /dev/null
  [ "${status}" -eq 0 ]
  grep -q -- "^new-session -A -s dotfiles -c ${PERSONAL}/dotfiles " "${TMUX_LOG}"
  ! grep -q -- ' -d ' "${TMUX_LOG}"
}

@test "attach mode passes the claude pane command" {
  run "${SCRIPT}" dotfiles < /dev/null
  [ "${status}" -eq 0 ]
  grep -qF -- "zsh -ic 'claude --name \"\$(basename \"\$PWD\")\" --remote-control; exec zsh'" "${TMUX_LOG}"
}

@test "nested dir names the session after the last component" {
  run "${SCRIPT}" terraform_ansible/ansible < /dev/null
  [ "${status}" -eq 0 ]
  grep -q -- "^new-session -A -s ansible -c ${PERSONAL}/terraform_ansible/ansible " "${TMUX_LOG}"
}

@test "--detached creates with -d when has-session fails" {
  run "${SCRIPT}" --detached dotfiles < /dev/null
  [ "${status}" -eq 0 ]
  grep -q -- '^has-session -t =dotfiles$' "${TMUX_LOG}"
  grep -q -- "^new-session -d -A -s dotfiles -c ${PERSONAL}/dotfiles " "${TMUX_LOG}"
}

@test "--detached does nothing when has-session succeeds" {
  printf '0\n' > "${HAS_SESSION_RC_FILE}"
  run "${SCRIPT}" --detached dotfiles < /dev/null
  [ "${status}" -eq 0 ]
  ! grep -q -- '^new-session' "${TMUX_LOG}"
}

@test "--detached propagates a new-session failure" {
  printf 'dotfiles\n' > "${NEW_SESSION_FAIL_FILE}"
  run "${SCRIPT}" --detached dotfiles < /dev/null
  [ "${status}" -eq 1 ]
}

@test "attach-mode new-session failure exits 1" {
  printf 'dotfiles\n' > "${NEW_SESSION_FAIL_FILE}"
  run "${SCRIPT}" dotfiles < /dev/null
  [ "${status}" -eq 1 ]
}

@test "--all walks the host list and exits 0 when all succeed" {
  run "${SCRIPT}" --detached --all < /dev/null
  [ "${status}" -eq 0 ]
  grep -q -- '^has-session -t =dotfiles$' "${TMUX_LOG}"
  grep -q -- '^new-session -d -A -s dotfiles ' "${TMUX_LOG}"
  grep -q -- ' -s etch-cli ' "${TMUX_LOG}"
  grep -q -- ' -s ansible ' "${TMUX_LOG}"
}

@test "--all continues past a failing dir and exits 1" {
  printf 'etch-cli\n' > "${NEW_SESSION_FAIL_FILE}"
  run "${SCRIPT}" --detached --all < /dev/null
  [ "${status}" -eq 1 ]
  [[ "${output}" == *etch-cli* ]]
  grep -q -- ' -s dotfiles ' "${TMUX_LOG}"
  grep -q -- ' -s ansible ' "${TMUX_LOG}"
}

@test "--all counts a missing directory in the list as a failure and continues" {
  printf 'declare -A REPO_SESSIONS=( [testhost]="nosuchdir dotfiles" )\n' > "${REPO_SESSIONS_FILE}"
  run "${SCRIPT}" --detached --all < /dev/null
  [ "${status}" -eq 1 ]
  [[ "${output}" == *nosuchdir* ]]
  grep -q -- ' -s dotfiles ' "${TMUX_LOG}"
}

@test "--all without --detached exits 2 without calling tmux" {
  run "${SCRIPT}" --all < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "empty dir exits 2 without calling tmux" {
  run "${SCRIPT}" "" < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "no argument exits 2 without calling tmux" {
  run "${SCRIPT}" < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "absolute dir exits 2 naming the argument, without calling tmux" {
  run "${SCRIPT}" /etc < /dev/null
  [ "${status}" -eq 2 ]
  [[ "${output}" == */etc* ]]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "dir with .. component exits 2 without calling tmux" {
  run "${SCRIPT}" ../personal/dotfiles < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
  run "${SCRIPT}" .. < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
  run "${SCRIPT}" dotfiles/.. < /dev/null
  [ "${status}" -eq 2 ]
  run "${SCRIPT}" etch-cli/../dotfiles < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "missing dir exits 2 naming the argument, without calling tmux" {
  run "${SCRIPT}" nosuchdir < /dev/null
  [ "${status}" -eq 2 ]
  [[ "${output}" == *nosuchdir* ]]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "a regular file is not a directory: exits 2" {
  : > "${PERSONAL}/afile"
  run "${SCRIPT}" afile < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "trailing slash is stripped: dotfiles/ names session dotfiles" {
  run "${SCRIPT}" dotfiles/ < /dev/null
  [ "${status}" -eq 0 ]
  grep -q -- "^new-session -A -s dotfiles -c ${PERSONAL}/dotfiles " "${TMUX_LOG}"
}

@test "slash alone exits 2 without calling tmux" {
  run "${SCRIPT}" / < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "--all through a symlink in ~/.local/bin reads the fixed-path list" {
  unset REPO_SESSIONS_FILE
  cp "${BATS_TEST_TMPDIR}/repo-sessions.sh" "${PERSONAL}/dotfiles/config/repo-sessions.sh"
  ln -s "${SCRIPT}" "${HOME}/.local/bin/repo-session"
  run "${HOME}/.local/bin/repo-session" --detached --all < /dev/null
  [ "${status}" -eq 0 ]
  grep -q -- ' -s dotfiles ' "${TMUX_LOG}"
  grep -q -- ' -s ansible ' "${TMUX_LOG}"
}

@test "missing list exits 3 naming the path" {
  export REPO_SESSIONS_FILE="${BATS_TEST_TMPDIR}/absent.sh"
  run "${SCRIPT}" --detached --all < /dev/null
  [ "${status}" -eq 3 ]
  [[ "${output}" == *"${REPO_SESSIONS_FILE}"* ]]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "unreadable list exits 3" {
  [[ "$(id -u)" -ne 0 ]] || skip "root reads any file"
  chmod 000 "${REPO_SESSIONS_FILE}"
  run "${SCRIPT}" --detached --all < /dev/null
  [ "${status}" -eq 3 ]
  [[ "${output}" == *"${REPO_SESSIONS_FILE}"* ]]
}

@test "host absent from a readable list exits 0 with a message" {
  export _REPO_SESSION_HOST="unlisted"
  run "${SCRIPT}" --detached --all < /dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"repo-session: no sessions listed for unlisted"* ]]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "tracked list maps claude and workstation per R10" {
  run bash -c 'source "$1"; printf "%s|%s" "${REPO_SESSIONS[claude]}" "${REPO_SESSIONS[workstation]}"' _ "${REPO_ROOT}/config/repo-sessions.sh"
  [ "${status}" -eq 0 ]
  [ "${output}" = "etch-cli etch-config dotfiles ai-config ai-devops math|terraform_ansible/ansible" ]
}

@test "dot components and dotted or colon names exit 2 without calling tmux" {
  mkdir -p "${PERSONAL}/my.repo" "${PERSONAL}/a:b"
  local arg
  for arg in . ./ dotfiles/. ./dotfiles my.repo a:b; do
    run "${SCRIPT}" "${arg}" < /dev/null
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"${arg}"* ]]
  done
  [ "$(tmux_calls)" -eq 0 ]
}

@test "two positional arguments exit 2 without calling tmux" {
  run "${SCRIPT}" dotfiles etch-cli < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}

@test "--detached --all with a dir exits 2 without calling tmux" {
  run "${SCRIPT}" --detached --all dotfiles < /dev/null
  [ "${status}" -eq 2 ]
  [ "$(tmux_calls)" -eq 0 ]
}
