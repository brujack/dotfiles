#!/usr/bin/env bash
# Shared BATS test helpers

# Absolute path to repo root (two levels up from tests/helpers/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Prepend tests/mocks/ to PATH so mock executables shadow real ones
load_mocks() {
  export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
  # Default pyenv-which to the mock python so run_update's pip section never
  # shells out to real python3/pip on dev machines (real pip is slow, hits the
  # network, and mutates the ansible venv). Individual tests may override it.
  export MOCK_PYENV_WHICH_STDOUT="${REPO_ROOT}/tests/mocks/python"
}

# Source setup_env.sh — the sourcing guard prevents main body execution
load_setup_env() {
  source "${REPO_ROOT}/setup_env.sh"
  export BATS_VER  # export so mock scripts can reference it
}
