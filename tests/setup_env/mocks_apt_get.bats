#!/usr/bin/env bats
# Contract of the apt-get and lsb_release mocks' output knobs, and of the
# load_mocks defaults the HashiCorp apt step relies on. The step reads apt's
# stdout and stderr separately and the codename through `lsb_release -cs`, so
# each knob has to be observable from the right stream.

load '../helpers/common.bash'

setup() {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  unset MOCK_APT_GET_SOURCELIST_COPY MOCK_APT_GET_UPDATE_OUTPUT MOCK_APT_GET_INSTALL_OUTPUT \
    MOCK_APT_GET_INSTALL_MARK MOCK_APT_FAIL_SUBCMD MOCK_LSB_RELEASE_CS MOCK_LSB_RELEASE_RS
  printf 'W: warn line\nplain line\nE: err line\n' > "${BATS_TEST_TMPDIR}/out.txt"
}

@test "apt-get update: unset output knob prints the default line on stdout" {
  run --separate-stderr apt-get update
  [ "$status" -eq 0 ]
  [ "$output" = "Reading package lists..." ]
  [ -z "$stderr" ]
}

@test "apt-get update: W:/E: lines go to stderr and the rest to stdout" {
  export MOCK_APT_GET_UPDATE_OUTPUT="${BATS_TEST_TMPDIR}/out.txt"
  run --separate-stderr apt-get update
  [ "$status" -eq 0 ]
  [ "$output" = "plain line" ]
  [[ "$stderr" == *"W: warn line"* ]]
  [[ "$stderr" == *"E: err line"* ]]
  [[ "$stderr" != *"plain line"* ]]
}

@test "apt-get update: copies the Dir::Etc::sourcelist file to the copy knob" {
  printf 'deb http://example/ noble main\n' > "${BATS_TEST_TMPDIR}/src.list"
  export MOCK_APT_GET_SOURCELIST_COPY="${BATS_TEST_TMPDIR}/copy.list"
  run apt-get update -o Dir::Etc::sourcelist="${BATS_TEST_TMPDIR}/src.list"
  [ "$status" -eq 0 ]
  cmp "${BATS_TEST_TMPDIR}/src.list" "${BATS_TEST_TMPDIR}/copy.list"
}

@test "apt-get update: copy and output both happen before the forced failure" {
  printf 'line\n' > "${BATS_TEST_TMPDIR}/src.list"
  export MOCK_APT_GET_SOURCELIST_COPY="${BATS_TEST_TMPDIR}/copy.list"
  export MOCK_APT_GET_UPDATE_OUTPUT="${BATS_TEST_TMPDIR}/out.txt"
  export MOCK_APT_FAIL_SUBCMD=update
  run --separate-stderr apt-get update -o Dir::Etc::sourcelist="${BATS_TEST_TMPDIR}/src.list"
  [ "$status" -eq 100 ]
  cmp "${BATS_TEST_TMPDIR}/src.list" "${BATS_TEST_TMPDIR}/copy.list"
  [ "$output" = "plain line" ]
  [[ "$stderr" == *"E: err line"* ]]
}

@test "apt-get update: no copy knob, no copy is made" {
  printf 'line\n' > "${BATS_TEST_TMPDIR}/src.list"
  run apt-get update -o Dir::Etc::sourcelist="${BATS_TEST_TMPDIR}/src.list"
  [ "$status" -eq 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/copy.list" ]
}

@test "apt-get install: output knob splits E: lines to stderr, before a forced failure" {
  export MOCK_APT_GET_INSTALL_OUTPUT="${BATS_TEST_TMPDIR}/out.txt"
  export MOCK_APT_FAIL_SUBCMD=install
  run --separate-stderr apt-get install -y pkg
  [ "$status" -eq 100 ]
  [[ "$output" == *"plain line"* ]]
  [[ "$stderr" == *"E: err line"* ]]
  [[ "$output" != *"E: err line"* ]]
}

@test "apt-get install: mark knob prints the mark and the package arguments only" {
  export MOCK_APT_GET_INSTALL_MARK=MARK
  run apt-get install -y -o Dpkg::Options::=--force-confdef -o Dir::Etc::sourcelist=/x/y.list --allow-downgrades 'packer=1.16.1-*'
  [ "$status" -eq 0 ]
  [ "$output" = "MARK packer=1.16.1-*" ]
}

@test "apt-get install: mark knob lists several packages and the call log keeps its line" {
  export MOCK_APT_GET_INSTALL_MARK=MARK
  run apt-get install -y a b
  [ "$output" = "MARK a b" ]
  grep -qx "apt-get install -y a b" "${MOCK_CALLS_FILE}"
}

@test "apt-get install: no knobs prints nothing" {
  run apt-get install -y a
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lsb_release -cs: unset gives noble" {
  run lsb_release -cs
  [ "$output" = "noble" ]
}

@test "lsb_release -cs: set but empty gives an empty codename" {
  export MOCK_LSB_RELEASE_CS=""
  run lsb_release -cs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lsb_release -cs: set value is printed" {
  export MOCK_LSB_RELEASE_CS=resolute
  run lsb_release -cs
  [ "$output" = "resolute" ]
}

@test "lsb_release -rs: default and override are unchanged and independent of -cs" {
  run lsb_release -rs
  [ "$output" = "24.04" ]
  export MOCK_LSB_RELEASE_RS=26.04 MOCK_LSB_RELEASE_CS=resolute
  run lsb_release -rs
  [ "$output" = "26.04" ]
}

@test "load_mocks: HashiCorp seam directories exist under the test tmpdir" {
  [[ "${_HASHICORP_SOURCE_DIR}" == "${BATS_TEST_TMPDIR}"/* ]]
  [[ "${_APT_KEYRINGS_DIR}" == "${BATS_TEST_TMPDIR}"/* ]]
  [ -d "${_HASHICORP_SOURCE_DIR}" ]
  [ -d "${_APT_KEYRINGS_DIR}" ]
}
