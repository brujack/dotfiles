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

# ── update_rust ──────────────────────────────────────────────────────────────

@test "update_rust: skips when UBUNTU not set" {
  unset UBUNTU
  export HAS_RUST=1
  run update_rust
  [ "$status" -eq 0 ]
  ! grep -q "rustup" "${MOCK_CALLS_FILE:-/dev/null}"
}

@test "update_rust: calls ~/.cargo/bin/rustup when it exists" {
  export UBUNTU=1
  export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
  grep -q "rustup component add" "${MOCK_CALLS_FILE}"
}

@test "update_rust: uses PATH rustup when ~/.cargo/bin/rustup is missing" {
  export UBUNTU=1
  export HAS_RUST=1
  # No ~/.cargo/bin/rustup in fake HOME; tests/mocks/rustup is in PATH via load_mocks
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
}

@test "update_rust: logs warning when rustup not found" {
  export UBUNTU=1
  export HAS_RUST=1
  # Restrict PATH so command -v rustup fails (no mocks, no ~/.cargo/bin/rustup)
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run update_rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"rustup not found"* ]]
}

@test "update_rust: updates nextest when rustup found and cargo-nextest available" {
  export UBUNTU=1
  export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  # Create cargo-nextest stub in .cargo/bin so command -v finds it
  printf '#!/usr/bin/env bash\n' > "${HOME}/.cargo/bin/cargo-nextest"
  chmod +x "${HOME}/.cargo/bin/cargo-nextest"
  export PATH="${HOME}/.cargo/bin:${PATH}"
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "get.nexte.st" "${MOCK_CALLS_FILE}"
}

@test "update_rust: skips nextest update when rustup not found" {
  export UBUNTU=1
  export HAS_RUST=1
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run update_rust
  [ "$status" -eq 0 ]
  ! grep -q "get.nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
}

# ── clone_personal_repos ─────────────────────────────────────────────────────

@test "clone_personal_repos: skips git clone when dotfiles dir exists" {
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  mkdir -p "${PERSONAL_GITREPOS}/dotfiles"
  run clone_personal_repos
  [ "$status" -eq 0 ]
  ! grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
}

@test "clone_personal_repos: calls git clone for dotfiles when dir missing" {
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  mkdir -p "${PERSONAL_GITREPOS}"
  run clone_personal_repos
  [ "$status" -eq 0 ]
  grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
}
