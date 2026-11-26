#!/usr/bin/env bats

# Covers config/systemd/repo-sessions.service and lib/repo_sessions.sh:
# install_repo_sessions and _doctor_check_repo_sessions.
#
# No test reaches real systemctl, loginctl, tmux or sudo: every binary goes through
# a seam (_SYSTEMCTL_BIN, _LOGINCTL_BIN, _TMUX_BIN) to a recording stub, and
# tests/mocks/sudo execs the stub path it is given. All stubs append to one calls
# file (MOCK_CALLS_FILE) so the relative order of calls can be asserted.

load '../helpers/common.bash'

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/calls"
  : > "${MOCK_CALLS_FILE}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export USER="tester"
  mkdir -p "${HOME}"
  # The lib reads these at call time; point link sources at this checkout.
  PERSONAL_GITREPOS="$(dirname "${REPO_ROOT}")"
  DOTFILES="$(basename "${REPO_ROOT}")"
  export PERSONAL_GITREPOS DOTFILES

  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}"
  printf 'no\n' > "${STUB_DIR}/linger"
  : > "${STUB_DIR}/sessions"
  _write_stubs

  export _SYSTEMCTL_BIN="${STUB_DIR}/systemctl"
  export _LOGINCTL_BIN="${STUB_DIR}/loginctl"
  export _TMUX_BIN="${STUB_DIR}/tmux"
  export _SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

  export REPO_SESSIONS_FILE="${BATS_TEST_TMPDIR}/repo-sessions.sh"
  cat > "${REPO_SESSIONS_FILE}" <<'EOF'
declare -A REPO_SESSIONS=(
  [claude]="etch-cli dotfiles"
  [workstation]="terraform_ansible/ansible"
)
EOF
  export _REPO_SESSION_HOST="claude"

  # OS vars are not set by load_setup_env; a developer shell may export either.
  unset MACOS LINUX UBUNTU
  UNIT_SRC="${REPO_ROOT}/config/systemd/repo-sessions.service"
  # The chmod mock logged the stub setup above; start every test from an empty record.
  : > "${MOCK_CALLS_FILE}"
}

# Recording stubs. systemctl state lives in files under STUB_DIR: `enabled` exists
# once `enable` ran, `failed` makes is-failed report failed. STUB_FAIL_ARGS is a
# substring of the joined argv; a matching call records itself then exits 1.
_write_stubs() {
  cat > "${STUB_DIR}/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${MOCK_CALLS_FILE}"
[[ -n "${STUB_FAIL_ARGS:-}" && "$*" == *"${STUB_FAIL_ARGS}"* ]] && exit 1
case "$2" in
  is-enabled)
    if [[ -e "${STUB_DIR}/enabled_word" ]]; then cat "${STUB_DIR}/enabled_word"; exit 0; fi
    if [[ -e "${STUB_DIR}/enabled" ]]; then printf 'enabled\n'; exit 0; fi
    printf 'linked\n'; exit 1 ;;
  is-failed)
    if [[ -e "${STUB_DIR}/failed" ]]; then printf 'failed\n'; exit 0; fi
    printf 'active\n'; exit 1 ;;
  enable) : > "${STUB_DIR}/enabled" ;;
esac
exit 0
EOF
  cat > "${STUB_DIR}/loginctl" <<'EOF'
#!/usr/bin/env bash
printf 'loginctl %s\n' "$*" >> "${MOCK_CALLS_FILE}"
[[ -n "${STUB_FAIL_ARGS:-}" && "$*" == *"${STUB_FAIL_ARGS}"* ]] && exit 1
case "$1" in
  show-user) printf 'Linger=%s\n' "$(cat "${STUB_DIR}/linger")" ;;
  enable-linger) printf 'yes\n' > "${STUB_DIR}/linger" ;;
esac
exit 0
EOF
  cat > "${STUB_DIR}/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "${MOCK_CALLS_FILE}"
if [[ "$1" == has-session ]]; then
  grep -qxF -- "${3#=}" "${STUB_DIR}/sessions"
  exit $?
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/systemctl" "${STUB_DIR}/loginctl" "${STUB_DIR}/tmux"
}

# _line_of <fixed-string>: first line number in the calls file containing it.
_line_of() {
  grep -nF -- "$1" "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1
}

_set_sessions() { printf '%s\n' "$@" > "${STUB_DIR}/sessions"; }

# ── unit file ────────────────────────────────────────────────────────────────

@test "unit: carries KillMode=process, TimeoutStartSec=180 and an ExecStart with no dash prefix" {
  grep -qx 'KillMode=process' "${UNIT_SRC}"
  grep -qx 'TimeoutStartSec=180' "${UNIT_SRC}"
  grep -qx 'ExecStart=%h/.local/bin/repo-session --detached --all' "${UNIT_SRC}"
  run ! grep -q '^ExecStart=-' "${UNIT_SRC}"
}

@test "unit: matches R11 line for line" {
  grep -qx 'Type=oneshot' "${UNIT_SRC}"
  grep -qx 'RemainAfterExit=yes' "${UNIT_SRC}"
  grep -qxF "ExecStartPre=-/usr/bin/timeout 60 /bin/sh -c 'until nc -z -w 1 api.anthropic.com 443; do sleep 1; done'" "${UNIT_SRC}"
  grep -qx 'WantedBy=default.target' "${UNIT_SRC}"
}

@test "unit: systemd-analyze --user verify passes" {
  command -v systemd-analyze > /dev/null 2>&1 \
    || skip "systemd-analyze not available on this platform"
  # verify wants the ExecStart target to exist; give it a stand-in under a fixture HOME.
  mkdir -p "${HOME}/.local/bin"
  printf '#!/bin/sh\n' > "${HOME}/.local/bin/repo-session"
  chmod +x "${HOME}/.local/bin/repo-session"
  run systemd-analyze --user verify "${UNIT_SRC}"
  [ "$status" -eq 0 ]
}

# ── installer ────────────────────────────────────────────────────────────────

@test "install: macOS links only home-lan-probe and known_hosts_home" {
  export MACOS=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ "$(readlink "${HOME}/.local/bin/home-lan-probe")" = "${REPO_ROOT}/bin/home-lan-probe" ]
  [ "$(readlink "${HOME}/.ssh/known_hosts_home")" = "${REPO_ROOT}/.ssh/known_hosts_home" ]
  [ ! -e "${HOME}/.local/bin/repo-session" ]
  [ ! -e "${_SYSTEMD_USER_DIR}" ]
  run ! grep -qE '^(systemctl|loginctl|sudo) ' "${MOCK_CALLS_FILE}"
}

@test "install: macOS does no Linux install on a listed host name" {
  export MACOS=1 _REPO_SESSION_HOST=claude
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.local/bin/repo-session" ]
  run ! grep -qE '^(systemctl|loginctl|sudo) ' "${MOCK_CALLS_FILE}"
}

@test "install: Linux host without a list entry gets nothing" {
  export LINUX=1 _REPO_SESSION_HOST=unlisted
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.local/bin" ]
  [ ! -e "${_SYSTEMD_USER_DIR}" ]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "install: Linux host with an unreadable list gets nothing" {
  export LINUX=1 REPO_SESSIONS_FILE="${BATS_TEST_TMPDIR}/absent.sh"
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.local/bin" ]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "install: neither macOS nor Linux gets nothing" {
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.local/bin" ]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "install: Linux listed host links repo-session and the unit" {
  export LINUX=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ "$(readlink "${HOME}/.local/bin/repo-session")" = "${REPO_ROOT}/bin/repo-session" ]
  [ "$(readlink "${_SYSTEMD_USER_DIR}/repo-sessions.service")" = "${UNIT_SRC}" ]
  [ ! -e "${HOME}/.local/bin/home-lan-probe" ]
}

@test "install: host name defaults to hostname -s when the seam is unset" {
  export LINUX=1 MOCK_HOSTNAME_OUTPUT=workstation
  unset _REPO_SESSION_HOST
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ -L "${HOME}/.local/bin/repo-session" ]
}

@test "install: list path defaults under PERSONAL_GITREPOS/DOTFILES when the seam is unset" {
  export LINUX=1
  unset REPO_SESSIONS_FILE
  # REPO_ROOT's own config/repo-sessions.sh lists claude.
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ -L "${HOME}/.local/bin/repo-session" ]
}

@test "install: enables linger only when Linger=no" {
  export LINUX=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  grep -qx 'loginctl show-user tester -p Linger' "${MOCK_CALLS_FILE}"
  grep -qx 'sudo '"${STUB_DIR}"'/loginctl enable-linger tester' "${MOCK_CALLS_FILE}"
  grep -qx 'loginctl enable-linger tester' "${MOCK_CALLS_FILE}"
}

@test "install: sudo never runs the _LOGINCTL_BIN seam outside bats" {
  export LINUX=1
  # The seam points at a recorder that would log SEAM-RAN. Guard failure
  # (seam honoured under sudo) records that line; the production name must
  # instead resolve to tests/mocks/loginctl via PATH, never a real loginctl.
  local _seam="${BATS_TEST_TMPDIR}/seam-loginctl"
  printf '#!/usr/bin/env bash\nprintf "SEAM-RAN %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 0\n' > "${_seam}"
  chmod +x "${_seam}"
  local _mockbin="${BATS_TEST_TMPDIR}/mockbin"
  mkdir -p "${_mockbin}"
  printf '#!/usr/bin/env bash\nprintf "loginctl %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\n[[ "$1" == show-user ]] && printf "Linger=no\\n"\nexit 0\n' > "${_mockbin}/loginctl"
  chmod +x "${_mockbin}/loginctl"
  PATH="${_mockbin}:${PATH}" BATS_TEST_TMPDIR='' _LOGINCTL_BIN="${_seam}" run install_repo_sessions
  [ "$status" -eq 0 ]
  grep -qx 'sudo loginctl enable-linger tester' "${MOCK_CALLS_FILE}"
  run ! grep -q 'SEAM-RAN' "${MOCK_CALLS_FILE}"
  run ! grep -F "sudo ${_seam}" "${MOCK_CALLS_FILE}"
}

@test "install: leaves linger alone when Linger=yes" {
  export LINUX=1
  printf 'yes\n' > "${STUB_DIR}/linger"
  run install_repo_sessions
  [ "$status" -eq 0 ]
  run ! grep -q 'enable-linger' "${MOCK_CALLS_FILE}"
  run ! grep -q '^sudo ' "${MOCK_CALLS_FILE}"
}

@test "install: the unit is enabled after daemon-reload and never started" {
  export LINUX=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  grep -qx 'systemctl --user daemon-reload' "${MOCK_CALLS_FILE}"
  grep -qx 'systemctl --user enable repo-sessions.service' "${MOCK_CALLS_FILE}"
  [ "$(_line_of 'systemctl --user daemon-reload')" -lt "$(_line_of 'systemctl --user enable')" ]
  run ! grep -qE 'systemctl .*(start|restart)' "${MOCK_CALLS_FILE}"
  [ -e "${STUB_DIR}/enabled" ]
}

@test "install: loginctl enable-linger is recorded before systemctl --user enable (N1 order)" {
  export LINUX=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  local _linger _enable
  _linger="$(_line_of 'loginctl enable-linger')"
  _enable="$(_line_of 'systemctl --user enable')"
  [ -n "${_linger}" ]
  [ -n "${_enable}" ]
  [ "${_linger}" -lt "${_enable}" ]
}

@test "install: creates the systemd user dir when absent" {
  export LINUX=1
  [ ! -d "${_SYSTEMD_USER_DIR}" ]
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ -d "${_SYSTEMD_USER_DIR}" ]
}

@test "install: a second run makes no sudo call and no new enable" {
  export LINUX=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  : > "${MOCK_CALLS_FILE}"
  run install_repo_sessions
  [ "$status" -eq 0 ]
  run ! grep -q '^sudo ' "${MOCK_CALLS_FILE}"
  run ! grep -q 'enable-linger' "${MOCK_CALLS_FILE}"
  run ! grep -qx 'systemctl --user enable repo-sessions.service' "${MOCK_CALLS_FILE}"
  [ "$(readlink "${_SYSTEMD_USER_DIR}/repo-sessions.service")" = "${UNIT_SRC}" ]
}

@test "install: never creates, kills or restarts a tmux session" {
  export LINUX=1
  run install_repo_sessions
  [ "$status" -eq 0 ]
  run ! grep -q '^tmux ' "${MOCK_CALLS_FILE}"
}

@test "install: failed repo-session link returns 1 naming the step" {
  export LINUX=1 MOCK_LN_EXIT=1
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"repo-session"*"link"* ]]
  run ! grep -q 'systemctl' "${MOCK_CALLS_FILE}"
}

@test "install: failed macOS link returns 1 naming the step" {
  export MACOS=1 MOCK_LN_EXIT=1
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"home-lan-probe"* ]]
}

@test "install: failed macOS known_hosts_home link returns 1 naming the step" {
  export MACOS=1
  safe_link() { [[ "$2" == *known_hosts_home ]] && return 1; return 0; }
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"known_hosts_home"* ]]
}

@test "install: macOS cannot create ~/.local/bin returns 1" {
  export MACOS=1
  : > "${HOME}/.local"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"mkdir"* ]]
}

@test "install: macOS cannot create ~/.ssh returns 1" {
  export MACOS=1
  mkdir -p "${HOME}/.local/bin"
  : > "${HOME}/.ssh"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"mkdir"* ]]
  # The ~/.ssh failure returns at once: nothing is linked, and the later
  # known_hosts_home mkdir is never reached.
  [[ "${output}" != *"(known_hosts_home)"* ]]
  [ ! -e "${HOME}/.local/bin/home-lan-probe" ]
}

@test "install: Linux cannot create ~/.local/bin returns 1" {
  export LINUX=1
  : > "${HOME}/.local"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"mkdir"* ]]
}

@test "install: unreadable linger state returns 1 and does not enable the unit" {
  export LINUX=1 STUB_FAIL_ARGS="show-user"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"linger"* ]]
  run ! grep -q 'systemctl --user enable' "${MOCK_CALLS_FILE}"
}

@test "install: failed enable-linger returns 1 and does not enable the unit" {
  export LINUX=1 STUB_FAIL_ARGS="enable-linger"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"enable-linger"* ]]
  run ! grep -q 'systemctl --user enable' "${MOCK_CALLS_FILE}"
}

@test "install: cannot create the systemd user dir returns 1" {
  export LINUX=1
  mkdir -p "${HOME}/.config"
  : > "${HOME}/.config/systemd"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"systemd"* ]]
  run ! grep -q 'systemctl' "${MOCK_CALLS_FILE}"
}

@test "install: failed unit link returns 1 naming the step" {
  export LINUX=1
  safe_link() { [[ "$2" == *repo-sessions.service ]] && return 1; command ln -sf "$1" "$2"; }
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"repo-sessions.service"* ]]
  run ! grep -q 'systemctl --user enable' "${MOCK_CALLS_FILE}"
}

@test "install: failed daemon-reload returns 1 and does not enable" {
  export LINUX=1 STUB_FAIL_ARGS="daemon-reload"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"daemon-reload"* ]]
  run ! grep -q 'systemctl --user enable' "${MOCK_CALLS_FILE}"
}

@test "install: failed enable returns 1 naming the step" {
  export LINUX=1 STUB_FAIL_ARGS="enable repo-sessions.service"
  run install_repo_sessions
  [ "$status" -eq 1 ]
  [[ "${output}" == *"enable"* ]]
}

# ── doctor ───────────────────────────────────────────────────────────────────

_healthy() {
  printf 'yes\n' > "${STUB_DIR}/linger"
  : > "${STUB_DIR}/enabled"
  _set_sessions etch-cli dotfiles
}

@test "doctor: all healthy passes" {
  _healthy
  run _doctor_check_repo_sessions
  [ "$status" -eq 0 ]
  [[ "${output}" == *"PASS"*"repo-sessions"* ]]
  [[ "${output}" != *"FAIL"* ]]
  [[ "${output}" != *"WARN"* ]]
}

@test "doctor: silent on a host with no entry" {
  _healthy
  export _REPO_SESSION_HOST=unlisted
  run _doctor_check_repo_sessions
  [ "$status" -eq 0 ]
  [ -z "${output}" ]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "doctor: silent when the list is unreadable" {
  export REPO_SESSIONS_FILE="${BATS_TEST_TMPDIR}/absent.sh"
  run _doctor_check_repo_sessions
  [ "$status" -eq 0 ]
  [ -z "${output}" ]
}

@test "doctor: Linger off fails with the enable-linger remedy" {
  _healthy
  printf 'no\n' > "${STUB_DIR}/linger"
  run _doctor_check_repo_sessions
  [[ "${output}" == *"FAIL"* ]]
  [[ "${output}" == *'sudo loginctl enable-linger "$USER"'* ]]
}

@test "doctor: unit not enabled fails with the setup_user remedy" {
  _healthy
  rm "${STUB_DIR}/enabled"
  run _doctor_check_repo_sessions
  [[ "${output}" == *"FAIL"* ]]
  [[ "${output}" == *'./setup_env.sh -t setup_user'* ]]
}

@test "doctor: a linked unit (rc 1, prints linked) fails" {
  _healthy
  rm "${STUB_DIR}/enabled"
  # A linked, not-yet-enabled unit prints 'linked' and exits 1.
  run _doctor_check_repo_sessions
  [[ "${output}" == *'./setup_env.sh -t setup_user'* ]]
  [[ "${output}" != *"PASS"* ]]
}

@test "doctor: failed unit with all sessions present fails with the restart remedy" {
  _healthy
  : > "${STUB_DIR}/failed"
  run _doctor_check_repo_sessions
  [[ "${output}" == *"FAIL"* ]]
  [[ "${output}" == *'systemctl --user restart repo-sessions.service'* ]]
  [[ "${output}" != *"WARN"* ]]
}

@test "doctor: one missing session warns naming it with the repo-session remedy" {
  _healthy
  _set_sessions etch-cli
  run _doctor_check_repo_sessions
  [[ "${output}" == *"WARN"* ]]
  [[ "${output}" == *"dotfiles"* ]]
  [[ "${output}" != *"etch-cli,"* ]]
  [[ "${output}" == *'repo-session --detached --all'* ]]
  [[ "${output}" != *"FAIL"* ]]
  grep -qxF 'tmux has-session -t =dotfiles' "${MOCK_CALLS_FILE}"
}

@test "doctor: two missing sessions are each named in the WARN" {
  _healthy
  _set_sessions other
  run _doctor_check_repo_sessions
  [[ "${output}" == *"WARN"* ]]
  [[ "${output}" == *"etch-cli"* ]]
  [[ "${output}" == *"dotfiles"* ]]
  [ "$(printf '%s\n' "${output}" | grep -c 'WARN')" -eq 1 ]
}

@test "doctor: a nested dir is checked by its last component" {
  _healthy
  export _REPO_SESSION_HOST=workstation
  _set_sessions ansible
  run _doctor_check_repo_sessions
  [[ "${output}" == *"PASS"* ]]
  grep -qxF 'tmux has-session -t =ansible' "${MOCK_CALLS_FILE}"
}

@test "doctor: reports every failing check, not just the first" {
  printf 'no\n' > "${STUB_DIR}/linger"
  : > "${STUB_DIR}/failed"
  run _doctor_check_repo_sessions
  [[ "${output}" == *'sudo loginctl enable-linger "$USER"'* ]]
  [[ "${output}" == *'./setup_env.sh -t setup_user'* ]]
  [[ "${output}" == *'restart repo-sessions.service'* ]]
  [[ "${output}" == *"WARN"* ]]
}

@test "doctor: unknown Linger state fails rather than passing" {
  _healthy
  export STUB_FAIL_ARGS="show-user"
  run _doctor_check_repo_sessions
  [[ "${output}" == *"FAIL"* ]]
  [[ "${output}" == *'sudo loginctl enable-linger "$USER"'* ]]
  [[ "${output}" != *"PASS"* ]]
}

# ── review round: ~/.ssh mode, enabled word, linger predicate, load_mocks seams ──

@test "install: macOS creates a missing ~/.ssh with mode 700" {
  export MACOS=1
  umask 022
  [ ! -e "${HOME}/.ssh" ]
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ -n "$(find "${HOME}/.ssh" -maxdepth 0 -perm 700)" ]
}

@test "install: macOS never changes the mode of an existing ~/.ssh" {
  export MACOS=1
  umask 022
  mkdir -p "${HOME}/.ssh"
  chmod 755 "${HOME}/.ssh"
  run install_repo_sessions
  [ "$status" -eq 0 ]
  [ -n "$(find "${HOME}/.ssh" -maxdepth 0 -perm 755)" ]
}

@test "install: an is-enabled word other than enabled (rc 0) still runs enable" {
  export LINUX=1
  printf 'enabled-runtime\n' > "${STUB_DIR}/enabled_word"
  run install_repo_sessions
  [ "$status" -eq 0 ]
  grep -qx 'systemctl --user enable repo-sessions.service' "${MOCK_CALLS_FILE}"
}

@test "doctor: an is-enabled word other than enabled (rc 0) fails" {
  _healthy
  printf 'enabled-runtime\n' > "${STUB_DIR}/enabled_word"
  run _doctor_check_repo_sessions
  [[ "${output}" == *"FAIL"* ]]
  [[ "${output}" == *'./setup_env.sh -t setup_user'* ]]
  [[ "${output}" != *"PASS"* ]]
}

@test "install: a malformed linger read enables linger" {
  export LINUX=1
  : > "${STUB_DIR}/linger"
  run install_repo_sessions
  [ "$status" -eq 0 ]
  grep -qx 'loginctl enable-linger tester' "${MOCK_CALLS_FILE}"
}

@test "load_mocks: exports inert defaults for the repo-sessions seams" {
  mkdir -p "${BATS_TEST_TMPDIR}/lm"
  run bash -c 'REPO_ROOT="$1"; export BATS_TEST_TMPDIR="$2"
    source "$1/tests/helpers/common.bash"; load_mocks
    printf "%s\n" "${_LOGINCTL_BIN}" "${_SYSTEMCTL_BIN}" "${_TMUX_BIN}" \
      "${_SYSTEMD_USER_DIR}" "${REPO_SESSIONS_FILE}"' \
    _ "${REPO_ROOT}" "${BATS_TEST_TMPDIR}/lm"
  [ "$status" -eq 0 ]
  local -a _l
  mapfile -t _l <<< "${output}"
  [ "${_l[0]}" = "${REPO_ROOT}/tests/mocks/loginctl" ]
  [ "${_l[1]}" = "${REPO_ROOT}/tests/stubs/systemctl-stub" ]
  [ "${_l[2]}" = "/usr/bin/false" ]
  [ "${_l[3]}" = "${BATS_TEST_TMPDIR}/lm/systemd-user" ]
  [ "${_l[4]}" = "${BATS_TEST_TMPDIR}/lm/repo-sessions-empty.sh" ]
  [ -f "${_l[4]}" ]
  [ ! -s "${_l[4]}" ]
}

@test "call site: run_setup_user calls install_repo_sessions" {
  run declare -f run_setup_user
  [ "$status" -eq 0 ]
  [[ "${output}" == *"install_repo_sessions"* ]]
}

@test "call site: run_doctor calls _doctor_check_repo_sessions" {
  run declare -f run_doctor
  [ "$status" -eq 0 ]
  [[ "${output}" == *"_doctor_check_repo_sessions"* ]]
}
