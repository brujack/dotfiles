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

# Assert a pattern is ABSENT from a file.
#
# Use this instead of `! grep -q ...`. A bare `!` only fails a bats test while
# it is the last command in the @test body — anywhere else the negation is
# silently ignored and the assertion cannot fail at all (shellcheck SC2314).
# Six assertions in this suite were inert for exactly that reason, each one the
# first of two consecutive negative checks, and each covering the "skips X"
# half of its test's claim. Failure output names what was actually found,
# which a bare `!` never did.
#
# Extra args are passed through to grep, so `refute_grep -E 'pat' file` works.
refute_grep() {
  local _pattern="$1" _file="$2"
  shift 2
  if grep -q "$@" -- "${_pattern}" "${_file}" 2>/dev/null; then
    printf 'expected no match for %s in %s, found:\n%s\n' \
      "${_pattern}" "${_file}" "$(grep "$@" -- "${_pattern}" "${_file}")" >&2
    return 1
  fi
}

# Source setup_env.sh — the sourcing guard prevents main body execution
load_setup_env() {
  source "${REPO_ROOT}/setup_env.sh"
  export BATS_VER  # export so mock scripts can reference it
}
