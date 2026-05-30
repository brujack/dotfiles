#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export _UPDATE_TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
}

teardown() {
  :
}

# ── _update_diff_lines ────────────────────────────────────────────────────────

@test "_update_diff_lines returns changed lines between pre and post" {
  printf "git 2.44.0\nwget 1.21.3\ncurl 8.6.0\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.45.0\nwget 1.21.3\ncurl 8.7.1\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git 2.45.0"* ]]
  [[ "$output" == *"curl 8.7.1"* ]]
  [[ "$output" != *"wget"* ]]
}

@test "_update_diff_lines returns empty when no changes" {
  printf "git 2.44.0\nwget 1.21.3\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.44.0\nwget 1.21.3\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_update_diff_lines returns new lines added in post" {
  printf "git 2.44.0\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.44.0\nnode 20.12.0\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node 20.12.0"* ]]
}

# ── _update_snapshot ──────────────────────────────────────────────────────────

@test "_update_snapshot writes command stdout to pre_SECTION file" {
  _update_snapshot "testcmd" printf "hello world\n"
  [ -f "${_UPDATE_TMPDIR}/pre_testcmd" ]
  grep -q "hello world" "${_UPDATE_TMPDIR}/pre_testcmd"
}

@test "_update_snapshot overwrites existing snapshot file" {
  printf "old\n" > "${_UPDATE_TMPDIR}/pre_testcmd"
  _update_snapshot "testcmd" printf "new\n"
  grep -q "new" "${_UPDATE_TMPDIR}/pre_testcmd"
  ! grep -q "old" "${_UPDATE_TMPDIR}/pre_testcmd"
}

# ── _update_git_diff ──────────────────────────────────────────────────────────

@test "_update_git_diff returns commit log between old SHA and HEAD" {
  local _repo="${BATS_TEST_TMPDIR}/gitrepo"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'first commit'
    printf 'b\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'second commit'
  "
  local _old_sha
  _old_sha=$(bash -c "export PATH='${clean_path}'; git -C '${_repo}' log --format='%H' | tail -1")
  run bash -c "export PATH='${clean_path}'; source '${REPO_ROOT}/lib/update_summary.sh'; _update_git_diff '${_repo}' '${_old_sha}'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"second commit"* ]]
  [[ "$output" != *"first commit"* ]]
}

@test "_update_git_diff returns empty when no new commits" {
  local _repo="${BATS_TEST_TMPDIR}/gitrepo2"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'first commit'
  "
  local _sha
  _sha=$(bash -c "export PATH='${clean_path}'; git -C '${_repo}' rev-parse HEAD")
  run bash -c "export PATH='${clean_path}'; source '${REPO_ROOT}/lib/update_summary.sh'; _update_git_diff '${_repo}' '${_sha}'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── _update_skip ──────────────────────────────────────────────────────────────

@test "_update_skip writes SKIP status and reason" {
  _update_skip "mas" "--brew-only flag set"
  [ -f "${_UPDATE_TMPDIR}/status_mas" ]
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_mas"
  [ -f "${_UPDATE_TMPDIR}/result_mas" ]
  grep -q "\-\-brew-only flag set" "${_UPDATE_TMPDIR}/result_mas"
}

# ── _update_record_start ──────────────────────────────────────────────────────

@test "_update_record_start creates pre-snapshot for brew section" {
  export MOCK_BREW_LIST_FORMULA="git wget"
  export MOCK_BREW_LIST_CASK="docker"
  _update_record_start "brew"
  [ -f "${_UPDATE_TMPDIR}/pre_brew_formula" ]
  [ -f "${_UPDATE_TMPDIR}/pre_brew_cask" ]
}

@test "_update_record_start creates pre-snapshot for gems section" {
  _update_record_start "gems"
  [ -f "${_UPDATE_TMPDIR}/pre_gems" ]
}

@test "_update_record_start records git SHA for oh-my-zsh section" {
  local _repo="${BATS_TEST_TMPDIR}/.oh-my-zsh"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'init'
  "
  _update_record_start "oh-my-zsh"
  [ -f "${_UPDATE_TMPDIR}/pre_oh-my-zsh" ]
}

@test "_update_record_start creates pre-snapshot for claude section" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="    Version: 5.0.7"
  _update_record_start "claude"
  [ -f "${_UPDATE_TMPDIR}/pre_claude" ]
  grep -q "Version:" "${_UPDATE_TMPDIR}/pre_claude"
}

@test "_update_record_start creates pre-snapshot for softwareupdate section" {
  export MOCK_SOFTWAREUPDATE_LIST_OUTPUT="* Label: Xcode-14.3"
  _update_record_start "softwareupdate"
  [ -f "${_UPDATE_TMPDIR}/pre_softwareupdate" ]
  grep -q "Xcode-14.3" "${_UPDATE_TMPDIR}/pre_softwareupdate"
}

@test "_update_record_start records no softwareupdate updates when none pending" {
  export MOCK_SOFTWAREUPDATE_LIST_OUTPUT=""
  _update_record_start "softwareupdate"
  [ -f "${_UPDATE_TMPDIR}/pre_softwareupdate" ]
  [ ! -s "${_UPDATE_TMPDIR}/pre_softwareupdate" ]
}

@test "_update_record_start apt creates pre_apt on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3
git 2.43.0-1ubuntu7"
  _update_record_start "apt"
  [ -f "${_UPDATE_TMPDIR}/pre_apt" ]
  grep -q "curl" "${_UPDATE_TMPDIR}/pre_apt"
}

@test "_update_record_start apt writes SKIP when not Ubuntu" {
  unset UBUNTU LINUX
  export MACOS=1
  _update_record_start "apt"
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_start snap creates pre_snap on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export MOCK_SNAP_LIST_OUTPUT="Name    Version
firefox 124.0"
  _update_record_start "snap"
  [ -f "${_UPDATE_TMPDIR}/pre_snap" ]
}

@test "_update_record_start snap writes SKIP when not Ubuntu" {
  unset UBUNTU LINUX
  export MACOS=1
  _update_record_start "snap"
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_snap"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_snap"
}

# ── _update_record_end ────────────────────────────────────────────────────────

@test "_update_record_end with exit 0 writes OK status" {
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK=""
  _update_record_end "brew" 0
  [ -f "${_UPDATE_TMPDIR}/status_brew" ]
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
}

@test "_update_record_end with exit 1 writes FAIL status" {
  _update_record_end "claude" 1
  grep -q "FAIL" "${_UPDATE_TMPDIR}/status_claude"
  grep -q "exit 1" "${_UPDATE_TMPDIR}/result_claude"
}

@test "_update_record_end diffs brew formulae and reports changes" {
  printf "git\nwget\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git wget node"
  export MOCK_BREW_LIST_CASK=""
  _update_record_end "brew" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "node" "${_UPDATE_TMPDIR}/result_brew"
}

@test "_update_record_end reports no changes when nothing changed" {
  printf "git\ndocker\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git docker"
  export MOCK_BREW_LIST_CASK=""
  _update_record_end "brew" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_brew"
}

@test "_update_record_end pip reports single package without trailing newline" {
  # Python's "\n".join([pkg]) produces no trailing newline — wc -l would return 0
  # grep -c . correctly counts 1 non-empty line regardless of trailing newline
  printf "requests" > "${_UPDATE_TMPDIR}/pip_outdated"
  _update_record_end "pip" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_pip"
  grep -q "requests" "${_UPDATE_TMPDIR}/result_pip"
}

@test "_update_record_end pip reports multiple packages" {
  printf "requests\nboto3\nansible" > "${_UPDATE_TMPDIR}/pip_outdated"
  _update_record_end "pip" 0
  grep -q "3 package" "${_UPDATE_TMPDIR}/result_pip"
}

@test "_update_record_end diffs gems and reports gem names" {
  export MOCK_GEM_LIST_OUTPUT="rake (13.0.1)"
  _update_record_start "gems"
  export MOCK_GEM_LIST_OUTPUT="rake (13.0.6, 13.0.1)"
  _update_record_end "gems" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_gems"
  grep -q "rake" "${_UPDATE_TMPDIR}/result_gems"
}

@test "_update_record_end reports no changes for gems when versions unchanged" {
  export MOCK_GEM_LIST_OUTPUT="rake (13.0.1)"
  _update_record_start "gems"
  _update_record_end "gems" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_gems"
}

@test "_update_record_end shows mas app names and versions in result" {
  printf "==> Updated Slack (4.40)\n" > "${_UPDATE_TMPDIR}/mas_upgrade_output"
  _update_record_end "mas" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_mas"
  grep -q "Slack (4.40)" "${_UPDATE_TMPDIR}/result_mas"
}

@test "_update_record_end shows no changes for mas when upgrade output has no updated lines" {
  printf "==> Updating mas packages\n" > "${_UPDATE_TMPDIR}/mas_upgrade_output"
  _update_record_end "mas" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_mas"
}

@test "_update_record_end shows softwareupdate labels in result" {
  export MOCK_SOFTWAREUPDATE_LIST_OUTPUT="* Label: Xcode-14.3"
  _update_record_start "softwareupdate"
  _update_record_end "softwareupdate" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_softwareupdate"
  grep -q "Xcode-14.3" "${_UPDATE_TMPDIR}/result_softwareupdate"
}

@test "_update_record_end reports no changes for softwareupdate when nothing pending" {
  export MOCK_SOFTWAREUPDATE_LIST_OUTPUT=""
  _update_record_start "softwareupdate"
  _update_record_end "softwareupdate" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_softwareupdate"
}

@test "_update_record_end diffs claude plugins and reports count when updated" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="    Version: 5.0.7"
  _update_record_start "claude"
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="    Version: 5.0.8"
  _update_record_end "claude" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_claude"
  grep -q "1 plugin" "${_UPDATE_TMPDIR}/result_claude"
}

@test "_update_record_end reports no changes for claude when versions unchanged" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="    Version: 5.0.7"
  _update_record_start "claude"
  _update_record_end "claude" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_claude"
}

# ── _update_summary ───────────────────────────────────────────────────────────

@test "_update_summary prints OK section with result" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "2 formulae (git 2.45.0, wget 1.22.0)\n" > "${_UPDATE_TMPDIR}/result_brew"
  local _s
  for _s in softwareupdate mas claude pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "not run\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"brew"* ]]
  [[ "$output" == *"2 formulae"* ]]
}

@test "_update_summary prints FAIL section with exit code" {
  printf "FAIL\n" > "${_UPDATE_TMPDIR}/status_claude"
  printf "exit 1 — see output above\n" > "${_UPDATE_TMPDIR}/result_claude"
  local _s
  for _s in brew softwareupdate mas pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"exit 1"* ]]
}

@test "_update_summary prints SKIP section with reason" {
  printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_mas"
  printf "%s\n" "--brew-only flag set" > "${_UPDATE_TMPDIR}/result_mas"
  local _s
  for _s in brew softwareupdate claude pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"[SKIP]"* ]]
  [[ "$output" == *"mas"* ]]
  [[ "$output" == *"--brew-only flag set"* ]]
}

@test "_update_summary prints totals line" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  printf "FAIL\n" > "${_UPDATE_TMPDIR}/status_claude"
  printf "exit 1\n" > "${_UPDATE_TMPDIR}/result_claude"
  printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_mas"
  printf "not needed\n" > "${_UPDATE_TMPDIR}/result_mas"
  local _s
  for _s in softwareupdate pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"8 OK"* ]]
  [[ "$output" == *"1 failed"* ]]
  [[ "$output" == *"1 skipped"* ]]
}

@test "_update_summary creates log file when missing" {
  rm -f "${UPDATE_LOG_PATH}"
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  [ -f "${UPDATE_LOG_PATH}" ]
}

@test "_update_summary appends to existing log file" {
  printf "previous run\n" > "${UPDATE_LOG_PATH}"
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  grep -q "previous run" "${UPDATE_LOG_PATH}"
  grep -q "Update Summary" "${UPDATE_LOG_PATH}"
}

@test "_update_summary writes separator before entry in log" {
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  head -1 "${UPDATE_LOG_PATH}" | grep -q "─"
}

@test "_update_summary does not warn 'Could not write' when no WARN detail output exists" {
  # Regression: group exit code was last-command exit (1 when _detail_output empty),
  # causing false "Could not write" warning even though the log write succeeded.
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" != *"Could not write"* ]]
}

@test "_update_summary skips sections with no status file" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew"* ]]
  [[ "$output" == *"1 OK"* ]]
}

# ── _update_record_end — SKIP guard ───────────────────────────────────────

@test "_update_record_end does not overwrite SKIP written by _update_record_start for apt" {
  _update_skip "apt" "not applicable"
  _update_record_end "apt" 0
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end does not overwrite SKIP written by _update_record_start for snap" {
  _update_skip "snap" "not applicable"
  _update_record_end "snap" 0
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_snap"
}

# ── _update_record_end — apt diff ─────────────────────────────────────────

@test "_update_record_end apt reports changed packages with name and version" {
  printf "curl 7.88.1-1ubuntu3\ngit 2.43.0-1ubuntu7\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3
git 2.44.0-1ubuntu7"
  _update_record_end "apt" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "git 2.44.0" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt reports no changes when packages unchanged" {
  printf "curl 7.88.1-1ubuntu3\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  _update_record_end "apt" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt reports updated when no pre-snapshot" {
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  _update_record_end "apt" 0
  grep -q "updated" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt writes FAIL on non-zero exit" {
  _update_record_end "apt" 1
  grep -q "FAIL" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "exit 1" "${_UPDATE_TMPDIR}/result_apt"
}

# ── _update_record_end — snap diff ────────────────────────────────────────

@test "_update_record_end snap reports changed packages with name and version" {
  printf "firefox 123.0\n" > "${_UPDATE_TMPDIR}/pre_snap"
  export MOCK_SNAP_LIST_OUTPUT="Name     Version
firefox  124.0"
  _update_record_end "snap" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_snap"
  grep -q "firefox 124.0" "${_UPDATE_TMPDIR}/result_snap"
}

@test "_update_record_end snap reports no changes when packages unchanged" {
  printf "firefox 124.0\n" > "${_UPDATE_TMPDIR}/pre_snap"
  export MOCK_SNAP_LIST_OUTPUT="Name     Version
firefox  124.0"
  _update_record_end "snap" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_snap"
}

# ── _update_record_end — apt reboot-required ──────────────────────────────

@test "_update_record_end apt appends reboot required when flag file exists" {
  printf "curl 7.88.1-1ubuntu3\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  local _reboot_file="${BATS_TEST_TMPDIR}/reboot-required"
  touch "${_reboot_file}"
  export _REBOOT_REQUIRED_PATH="${_reboot_file}"
  _update_record_end "apt" 0
  grep -q "reboot required" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt includes package name from reboot-required.pkgs" {
  printf "curl 7.88.1-1ubuntu3\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  local _reboot_file="${BATS_TEST_TMPDIR}/reboot-required"
  local _reboot_pkgs_file="${BATS_TEST_TMPDIR}/reboot-required.pkgs"
  touch "${_reboot_file}"
  printf "linux-image-6.8.0-58-generic\n" > "${_reboot_pkgs_file}"
  export _REBOOT_REQUIRED_PATH="${_reboot_file}"
  export _REBOOT_REQUIRED_PKGS_PATH="${_reboot_pkgs_file}"
  _update_record_end "apt" 0
  grep -q "linux-image-6.8.0-58-generic" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt reboot required without pkgs file shows generic message" {
  printf "curl 7.88.1-1ubuntu3\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  local _reboot_file="${BATS_TEST_TMPDIR}/reboot-required"
  touch "${_reboot_file}"
  export _REBOOT_REQUIRED_PATH="${_reboot_file}"
  unset _REBOOT_REQUIRED_PKGS_PATH
  _update_record_end "apt" 0
  grep -q "reboot required" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt no reboot warning when flag file absent" {
  printf "curl 7.88.1-1ubuntu3\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  export _REBOOT_REQUIRED_PATH="${BATS_TEST_TMPDIR}/no-such-file"
  _update_record_end "apt" 0
  ! grep -q "reboot required" "${_UPDATE_TMPDIR}/result_apt"
}

# ── _update_ok ───────────────────────────────────────────────────────────────

@test "_update_ok writes OK status and result files" {
  _update_ok "brew-drift" "formulae clean, taps clean"
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ "$(cat "${_UPDATE_TMPDIR}/result_brew-drift")" = "formulae clean, taps clean" ]
}

# ── _update_warn ─────────────────────────────────────────────────────────────

@test "_update_warn writes WARN status and result files" {
  _update_warn "brew-drift" "3 untracked formulae"
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  [ "$(cat "${_UPDATE_TMPDIR}/result_brew-drift")" = "3 untracked formulae" ]
}

# ── _update_summary WARN support ─────────────────────────────────────────────

@test "_update_summary: WARN section printed with [WARN] prefix" {
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_brew-drift"
  printf "2 untracked formulae\n" > "${_UPDATE_TMPDIR}/result_brew-drift"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] brew-drift"* ]]
  [[ "$output" == *"2 untracked formulae"* ]]
}

@test "_update_summary: WARN counted in warnings, not failures" {
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_brew-drift"
  printf "1 untracked formula\n" > "${_UPDATE_TMPDIR}/result_brew-drift"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 warnings"* ]]
  [[ "$output" != *"1 failed"* ]]
}

@test "_update_summary: detail block printed after table" {
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_brew-drift"
  printf "1 untracked formulae\n" > "${_UPDATE_TMPDIR}/result_brew-drift"
  printf "brew-drift details:\n  Untracked:\n    bat\n" \
    > "${_UPDATE_TMPDIR}/detail_brew-drift"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew-drift details:"* ]]
  [[ "$output" == *"bat"* ]]
}

@test "_update_summary: no detail block when no detail file exists" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" != *"details:"* ]]
}

# ── _update_record_start tpm/tfenv/zsh-autosuggestions ───────────────────────

@test "_update_record_start tpm: creates pre-snapshot file" {
  export HOME="${BATS_TEST_TMPDIR}"
  _update_record_start "tpm"
  [ -f "${_UPDATE_TMPDIR}/pre_tpm" ]
}

@test "_update_record_start tfenv: creates pre-snapshot file" {
  export HOME="${BATS_TEST_TMPDIR}"
  _update_record_start "tfenv"
  [ -f "${_UPDATE_TMPDIR}/pre_tfenv" ]
}

@test "_update_record_start zsh-autosuggestions: creates pre-snapshot file" {
  export HOME="${BATS_TEST_TMPDIR}"
  _update_record_start "zsh-autosuggestions"
  [ -f "${_UPDATE_TMPDIR}/pre_zsh-autosuggestions" ]
}

# ── _update_record_start npm ──────────────────────────────────────────────────

@test "_update_record_start npm: creates pre-snapshot file" {
  export MOCK_NPM_LIST_OUTPUT="── firecrawl-mcp@0.1.0"
  _update_record_start "npm"
  [ -f "${_UPDATE_TMPDIR}/pre_npm" ]
}

# ── _update_record_end npm ────────────────────────────────────────────────────

@test "_update_record_end npm: reports package updates when changed" {
  export MOCK_NPM_LIST_OUTPUT="── firecrawl-mcp@0.1.0"
  _update_record_start "npm"
  export MOCK_NPM_LIST_OUTPUT="── firecrawl-mcp@0.2.0"
  _update_record_end "npm" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_npm"
  grep -q "package(s)" "${_UPDATE_TMPDIR}/result_npm"
  grep -q "firecrawl-mcp" "${_UPDATE_TMPDIR}/result_npm"
}

@test "_update_record_end npm: reports no changes when packages unchanged" {
  export MOCK_NPM_LIST_OUTPUT="── firecrawl-mcp@0.1.0"
  _update_record_start "npm"
  _update_record_end "npm" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_npm"
}

@test "_update_record_end npm: reports updated when no pre-snapshot" {
  _update_record_end "npm" 0
  grep -q "updated" "${_UPDATE_TMPDIR}/result_npm"
  grep -q "OK" "${_UPDATE_TMPDIR}/status_npm"
}

# ── _update_record_end git-SHA group ─────────────────────────────────────────

@test "_update_record_end tpm: reports commit count when updates found" {
  printf "abc1234\n" > "${_UPDATE_TMPDIR}/pre_tpm"
  _update_git_diff() { printf "abc1234 update tpm to latest\n"; }
  _update_record_end "tpm" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_tpm"
  grep -q "1 commit(s)" "${_UPDATE_TMPDIR}/result_tpm"
}

@test "_update_record_end tfenv: reports no changes when no new commits" {
  printf "abc1234\n" > "${_UPDATE_TMPDIR}/pre_tfenv"
  _update_record_end "tfenv" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_tfenv"
}

@test "_update_record_end zsh-autosuggestions: reports no changes when no pre-snapshot" {
  _update_record_end "zsh-autosuggestions" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_zsh-autosuggestions"
}

# ── _update_record_end default case ──────────────────────────────────────────

@test "_update_record_end: default case reports updated for untracked section" {
  _update_record_end "cheat.sh" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_cheat.sh"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_cheat.sh"
}

@test "_update_record_end brew: reports cask-only update when formulae unchanged" {
  printf "git\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "old-app\n" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK="new-app"
  _update_record_end "brew" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "1 cask(s)" "${_UPDATE_TMPDIR}/result_brew"
  grep -q "new-app" "${_UPDATE_TMPDIR}/result_brew"
  [[ "$(<"${_UPDATE_TMPDIR}/result_brew")" != *"formulae"* ]]
}

@test "_update_record_end brew: reports both formulae and cask updates" {
  printf "git 2.44.0\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "old-app\n" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git 2.45.0"
  export MOCK_BREW_LIST_CASK="new-app"
  _update_record_end "brew" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "formulae" "${_UPDATE_TMPDIR}/result_brew"
  grep -q "cask(s)" "${_UPDATE_TMPDIR}/result_brew"
}

@test "_update_record_end gems: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_gems"
  _update_record_end "gems" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_gems"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_gems"
}

@test "_update_record_end pip: reports no changes when pip_outdated is empty" {
  touch "${_UPDATE_TMPDIR}/pip_outdated"
  _update_record_end "pip" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_pip"
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_pip"
}

@test "_update_record_end pip: reports updated when no pip_outdated file" {
  rm -f "${_UPDATE_TMPDIR}/pip_outdated"
  _update_record_end "pip" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_pip"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_pip"
}

@test "_update_record_end zsh-autosuggestions: reports commit count when pre-snapshot and updates found" {
  printf "abc1234\n" > "${_UPDATE_TMPDIR}/pre_zsh-autosuggestions"
  _update_git_diff() { printf "abc1234 update zsh-autosuggestions\n"; }
  _update_record_end "zsh-autosuggestions" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_zsh-autosuggestions"
  grep -q "1 commit(s)" "${_UPDATE_TMPDIR}/result_zsh-autosuggestions"
}

@test "_update_record_end softwareupdate: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_softwareupdate"
  _update_record_end "softwareupdate" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_softwareupdate"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_softwareupdate"
}

@test "_update_record_end claude: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_claude"
  _update_record_end "claude" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_claude"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_claude"
}

@test "_update_record_end snap: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_snap"
  _update_record_end "snap" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_snap"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_snap"
}
