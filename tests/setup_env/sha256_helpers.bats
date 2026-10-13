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
  _hash="$(sha256sum "${_f}" | cut -d' ' -f1)"
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
