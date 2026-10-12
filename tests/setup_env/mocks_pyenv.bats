#!/usr/bin/env bats
# Contract of tests/mocks/pyenv's `install` and `commands` handling: the mock
# creates the interpreter only inside a bats HOME, honours -s, and can be told
# to fail through a file under HOME (survives `env -i`).

load '../helpers/common.bash'

setup() {
  MOCK="${BATS_TEST_DIRNAME}/../mocks/pyenv"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  unset MOCK_PYENV_EXIT MOCK_PYENV_COMMANDS
  OUTSIDE=""
}

teardown() {
  [[ -n "${OUTSIDE}" ]] && rm -rf "${OUTSIDE}"
  return 0
}

@test "pyenv mock: install creates an executable bin/python" {
  run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 0 ]
  [ -x "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: install -s with an existing bare version dir creates nothing" {
  mkdir -p "${HOME}/.pyenv/versions/3.99.1"
  run "${MOCK}" install -s -v 3.99.1
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: install -s without an existing dir still creates the interpreter" {
  run "${MOCK}" install -s -v 3.99.1
  [ "$status" -eq 0 ]
  [ -x "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: failure file sets the exit code and creates nothing" {
  printf '5' > "${HOME}/.mock-pyenv-install-exit"
  run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 5 ]
  [ ! -e "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: MOCK_PYENV_EXIT fails install and creates nothing" {
  MOCK_PYENV_EXIT=4 run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 4 ]
  [ ! -e "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: an existing interpreter is never overwritten" {
  mkdir -p "${HOME}/.pyenv/versions/3.99.1/bin"
  printf 'keep' > "${HOME}/.pyenv/versions/3.99.1/bin/python"
  run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 0 ]
  [ "$(cat "${HOME}/.pyenv/versions/3.99.1/bin/python")" = "keep" ]
}

@test "pyenv mock: declines to create anything outside a bats HOME" {
  OUTSIDE="$(mktemp -d /tmp/mpyX.XXXXXX)"
  [[ "${OUTSIDE}" != *bats-run-* ]]
  HOME="${OUTSIDE}" run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 0 ]
  [ ! -e "${OUTSIDE}/.pyenv/versions/3.99.1/bin/python" ]
  [[ "$output" == *"declined to create interpreter"* ]]
  # positive control: same call under the bats HOME creates the file
  run "${MOCK}" install -v 3.99.1
  [ -x "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: works under env -i (HOME-keyed, not PATH or PYENV_ROOT)" {
  run env -i HOME="${HOME}" PATH=/usr/bin:/bin "${MOCK}" install -s -v 3.99.1
  [ "$status" -eq 0 ]
  [ -x "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: commands prints MOCK_PYENV_COMMANDS" {
  MOCK_PYENV_COMMANDS=$'install\nupdate' run "${MOCK}" commands
  [ "$status" -eq 0 ]
  [ "$output" = $'install\nupdate' ]
}

@test "pyenv mock: commands prints nothing when unset" {
  run "${MOCK}" commands
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pyenv mock: env -i without MOCK_CALLS_FILE logs under the bats HOME" {
  run env -i HOME="${HOME}" PATH=/usr/bin:/bin "${MOCK}" install -s -v 3.99.1
  [ "$status" -eq 0 ]
  grep -q 'pyenv install -s -v 3.99.1' "${HOME}/.mock_calls"
}

@test "pyenv mock: empty failure file is rejected with rc 1" {
  : > "${HOME}/.mock-pyenv-install-exit"
  run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"mock pyenv: invalid failure file content ''"* ]]
  [ ! -e "${HOME}/.pyenv/versions/3.99.1/bin/python" ]
}

@test "pyenv mock: out-of-range failure file is rejected with rc 1" {
  printf '300' > "${HOME}/.mock-pyenv-install-exit"
  run "${MOCK}" install -v 3.99.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"mock pyenv: invalid failure file content '300'"* ]]
}

@test "pyenv mock: version containing a slash is rejected, nothing created" {
  run "${MOCK}" install ../../x
  [ "$status" -eq 1 ]
  [[ "$output" == *"mock pyenv: invalid version '../../x'"* ]]
  [ ! -e "${HOME}/.pyenv/versions" ]
  [ ! -e "${BATS_TEST_TMPDIR}/x" ]
}

@test "pyenv mock: version starting with a dash is rejected" {
  run "${MOCK}" install -v
  [ "$status" -eq 1 ]
  [[ "$output" == *"mock pyenv: invalid version '-v'"* ]]
}

@test "pyenv mock: failure file with a leading zero is read as base 10" {
  printf '08' > "${HOME}/.mock-pyenv-install-exit"
  run --separate-stderr "${MOCK}" install -v 3.99.1
  [ "$status" -eq 8 ]
  [ -z "$stderr" ]
  printf '099' > "${HOME}/.mock-pyenv-install-exit"
  run --separate-stderr "${MOCK}" install -v 3.99.1
  [ "$status" -eq 99 ]
  [ -z "$stderr" ]
}
