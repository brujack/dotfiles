#!/usr/bin/env bats
#
# Tests for scripts/verify-release-asset.sh, which CI runs on a downloaded
# GitHub release asset before anything executes it. The script is a separate
# process reading a COPY of lib/constants.sh through the bats-only
# _OVERRIDE_CONSTANTS_PATH seam; pins are real sha256 digests of files the test
# writes, so sha256sum itself is never mocked.

bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/verify-release-asset.sh"
  export HOME="${BATS_TEST_TMPDIR}"
  ASSET="${BATS_TEST_TMPDIR}/gitleaks.tar.gz"
  OTHER="${BATS_TEST_TMPDIR}/other.tar.gz"
  printf 'genuine release asset\n' >"${ASSET}"
  printf 'a different build\n' >"${OTHER}"
  SHA_ASSET="$(sha256sum "${ASSET}" | cut -d' ' -f1)"
  SHA_OTHER="$(sha256sum "${OTHER}" | cut -d' ' -f1)"
  C="${BATS_TEST_TMPDIR}/constants.sh"
  _write_constants "${SHA_ASSET}" "${SHA_OTHER}" "1.2.3"
  export _OVERRIDE_CONSTANTS_PATH="${C}"
}

# _write_constants <amd64-pin> <arm64-pin> <for-ver> -- the real constants with
# GITLEAKS_VER=1.2.3 and the three gitleaks pin lines replaced.
_write_constants() {
  command grep -vE '^GITLEAKS_(VER|SHA256_AMD64|SHA256_ARM64|SHA256_FOR_VER)=' \
    "${REPO_ROOT}/lib/constants.sh" >"${C}"
  printf 'GITLEAKS_VER="1.2.3"\nGITLEAKS_SHA256_AMD64="%s"\nGITLEAKS_SHA256_ARM64="%s"\nGITLEAKS_SHA256_FOR_VER="%s"\n' \
    "$1" "$2" "$3" >>"${C}"
}

@test "a file matching the amd64 pin verifies" {
  run "${SCRIPT}" gitleaks amd64 "${ASSET}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitleaks: ${ASSET} verified against GITLEAKS_SHA256_AMD64"* ]]
}

@test "a file one byte off the pin is refused and the mismatch names the pin" {
  printf 'X' >>"${ASSET}"
  run "${SCRIPT}" gitleaks amd64 "${ASSET}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch: GITLEAKS_SHA256_AMD64 expects ${SHA_ASSET}"* ]]
  [[ "$output" != *"verified"* ]]
}

@test "the arch argument selects its own pin" {
  run "${SCRIPT}" gitleaks arm64 "${OTHER}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified against GITLEAKS_SHA256_ARM64"* ]]
  run "${SCRIPT}" gitleaks arm64 "${ASSET}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GITLEAKS_SHA256_ARM64 expects ${SHA_OTHER}"* ]]
}

@test "pins recorded for another version refuse even a matching file" {
  # The file matches GITLEAKS_SHA256_AMD64, so only the stale _FOR_VER can fail it.
  _write_constants "${SHA_ASSET}" "${SHA_OTHER}" "1.2.2"
  run "${SCRIPT}" gitleaks amd64 "${ASSET}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GITLEAKS_SHA256_FOR_VER is 1.2.2, not GITLEAKS_VER 1.2.3"* ]]
  [[ "$output" == *"scripts/refresh-sha256-pins.sh gitleaks"* ]]
  [[ "$output" != *"verified"* ]]
}

@test "a missing file is refused as unreadable, not as a mismatch" {
  run "${SCRIPT}" gitleaks amd64 "${BATS_TEST_TMPDIR}/absent.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read the download"* ]]
  [[ "$output" != *"mismatch"* ]]
}

@test "an unknown tool or arch is a usage error" {
  run "${SCRIPT}" nosuchtool amd64 "${ASSET}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no sha256 pin for nosuchtool amd64"* ]]
  run "${SCRIPT}" gitleaks riscv64 "${ASSET}"
  [ "$status" -eq 2 ]
}

@test "the wrong number of arguments is a usage error" {
  run "${SCRIPT}" gitleaks amd64
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  run "${SCRIPT}"
  [ "$status" -eq 2 ]
}

@test "without the override the committed constants are read" {
  # Positive control for the production path: the real GITLEAKS_SHA256_AMD64
  # cannot match this file, so the mismatch must name the committed pin.
  unset _OVERRIDE_CONSTANTS_PATH
  local _pin
  _pin="$(sed -n 's/^GITLEAKS_SHA256_AMD64="\(.*\)"$/\1/p' "${REPO_ROOT}/lib/constants.sh")"
  [ -n "${_pin}" ]
  run "${SCRIPT}" gitleaks amd64 "${ASSET}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GITLEAKS_SHA256_AMD64 expects ${_pin}"* ]]
}
