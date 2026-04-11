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

@test "_update_record_start creates no snapshot for claude section" {
  _update_record_start "claude"
  [ ! -f "${_UPDATE_TMPDIR}/pre_claude" ]
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

# ── _update_summary ───────────────────────────────────────────────────────────

@test "_update_summary prints OK section with result" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "2 formulae (git 2.45.0, wget 1.22.0)\n" > "${_UPDATE_TMPDIR}/result_brew"
  local _s
  for _s in softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
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
  for _s in brew softwareupdate mas pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
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
  for _s in brew softwareupdate claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
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
  for _s in softwareupdate pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"9 OK"* ]]
  [[ "$output" == *"1 failed"* ]]
  [[ "$output" == *"1 skipped"* ]]
}

@test "_update_summary creates log file when missing" {
  rm -f "${UPDATE_LOG_PATH}"
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  [ -f "${UPDATE_LOG_PATH}" ]
}

@test "_update_summary appends to existing log file" {
  printf "previous run\n" > "${UPDATE_LOG_PATH}"
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  grep -q "previous run" "${UPDATE_LOG_PATH}"
  grep -q "Update Summary" "${UPDATE_LOG_PATH}"
}

@test "_update_summary writes separator before entry in log" {
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  head -1 "${UPDATE_LOG_PATH}" | grep -q "─"
}

@test "_update_summary skips sections with no status file" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew"* ]]
  [[ "$output" == *"1 OK"* ]]
}
