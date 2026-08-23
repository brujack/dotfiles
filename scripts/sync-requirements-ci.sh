#!/usr/bin/env bash
# Renders the CI requirements files from uv.lock.
#
# Each file is a RENDERING, not a declaration: pyproject.toml plus uv.lock are
# the source, and this produces the plain, hash-carrying requirements files that
# other repos' CI can install with stock pip and no uv on the runner.
#
# FOUR renderings, deliberately separate files -- do not harmonise them:
#   test-lint    -> requirements-ci.txt              the full local/dev test set
#   runtime      -> requirements-runtime-ci.txt      terraform_ansible
#   ci-test      -> requirements-ci-test.txt         per-PR test/lint jobs
#   ci-mutation  -> requirements-ci-mutation.txt     mutation jobs
# They exist because the consumers genuinely differ: terraform_ansible installs
# ansible/molecule and no test tooling; etch-cli runs three tools and needs 9
# packages, not the 80 the full test-lint set renders. See pyproject.toml for
# the boundary rule governing what may enter ci-test.
#
# `sync` writes them; `check` fails if a committed copy has drifted. Same shape
# as sync-agent-guidance.sh.
#
# uv's own two-line header is stripped and replaced. It echoes the exact argv,
# including `--project /abs/path` when passed -- so a file rendered on a dev
# machine would never match one checked in CI, and the gate would fire forever
# on correct state. Measured, not assumed.
#
# Provenance (source repo, uv.lock SHA, date) deliberately does NOT go in these
# headers. A runtime-group edit changes uv.lock without changing the test-lint
# export, so a SHA in that header would demand a re-render whose only effect is
# one header line -- a check firing on correct state, forever. Provenance belongs
# on the CONSUMER's copy, written at copy time.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# REQUIREMENTS_CI_TARGET / REQUIREMENTS_RUNTIME_CI_TARGET exist so tests can
# point at a fixture instead of the tracked file. Without them a test that
# crashes between mutating and restoring leaves a modified tracked rendering
# that could be committed by accident.
_RENDERINGS=(
  "test-lint:${REQUIREMENTS_CI_TARGET:-${REPO_ROOT}/requirements-ci.txt}"
  "runtime:${REQUIREMENTS_RUNTIME_CI_TARGET:-${REPO_ROOT}/requirements-runtime-ci.txt}"
  "ci-test:${REQUIREMENTS_CI_TEST_TARGET:-${REPO_ROOT}/requirements-ci-test.txt}"
  "ci-mutation:${REQUIREMENTS_CI_MUTATION_TARGET:-${REPO_ROOT}/requirements-ci-mutation.txt}"
  "ci-audit:${REQUIREMENTS_CI_AUDIT_TARGET:-${REPO_ROOT}/requirements-ci-audit.txt}"
)
readonly _RENDERINGS

# shellcheck source=lib/helpers.sh
source "${REPO_ROOT}/lib/helpers.sh"
readonly HEADER="# Generated from uv.lock — do not edit.
# Regenerate with: make sync-requirements-ci"

# _render GROUP -- emit the rendering for one dependency group on stdout.
_render() {
  local _group="$1" _uv
  _uv="$(resolve_uv)" || return 1
  {
    printf "%s\n" "${HEADER}"
    (cd "${REPO_ROOT}" && "${_uv}" export --frozen --only-group "${_group}" \
       --format requirements-txt 2>/dev/null | sed '/^#/d')
  } || return 1
}

cmd_sync() {
  local _pair _group _target _out _rc=0
  for _pair in "${_RENDERINGS[@]}"; do
    _group="${_pair%%:*}"
    _target="${_pair#*:}"
    if ! _out="$(_render "${_group}")"; then
      printf "FAILED to render group %s\n" "${_group}" >&2
      _rc=1
      continue
    fi
    printf "%s\n" "${_out}" > "${_target}" || { _rc=1; continue; }
    printf "wrote %s\n" "${_target#"${REPO_ROOT}/"}"
  done
  return "${_rc}"
}

cmd_check() {
  local _pair _group _target _out _rc=0
  for _pair in "${_RENDERINGS[@]}"; do
    _group="${_pair%%:*}"
    _target="${_pair#*:}"
    if [[ ! -f "${_target}" ]]; then
      printf "MISSING: %s — run 'make sync-requirements-ci'\n" \
        "${_target#"${REPO_ROOT}/"}" >&2
      _rc=1
      continue
    fi
    if ! _out="$(_render "${_group}")"; then
      printf "FAILED to render group %s\n" "${_group}" >&2
      _rc=1
      continue
    fi
    if ! printf "%s\n" "${_out}" | diff -q - "${_target}" >/dev/null; then
      printf "DRIFT: %s does not match uv.lock — run 'make sync-requirements-ci'\n" \
        "${_target#"${REPO_ROOT}/"}" >&2
      printf "%s\n" "${_out}" | diff - "${_target}" | head -20 >&2
      _rc=1
      continue
    fi
    printf "OK: %s matches uv.lock\n" "${_target#"${REPO_ROOT}/"}"
  done
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

case "${1:-}" in
  sync)  cmd_sync ;;
  check) cmd_check ;;
  *)     printf "usage: %s {sync|check}\n" "$(basename "$0")" >&2; exit 2 ;;
esac
