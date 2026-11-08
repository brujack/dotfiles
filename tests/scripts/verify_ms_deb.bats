#!/usr/bin/env bats
#
# Tests for scripts/verify-ms-deb.sh, which CI's powershell job runs on
# packages-microsoft-prod.deb before `dpkg -i` installs Microsoft's apt signing
# key as root. The fixture is the real Microsoft-signed 1.2-ubuntu24.04 .deb,
# so the pass case checks Microsoft's actual signature against the vendored key.
# The script runs as its own process; gpg and ar are the real binaries.

bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/verify-ms-deb.sh"
  FIXTURE="${REPO_ROOT}/tests/fixtures/packages-microsoft-prod.deb"
  export HOME="${BATS_TEST_TMPDIR}"
  # Microsoft's .deb stores GNU-format member names, which Apple's ar cannot
  # extract; the verifier runs on Ubuntu only. Mirrors tests/setup_env/linux_ubuntu.bats.
  GNU_AR=""
  if ar --version 2>/dev/null | command grep -q 'GNU ar'; then
    GNU_AR="ar"
  elif command -v gar >/dev/null 2>&1; then
    GNU_AR="gar"
  fi
  [[ -n "${GNU_AR}" ]] && export _MS_AR_BIN="${GNU_AR}"
}

_require_gnu_ar() {
  [[ -n "${GNU_AR}" ]] && return 0
  [[ "$(uname -s)" == "Darwin" ]] && skip "no GNU ar: Apple's ar cannot read the GNU member names in Microsoft's .deb; the verifier runs on Ubuntu only"
  printf 'GNU ar (binutils) is required to test verify-ms-deb.sh off macOS\n' >&2
  return 1
}

@test "the real Microsoft-signed .deb verifies" {
  _require_gnu_ar
  run "${SCRIPT}" "${FIXTURE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"packages-microsoft-prod.deb: signature verified"* ]]
}

@test "a .deb whose data changed after signing is refused" {
  _require_gnu_ar
  mkdir -p "${BATS_TEST_TMPDIR}/m"
  (cd "${BATS_TEST_TMPDIR}/m" && "${GNU_AR}" x "${FIXTURE}")
  printf 'X' >>"${BATS_TEST_TMPDIR}/m/data.tar.gz"
  (cd "${BATS_TEST_TMPDIR}/m" && "${GNU_AR}" rc "${BATS_TEST_TMPDIR}/tampered.deb" \
    debian-binary control.tar.gz data.tar.gz _gpgorigin)
  run "${SCRIPT}" "${BATS_TEST_TMPDIR}/tampered.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not verify"* ]]
  [[ "$output" != *"signature verified"* ]]
}

@test "a missing file is refused" {
  _require_gnu_ar
  run "${SCRIPT}" "${BATS_TEST_TMPDIR}/absent.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"absent.deb: not a readable file"* ]]
  [[ "$output" != *"signature verified"* ]]
}

@test "no argument, or more than one, is a usage error" {
  run "${SCRIPT}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  run "${SCRIPT}" a.deb b.deb
  [ "$status" -eq 2 ]
}
