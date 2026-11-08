#!/usr/bin/env bash
# Refresh uv.lock and the five CI renderings, then write a PR body.
#
# Usage: refresh-uv-lock.sh <body-file>
#
# Last stdout line is `changed` or `no changes` (exit 0); any refusal exits
# non-zero with the reason on stderr. All uv and make output goes to stderr so
# stdout carries only the result word. Never commits and never touches a remote.
#
# Seams (tests point these at fixtures):
#   _UV_BIN               uv binary (default: uv)
#   _MAKE_BIN             make binary (default: make)
#   REFRESH_UV_LOCK_ROOT  directory holding uv.lock (default: this repo's root)
#   _DOWNGRADE_HELPER     downgrade checker (default: uv_lock_downgrades.py beside this script)

_REFRESH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print one error line to stderr.
_refresh_err() {
  printf 'refresh-uv-lock: %s\n' "$*" >&2
}

# Write the PR body to ${1} from the captured change lines in ${2}.
_refresh_write_body() {
  local body_file="${1}" lines_file="${2}" count
  count="$(wc -l < "${lines_file}")" || return 1
  count="${count//[[:space:]]/}"
  {
    printf '## Lock refresh\n\n'
    printf 'uv lock --upgrade changed %s package entries:\n\n' "${count}"
    printf '```\n'
    cat "${lines_file}"
    printf '```\n\n'
    cat <<'BODY'
The five CI renderings were re-synced and `check-lock` and `check-requirements-ci` passed under REQUIRE_TOOLS=1.

## Review

1. Start CI (a GITHUB_TOKEN PR gets none): `gh pr close chore/uv-lock-refresh && gh pr reopen chore/uv-lock-refresh`
2. Read the change list above and the diff.
3. Merge by hand, because the auto-merge gate holds bot PRs and a label only re-runs CI: `gh pr merge chore/uv-lock-refresh --squash`
4. A later weekly run replaces this PR's contents with a fresh refresh from master, and `gh workflow run uv-lock-refresh.yml` does that now.
BODY
  } > "${body_file}" || return 1
}

# Run one make target with REQUIRE_TOOLS=1 for the checks; output to stderr.
_refresh_make() {
  local target="${1}" require="${2}"
  if [[ "${require}" == "1" ]]; then
    REQUIRE_TOOLS=1 "${_MAKE_BIN}" "${target}" >&2 || {
      _refresh_err "make ${target} failed"
      return 1
    }
  else
    "${_MAKE_BIN}" "${target}" >&2 || {
      _refresh_err "make ${target} failed"
      return 1
    }
  fi
}

# Everything that needs temp files; runs in a subshell so the trap is scoped.
_refresh_run() {
  local body_file="${1}" tmp log lines before rc
  tmp="$(mktemp -d)" || exit 1
  # shellcheck disable=SC2064 # expand now: ${tmp} is fixed for this subshell's life
  trap "rm -rf -- '${tmp}'" EXIT
  log="${tmp}/uv.log"
  lines="${tmp}/lines"
  before="${tmp}/uv.lock.before"

  cp uv.lock "${before}" || {
    _refresh_err "cannot read uv.lock"
    return 1
  }

  "${_UV_BIN}" lock --upgrade --color never > "${log}" 2>&1
  rc=$?
  cat "${log}" >&2
  if [[ ${rc} -ne 0 ]]; then
    _refresh_err "uv lock --upgrade failed"
    return 1
  fi

  command grep -E '^(Updated|Added|Removed) ' "${log}" > "${lines}"
  rc=$?
  if [[ ${rc} -gt 1 ]]; then
    _refresh_err "cannot read uv output"
    return 1
  fi

  if cmp -s uv.lock "${before}"; then
    printf 'no changes\n'
    return 0
  fi

  if [[ ! -s "${lines}" ]]; then
    _refresh_err "uv printed no change lines but uv.lock changed"
    return 1
  fi

  local offenders
  offenders="$(python3 "${_DOWNGRADE_HELPER}" < "${lines}")"
  rc=$?
  case "${rc}" in
    0) ;;
    1)
      _refresh_err "refusing downgrade: ${offenders//$'\n'/, }"
      _refresh_err "if a release was yanked, raise the pyproject.toml floor past it, then re-run"
      return 1
      ;;
    *)
      _refresh_err "downgrade check failed (helper rc ${rc})"
      return 1
      ;;
  esac

  _refresh_make sync-requirements-ci 0 || return 1
  _refresh_make check-lock 1 || return 1
  _refresh_make check-requirements-ci 1 || return 1

  _refresh_write_body "${body_file}" "${lines}" || {
    _refresh_err "cannot write ${body_file}"
    return 1
  }
  printf 'changed\n'
}

main() {
  local body_file="${1:-}"
  if [[ -z "${body_file}" ]]; then
    _refresh_err "usage: refresh-uv-lock.sh <body-file>"
    return 2
  fi
  : "${_UV_BIN:=uv}" "${_MAKE_BIN:=make}"
  : "${_DOWNGRADE_HELPER:=${_REFRESH_SCRIPT_DIR}/uv_lock_downgrades.py}"
  # Resolve before the cd below, so a relative path means the caller's cwd.
  [[ "${body_file}" == /* ]] || body_file="${PWD}/${body_file}"
  local root="${REFRESH_UV_LOCK_ROOT:-${_REFRESH_SCRIPT_DIR}/..}"
  cd "${root}" || {
    _refresh_err "cannot cd to ${root}"
    return 1
  }
  ( _refresh_run "${body_file}" )
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
