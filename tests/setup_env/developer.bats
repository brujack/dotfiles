#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── setup_vim_plugins ────────────────────────────────────────────────────────

@test "setup_vim_plugins: creates .vim/plugged and .vim/autoload directories" {
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.vim/plugged" ]
  [ -d "${HOME}/.vim/autoload" ]
}

@test "setup_vim_plugins: downloads plug.vim when it does not exist" {
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  grep -q "curl.*plug.vim" "${MOCK_CALLS_FILE}"
}

@test "setup_vim_plugins: skips curl when plug.vim already exists" {
  mkdir -p "${HOME}/.vim/autoload"
  touch "${HOME}/.vim/autoload/plug.vim"
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  ! grep -q "curl.*plug.vim" "${MOCK_CALLS_FILE}"
}
