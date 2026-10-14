#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  export KIND_VER="1.2.3"
  export YQ_VER="1.2.3"
  export SHELLCHECK_VER="1.2.3"
}

@test "_release_asset_url kind amd64" {
  run _release_asset_url kind amd64
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/kubernetes-sigs/kind/releases/download/v1.2.3/kind-linux-amd64" ]
}

@test "_release_asset_url kind arm64" {
  run _release_asset_url kind arm64
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/kubernetes-sigs/kind/releases/download/v1.2.3/kind-linux-arm64" ]
}

@test "_release_asset_url yq amd64" {
  run _release_asset_url yq amd64
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/mikefarah/yq/releases/download/v1.2.3/yq_linux_amd64" ]
}

@test "_release_asset_url yq arm64" {
  run _release_asset_url yq arm64
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/mikefarah/yq/releases/download/v1.2.3/yq_linux_arm64" ]
}

@test "_release_asset_url shellcheck amd64 maps to x86_64" {
  run _release_asset_url shellcheck amd64
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/koalaman/shellcheck/releases/download/v1.2.3/shellcheck-v1.2.3.linux.x86_64.tar.xz" ]
}

@test "_release_asset_url shellcheck arm64 maps to aarch64" {
  run _release_asset_url shellcheck arm64
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/koalaman/shellcheck/releases/download/v1.2.3/shellcheck-v1.2.3.linux.aarch64.tar.xz" ]
}

@test "_release_asset_url unknown tool returns 2 with no output" {
  run _release_asset_url nosuchtool amd64
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "_release_asset_url unknown arch returns 3 with no output" {
  run _release_asset_url kind riscv64
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}

@test "_release_asset_url empty arch returns 3 with no output" {
  run _release_asset_url shellcheck ""
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}

_set_pins() {
  export KIND_SHA256_AMD64="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  export KIND_SHA256_ARM64="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  export YQ_SHA256_AMD64="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  export YQ_SHA256_ARM64="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  export SHELLCHECK_SHA256_AMD64="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  export SHELLCHECK_SHA256_ARM64="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
}

@test "_release_asset_sha prints variable name and value for every tool/arch" {
  _set_pins
  local _t _a _var _want
  for _t in kind yq shellcheck; do
    for _a in amd64 arm64; do
      _var="${_t^^}_SHA256_${_a^^}"
      _want="${!_var}"
      run _release_asset_sha "${_t}" "${_a}"
      [ "$status" -eq 0 ]
      [ "$output" = "${_var} ${_want}" ]
    done
  done
}

@test "_release_asset_sha unknown tool returns 2" {
  _set_pins
  run _release_asset_sha nosuchtool amd64
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "_release_asset_sha unknown arch returns 3" {
  _set_pins
  run _release_asset_sha kind riscv64
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}

@test "committed constants define four 64-hex kind/yq pins and three _FOR_VER lines" {
  run grep -cE '^(KIND|YQ)_SHA256_(AMD64|ARM64)="[[:xdigit:]]{64}"$' "${REPO_ROOT}/lib/constants.sh"
  [ "$output" -eq 4 ]
  run grep -cE '^(KIND|YQ|SHELLCHECK)_SHA256_FOR_VER=' "${REPO_ROOT}/lib/constants.sh"
  [ "$output" -eq 3 ]
}

# Reads the real lib/constants.sh in a clean child shell: setup() overrides the
# *_VER variables with fixtures, which would mask the committed values.
_committed() {
  env -i HOME="${BATS_TEST_TMPDIR}" PATH="${PATH}" bash -c '
    source "$1/lib/constants.sh"; source "$1/lib/helpers.sh"
    printf -v v "%s" "${!2}"; printf "%s" "$v"' _ "${REPO_ROOT}" "$1"
}

@test "committed pins: each of the six is a real 64-hex digest, not zeros" {
  local zeros v
  zeros="$(printf '0%.0s' {1..64})"
  for name in KIND_SHA256_AMD64 KIND_SHA256_ARM64 YQ_SHA256_AMD64 YQ_SHA256_ARM64 \
    SHELLCHECK_SHA256_AMD64 SHELLCHECK_SHA256_ARM64; do
    v="$(_committed "${name}")"
    _sha256_pin_ok "${v}" || { printf '%s=%s\n' "${name}" "${v}" >&2; return 1; }
    [ "${v}" != "${zeros}" ] || { printf '%s is zeros\n' "${name}" >&2; return 1; }
  done
}

@test "committed pins: _FOR_VER equals *_VER and *_VER is non-empty" {
  local a b
  a="$(_committed KIND_VER)"; b="$(_committed KIND_SHA256_FOR_VER)"
  [ -n "${a}" ]; [ "${a}" = "${b}" ]
  a="$(_committed YQ_VER)"; b="$(_committed YQ_SHA256_FOR_VER)"
  [ -n "${a}" ]; [ "${a}" = "${b}" ]
  a="$(_committed SHELLCHECK_VER)"; b="$(_committed SHELLCHECK_SHA256_FOR_VER)"
  [ -n "${a}" ]; [ "${a}" = "${b}" ]
}
