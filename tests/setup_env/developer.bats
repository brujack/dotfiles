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

@test "update_rust: does not call nextest curl when rustup found (brew manages updates)" {
  export UBUNTU=1
  export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  printf '#!/usr/bin/env bash\n' > "${HOME}/.cargo/bin/cargo-nextest"
  chmod +x "${HOME}/.cargo/bin/cargo-nextest"
  export PATH="${HOME}/.cargo/bin:${PATH}"
  run update_rust
  [ "$status" -eq 0 ]
  run grep "nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
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

# ── setup_ansible — Linux branch ─────────────────────────────────────────────

@test "setup_ansible: calls pyenv update on Linux when Python version absent" {
  export LINUX=1; unset MACOS
  export HAS_DEVTOOLS=1
  run setup_ansible
  grep -q "pyenv update" "${MOCK_CALLS_FILE}"
}

@test "the manifest still declares passlib" {
  # passlib backs ansible's password_hash filter; it has no other consumer and
  # is the package most likely to look droppable to someone pruning the list
  grep -q '"passlib"' "${BATS_TEST_DIRNAME}/../../pyproject.toml"
}

# ── declared package set ──────────────────────────────────────────────────────
#
# The package set now lives in one place. wheel's deletion is asserted against
# that declaration rather than against a pip invocation, because there is no
# longer a pip invocation to inspect. The positive control is a package that
# must still be declared, so a renamed or moved manifest fails loudly instead
# of making the absence assertion vacuous.

@test "pyproject.toml declares the package set and no longer carries wheel" {
  local _manifest="${BATS_TEST_DIRNAME}/../../pyproject.toml"
  [ -f "${_manifest}" ]
  grep -q '"ansible-lint"' "${_manifest}"
  if grep -qE '^\s*"wheel"' "${_manifest}"; then
    printf "wheel is still declared in pyproject.toml\n" >&2
    return 1
  fi
}

@test "the package set is declared once — not in lib/developer.sh" {
  if grep -q '_pip_pkgs' "${BATS_TEST_DIRNAME}/../../lib/developer.sh"; then
    printf "lib/developer.sh still carries a hardcoded package array\n" >&2
    return 1
  fi
}

# ── uv-managed dependency install (step 4) ───────────────────────────────────
#
# Both venv-creating sites install from the committed lock rather than from a
# hardcoded array. Each absence assertion carries a positive control, and the
# missing-uv cases assert the function FAILS rather than silently installing
# nothing — a new hard dependency with no guard is worse than the duplication
# it replaces.

@test "setup_ansible: installs from the lock, not a package array" {
  export LINUX=1; unset MACOS
  export HAS_DEVTOOLS=1
  run setup_ansible
  grep -q "uv sync" "${MOCK_CALLS_FILE}"
  if grep -q "pip install" "${MOCK_CALLS_FILE}"; then
    printf "still installing from a hardcoded package list\n" >&2
    return 1
  fi
}

@test "setup_ansible: uv sync targets the ansible venv" {
  export LINUX=1; unset MACOS
  export HAS_DEVTOOLS=1
  run setup_ansible
  grep -q "uv sync.*--group runtime" "${MOCK_CALLS_FILE}"
  grep -q "uv sync.*--group test-lint" "${MOCK_CALLS_FILE}"
  grep -q "uv sync.*--frozen" "${MOCK_CALLS_FILE}"
}

@test "recreate_python_venv: installs from the lock, not a package array" {
  export LINUX=1; unset MACOS
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  run recreate_python_venv ansible
  grep -q "uv sync" "${MOCK_CALLS_FILE}"
  if grep -q "pip install" "${MOCK_CALLS_FILE}"; then
    printf "still installing from a hardcoded package list\n" >&2
    return 1
  fi
}

@test "recreate_python_venv: fails loudly when uv is not installed" {
  export LINUX=1; unset MACOS
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export UV_BIN="${BATS_TEST_TMPDIR}/no-such-uv"
  run recreate_python_venv ansible
  [ "${status}" -ne 0 ]
  if [[ "${output}" != *"uv"* ]]; then
    printf "failed without naming uv as the missing dependency\n" >&2
    return 1
  fi
}

@test "resolve_uv falls back to a brew prefix when uv is not on PATH" {
  # This is the branch resolve_uv exists for: a git hook or cron job whose PATH
  # never sourced a profile and so cannot see the brew prefix. Stripping the
  # mocks dir is what makes the fallback reachable — with the mock present the
  # `command -v` branch answers first and this path never runs.
  unset UV_BIN
  local _found
  _found="$(PATH="/usr/bin:/bin" resolve_uv)" || _found=""
  if [[ -z "${_found}" ]]; then
    printf "resolve_uv found nothing with a bare PATH; the prefix fallback is dead\n" >&2
    return 1
  fi
  [[ "${_found}" == /* ]]
  [[ -x "${_found}" ]]
}

@test "resolve_uv prefers an explicit UV_BIN over PATH" {
  local _fake="${BATS_TEST_TMPDIR}/my-uv"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_fake}"; chmod +x "${_fake}"
  export UV_BIN="${_fake}"
  local _got
  _got="$(resolve_uv)"
  [ "${_got}" = "${_fake}" ]
}
