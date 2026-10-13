#!/usr/bin/env bats
# Tests for _sha256_pin_ok and _verify_sha256 (lib/helpers.sh).
#
# sha256sum is deliberately NOT mocked: every verdict comes from the real
# binary, so a mismatch is genuinely exercised in both directions.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  _f="${BATS_TEST_TMPDIR}/f"
  printf 'abc' > "${_f}"
  # Known SHA-256 vector for "abc"; hard-coded so the expectation does not come
  # from the same sha256sum the function under test calls.
  _hash="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}

@test "_verify_sha256: matching hash returns 0" {
  run _verify_sha256 "${_f}" "${_hash}"
  [ "$status" -eq 0 ]
}

@test "_verify_sha256: one changed byte returns 1" {
  printf 'abd' > "${_f}"
  run _verify_sha256 "${_f}" "${_hash}"
  [ "$status" -eq 1 ]
}

@test "_verify_sha256: malformed pin returns 2 before the file is consulted" {
  local _bad
  for _bad in "" "${_hash:0:63}" "${_hash}0" "${_hash:0:63}g"; do
    run _verify_sha256 "${BATS_TEST_TMPDIR}/nonexistent" "${_bad}"
    [ "$status" -eq 2 ]
  done
}

@test "_verify_sha256: valid pin on a missing file returns 3" {
  run _verify_sha256 "${BATS_TEST_TMPDIR}/nonexistent" "${_hash}"
  [ "$status" -eq 3 ]
}

@test "_verify_sha256: upper-case hex pin is accepted" {
  local _upper
  _upper="$(printf '%s' "${_hash}" | tr a-f A-F)"
  run _verify_sha256 "${_f}" "${_upper}"
  [ "$status" -eq 0 ]
}

@test "_sha256_pin_ok: 64 hex returns 0" {
  run _sha256_pin_ok "${_hash}"
  [ "$status" -eq 0 ]
}

@test "_sha256_pin_ok: 63 hex returns 1" {
  run _sha256_pin_ok "${_hash:0:63}"
  [ "$status" -eq 1 ]
}

@test "_sha256_pin_ok: empty returns 1" {
  run _sha256_pin_ok ""
  [ "$status" -eq 1 ]
}

@test "_verify_sha256: a directory with a valid pin returns 3" {
  mkdir "${BATS_TEST_TMPDIR}/d"
  run _verify_sha256 "${BATS_TEST_TMPDIR}/d" "${_hash}"
  [ "$status" -eq 3 ]
}

# The [0-9a-fA-F] range matched non-ASCII letters only where the locale's range
# collation is non-ASCII (Linux glibc en_US.UTF-8; the Studio does not
# reproduce it), so this discriminates on Linux and CI. Skips if the locale is
# not installed, since the C fallback cannot exhibit the defect.
@test "_sha256_pin_ok: non-ASCII letter in a 64-char pin is rejected under en_US.UTF-8" {
  locale -a | grep -qix 'en_US.utf-\?8' || skip "en_US.UTF-8 not installed"
  local _pin
  _pin="$(printf '%063d' 0)é"
  export LC_ALL=en_US.UTF-8
  run _sha256_pin_ok "${_pin}"
  [ "$status" -eq 1 ]
  run _verify_sha256 "${BATS_TEST_TMPDIR}/nonexistent" "${_pin}"
  [ "$status" -eq 2 ]
}
