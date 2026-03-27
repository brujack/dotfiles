#!/usr/bin/env bash
# Shared BATS test helpers

# Absolute path to repo root (two levels up from tests/helpers/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Prepend tests/mocks/ to PATH so mock executables shadow real ones
load_mocks() {
  export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
}

# Source setup_env.sh — the sourcing guard prevents main body execution
load_setup_env() {
  source "${REPO_ROOT}/setup_env.sh"
  export BATS_VER  # export so mock scripts can reference it
}
