#!/usr/bin/env bats
# Scoped failure knobs on the wget, curl, apt, apt-get, nala and mv mocks.
# Each knob fails only the calls it names, so a test can break one step of a
# multi-step installer while the rest succeed. Every test pairs the matching
# (failing) call with a non-matching call in the same test as a positive
# control: a knob that failed everything would otherwise pass.

load '../helpers/common.bash'

setup() {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  unset MOCK_WGET_EXIT MOCK_WGET_FILE MOCK_WGET_FAIL_URL \
    MOCK_CURL_EXIT MOCK_CURL_HTTP_STATUS MOCK_CURL_STDOUT MOCK_CURL_FAIL_URL \
    MOCK_APT_EXIT MOCK_APT_ONLY_EXIT MOCK_NALA_EXIT MOCK_APT_FAIL_SUBCMD \
    MOCK_MV_EXIT MOCK_MV_FAIL_ARGS
  MOCKS="${REPO_ROOT}/tests/mocks"
}

@test "wget mock: MOCK_WGET_FAIL_URL fails the matching URL with rc 4 and a 0-byte target" {
  export MOCK_WGET_FAIL_URL="bad.example"
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/bad" https://bad.example/x.deb
  [ "$status" -eq 4 ]
  [ -f "${BATS_TEST_TMPDIR}/bad" ]
  [ ! -s "${BATS_TEST_TMPDIR}/bad" ]
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/good" https://good.example/x.deb
  [ "$status" -eq 0 ]
  [ -f "${BATS_TEST_TMPDIR}/good" ]
  grep -q 'bad.example' "${MOCK_CALLS_FILE}"
}

@test "wget mock: MOCK_WGET_FAIL_URL truncates a target that MOCK_WGET_FILE would fill" {
  printf 'payload' > "${BATS_TEST_TMPDIR}/fixture"
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/fixture"
  export MOCK_WGET_FAIL_URL="bad.example"
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/bad" https://bad.example/x.deb
  [ "$status" -eq 4 ]
  [ ! -s "${BATS_TEST_TMPDIR}/bad" ]
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/good" https://good.example/x.deb
  [ "$status" -eq 0 ]
  [ -s "${BATS_TEST_TMPDIR}/good" ]
}

@test "wget mock: a set MOCK_WGET_EXIT wins over MOCK_WGET_FAIL_URL; unset, the URL knob gives rc 4" {
  export MOCK_WGET_FAIL_URL="bad.example"
  export MOCK_WGET_EXIT=8
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/a" https://bad.example/x.deb
  [ "$status" -eq 8 ]
  export MOCK_WGET_EXIT=0
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/b" https://bad.example/x.deb
  [ "$status" -eq 0 ]
  unset MOCK_WGET_EXIT
  run "${MOCKS}/wget" -O "${BATS_TEST_TMPDIR}/c" https://bad.example/x.deb
  [ "$status" -eq 4 ]
}

@test "curl mock: a set MOCK_CURL_EXIT wins over MOCK_CURL_FAIL_URL; unset, the URL knob gives rc 22" {
  export MOCK_CURL_FAIL_URL="bad.example"
  export MOCK_CURL_EXIT=7
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/a" https://bad.example/k
  [ "$status" -eq 7 ]
  export MOCK_CURL_EXIT=0
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/b" https://bad.example/k
  [ "$status" -eq 0 ]
  unset MOCK_CURL_EXIT
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/c" https://bad.example/k
  [ "$status" -eq 22 ]
}

@test "curl mock: MOCK_CURL_FAIL_URL fails the matching URL with rc 22 and a 0-byte target" {
  export MOCK_CURL_FAIL_URL="bad.example"
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/bad" https://bad.example/k.asc
  [ "$status" -eq 22 ]
  [ -f "${BATS_TEST_TMPDIR}/bad" ]
  [ ! -s "${BATS_TEST_TMPDIR}/bad" ]
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/good" https://good.example/k.asc
  [ "$status" -eq 0 ]
  [ -f "${BATS_TEST_TMPDIR}/good" ]
  grep -q 'bad.example' "${MOCK_CALLS_FILE}"
}

@test "curl mock: MOCK_CURL_FAIL_URL does not write MOCK_CURL_STDOUT to the failed target" {
  export MOCK_CURL_STDOUT="content"
  export MOCK_CURL_FAIL_URL="bad.example"
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/bad" https://bad.example/k.asc
  [ "$status" -eq 22 ]
  [ ! -s "${BATS_TEST_TMPDIR}/bad" ]
  run "${MOCKS}/curl" -fsS -o "${BATS_TEST_TMPDIR}/good" https://good.example/k.asc
  [ "$status" -eq 0 ]
  [ -s "${BATS_TEST_TMPDIR}/good" ]
}

@test "apt mock: MOCK_APT_FAIL_SUBCMD=update fails update with rc 100 but not install" {
  export MOCK_APT_FAIL_SUBCMD=update
  run "${MOCKS}/apt" update
  [ "$status" -eq 100 ]
  run "${MOCKS}/apt" install foo
  [ "$status" -eq 0 ]
  grep -q '^apt update$' "${MOCK_CALLS_FILE}"
}

@test "apt mock: MOCK_APT_FAIL_SUBCMD finds the subcommand after leading options" {
  export MOCK_APT_FAIL_SUBCMD=install
  run "${MOCKS}/apt" -y install x
  [ "$status" -eq 100 ]
  run "${MOCKS}/apt" -y update
  [ "$status" -eq 0 ]
}

@test "apt mock: MOCK_APT_FAIL_SUBCMD still strips APT_CONFFILE_OPTS from the record" {
  export MOCK_APT_FAIL_SUBCMD=install
  run "${MOCKS}/apt" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install x
  [ "$status" -eq 100 ]
  grep -q '^apt install x$' "${MOCK_CALLS_FILE}"
  run "${MOCKS}/apt" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold update
  [ "$status" -eq 0 ]
}

@test "apt-get mock: MOCK_APT_FAIL_SUBCMD fails the named subcommand only" {
  export MOCK_APT_FAIL_SUBCMD=update
  run "${MOCKS}/apt-get" update
  [ "$status" -eq 100 ]
  run "${MOCKS}/apt-get" -y install x
  [ "$status" -eq 0 ]
  export MOCK_APT_FAIL_SUBCMD=install
  run "${MOCKS}/apt-get" -y install x
  [ "$status" -eq 100 ]
  run "${MOCKS}/apt-get" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install x
  [ "$status" -eq 100 ]
  run "${MOCKS}/apt-get" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold update
  [ "$status" -eq 0 ]
}

@test "nala mock: MOCK_APT_FAIL_SUBCMD fails the named subcommand only" {
  export MOCK_APT_FAIL_SUBCMD=update
  run "${MOCKS}/nala" update
  [ "$status" -eq 100 ]
  run "${MOCKS}/nala" install x
  [ "$status" -eq 0 ]
  export MOCK_APT_FAIL_SUBCMD=install
  run "${MOCKS}/nala" -y install x
  [ "$status" -eq 100 ]
  run "${MOCKS}/nala" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install x
  [ "$status" -eq 100 ]
  run "${MOCKS}/nala" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold update
  [ "$status" -eq 0 ]
}

@test "mv mock: MOCK_MV_FAIL_ARGS fails a matching call, records it, and leaves the source" {
  printf 'a' > "${BATS_TEST_TMPDIR}/src"
  printf 'b' > "${BATS_TEST_TMPDIR}/src2"
  export MOCK_MV_FAIL_ARGS="${BATS_TEST_TMPDIR}/src "
  run "${MOCKS}/mv" "${BATS_TEST_TMPDIR}/src" "${BATS_TEST_TMPDIR}/dst"
  [ "$status" -eq 1 ]
  [ -f "${BATS_TEST_TMPDIR}/src" ]
  [ ! -e "${BATS_TEST_TMPDIR}/dst" ]
  grep -q "^mv ${BATS_TEST_TMPDIR}/src " "${MOCK_CALLS_FILE}"
  run "${MOCKS}/mv" "${BATS_TEST_TMPDIR}/src2" "${BATS_TEST_TMPDIR}/dst2"
  [ "$status" -eq 0 ]
  [ -f "${BATS_TEST_TMPDIR}/dst2" ]
  [ ! -e "${BATS_TEST_TMPDIR}/src2" ]
}
