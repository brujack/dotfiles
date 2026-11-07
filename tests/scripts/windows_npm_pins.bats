#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# setup_windows.ps1 cannot source lib/constants.sh, so it carries its own copy
# of the firecrawl-cli pin. This file keeps that copy equal to FIRECRAWL_CLI_VER.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  PS1_FILE="${REPO_ROOT}/powershell/setup_windows.ps1"
  SH_FILE="${REPO_ROOT}/lib/constants.sh"
}

# Lines of <file> defining the pin, as "<value>" per line.
_ps1_ver() {
  sed -nE "s/^\\\$FirecrawlCliVersion = '([^']*)'\$/\\1/p" "$1"
}

_sh_ver() {
  sed -nE 's/^FIRECRAWL_CLI_VER="([^"]*)"$/\1/p' "$1"
}

# _check_count <extractor> <file>: exactly one definition.
_check_count() {
  local _n
  _n="$("$1" "$2" | wc -l)"
  if [[ "${_n}" -ne 1 ]]; then
    printf 'expected 1 definition in %s, found %s\n' "$2" "${_n}" >&2
    return 1
  fi
}

_check_semver() {
  local _v
  _v="$("$1" "$2")"
  [[ "${_v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'not a semver in %s: "%s"\n' "$2" "${_v}" >&2
    return 1
  }
}

# _check_equal <ps1 file> <sh file>
_check_equal() {
  local _p _s
  _p="$(_ps1_ver "$1")"
  _s="$(_sh_ver "$2")"
  if [[ "${_p}" != "${_s}" ]]; then
    printf 'pin drift: %s="%s" %s="%s"\n' "$1" "${_p}" "$2" "${_s}" >&2
    return 1
  fi
}

@test "each real file has exactly one pin definition" {
  _check_count _ps1_ver "${PS1_FILE}"
  _check_count _sh_ver "${SH_FILE}"
}

@test "each real pin is a plain semver" {
  _check_semver _ps1_ver "${PS1_FILE}"
  _check_semver _sh_ver "${SH_FILE}"
}

@test "the ps1 pin equals FIRECRAWL_CLI_VER" {
  _check_equal "${PS1_FILE}" "${SH_FILE}"
}

@test "fixture: differing values fail the equality check" {
  printf "\$FirecrawlCliVersion = '9.9.9'\n" > "${BATS_TEST_TMPDIR}/a.ps1"
  printf 'FIRECRAWL_CLI_VER="1.0.0"\n' > "${BATS_TEST_TMPDIR}/a.sh"
  run ! _check_equal "${BATS_TEST_TMPDIR}/a.ps1" "${BATS_TEST_TMPDIR}/a.sh"
}

@test "fixture: matching values pass the equality check" {
  printf "\$FirecrawlCliVersion = '1.0.0'\n" > "${BATS_TEST_TMPDIR}/a.ps1"
  printf 'FIRECRAWL_CLI_VER="1.0.0"\n' > "${BATS_TEST_TMPDIR}/a.sh"
  _check_equal "${BATS_TEST_TMPDIR}/a.ps1" "${BATS_TEST_TMPDIR}/a.sh"
}

@test "fixture: zero definitions fail the count check" {
  printf '# nothing\n' > "${BATS_TEST_TMPDIR}/z.ps1"
  run ! _check_count _ps1_ver "${BATS_TEST_TMPDIR}/z.ps1"
}

@test "fixture: two definitions fail the count check" {
  printf "\$FirecrawlCliVersion = '1.0.0'\n\$FirecrawlCliVersion = '1.0.1'\n" > "${BATS_TEST_TMPDIR}/t.ps1"
  printf 'FIRECRAWL_CLI_VER="1.0.0"\nFIRECRAWL_CLI_VER="1.0.1"\n' > "${BATS_TEST_TMPDIR}/t.sh"
  run ! _check_count _ps1_ver "${BATS_TEST_TMPDIR}/t.ps1"
  run ! _check_count _sh_ver "${BATS_TEST_TMPDIR}/t.sh"
}
