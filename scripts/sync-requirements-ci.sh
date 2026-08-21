#!/usr/bin/env bash
# Renders requirements-ci.txt from uv.lock's test-lint group.
#
# The file is a RENDERING, not a declaration: pyproject.toml plus uv.lock are
# the source, and this produces the plain, hash-carrying requirements file that
# five repos' CI can install with stock pip and no uv on the runner.
#
# `sync` writes it; `check` fails if the committed copy has drifted. Same shape
# as sync-agent-guidance.sh.
#
# uv's own two-line header is stripped and replaced. It echoes the exact argv,
# including `--project /abs/path` when passed — so a file rendered on a dev
# machine would never match one checked in CI, and the gate would fire forever
# on correct state. Measured, not assumed.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
# REQUIREMENTS_CI_TARGET exists so tests can point at a fixture instead of the
# tracked file. Without it a test that crashes between mutating and restoring
# leaves a modified requirements-ci.txt that could be committed by accident.
readonly TARGET="${REQUIREMENTS_CI_TARGET:-${REPO_ROOT}/requirements-ci.txt}"

# shellcheck source=lib/helpers.sh
source "${REPO_ROOT}/lib/helpers.sh"
readonly HEADER="# Generated from uv.lock — do not edit.
# Regenerate with: make sync-requirements-ci"

_render() {
  local _uv
  _uv="$(resolve_uv)" || return 1
  {
    printf "%s\n" "${HEADER}"
    (cd "${REPO_ROOT}" && "${_uv}" export --frozen --only-group test-lint \
       --format requirements-txt 2>/dev/null | sed '/^#/d')
  } || return 1
}

cmd_sync() {
  local _out
  _out="$(_render)" || return 1
  printf "%s\n" "${_out}" > "${TARGET}" || return 1
  printf "wrote %s\n" "${TARGET#"${REPO_ROOT}/"}"
}

cmd_check() {
  if [[ ! -f "${TARGET}" ]]; then
    printf "MISSING: %s — run 'make sync-requirements-ci'\n" "${TARGET#"${REPO_ROOT}/"}" >&2
    return 1
  fi
  local _out
  _out="$(_render)" || return 1
  if ! printf "%s\n" "${_out}" | diff -q - "${TARGET}" >/dev/null; then
    printf "DRIFT: %s does not match uv.lock — run 'make sync-requirements-ci'\n" \
      "${TARGET#"${REPO_ROOT}/"}" >&2
    printf "%s\n" "${_out}" | diff - "${TARGET}" | head -20 >&2
    return 1
  fi
  printf "OK: %s matches uv.lock\n" "${TARGET#"${REPO_ROOT}/"}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

case "${1:-}" in
  sync)  cmd_sync ;;
  check) cmd_check ;;
  *)     printf "usage: %s {sync|check}\n" "$(basename "$0")" >&2; exit 2 ;;
esac
