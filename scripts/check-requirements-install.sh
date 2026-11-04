#!/usr/bin/env bash
# Installs the requirements-ci renderings that other repos' CI pulls LIVE from
# dotfiles master, in each consumer's install shape, under the interpreter
# pyproject.toml requires.
#
# Why: since 2026-11-03 ai-config and state-ledger CI run
#   pip install --require-hashes -r https://raw.githubusercontent.com/brujack/dotfiles/master/requirements-ci-<group>.txt
# (ai-config ADR-0092), so a merged rendering reaches their pipelines within the
# CDN's ~5-minute cache. check-requirements-ci only proves a rendering matches
# uv.lock; a pin that resolves but will not install (sdist-only, failed build,
# no wheel for the platform) would merge green here and turn every consumer PR
# red. This is the pre-merge install test.
#
# A real install, not `pip install --dry-run`: dry-run resolves and downloads
# but never builds or installs a wheel, so it cannot see a build failure.
#
# Exit status: 0 every shape installed; 1 a shape failed (or a rendering is
# missing, which breaks its consumers the same way); 2 the check could not run
# (no interpreter, wrong interpreter, unreadable requires-python, no temp dir).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# Seams: tests point these at a fixture root, a stub interpreter and a
# test-owned temp root. BSD mktemp with a template ignores TMPDIR, so the temp
# root is explicit rather than inherited.
_ROOT="${RENDERINGS_INSTALL_ROOT:-${REPO_ROOT}}"
_PYTHON="${RENDERINGS_INSTALL_PYTHON:-python3}"
_TMP_ROOT="${RENDERINGS_INSTALL_TMP_ROOT:-${TMPDIR:-/tmp}}"

# Consumer install shapes, one venv each, files installed in order as separate
# pip calls. Mirrored from the consumers' workflows on 2026-11-04:
#   ci-test+ci-audit     ai-config ci.yml test/lint jobs
#   ci-mutation          ai-config mutation-pr.yml
#   ci-test+ci-mutation  ai-config mutation-review.yml, mutation-testing.yml
# state-ledger's jobs use the same shapes. A consumer adding a new combination
# needs a row here.
readonly _SHAPES=(
  "ci-test+ci-audit:requirements-ci-test.txt requirements-ci-audit.txt"
  "ci-mutation:requirements-ci-mutation.txt"
  "ci-test+ci-mutation:requirements-ci-test.txt requirements-ci-mutation.txt"
)

# _required_minor: print X.Y from requires-python = "==X.Y.*", or fail.
_required_minor() {
  local _minor
  _minor="$(sed -nE 's/^requires-python = "==([0-9]+\.[0-9]+)\.\*"$/\1/p' "${_ROOT}/pyproject.toml" 2>/dev/null)"
  [[ -n "${_minor}" ]] || return 1
  printf '%s\n' "${_minor}"
}

# _install_shape NAME FILE...: install FILEs in order into a fresh venv.
# Runs in a subshell so the EXIT trap removes the venv on every path.
_install_shape() (
  local _name="$1" _dir _f
  shift
  _dir="$(mktemp -d "${_TMP_ROOT}/renderings-install.XXXXXX")" || exit 1
  trap 'rm -rf "${_dir}"' EXIT
  "${_PYTHON}" -m venv "${_dir}/venv" || exit 1
  for _f in "$@"; do
    printf 'installing %s (%s)\n' "${_f}" "${_name}"
    "${_dir}/venv/bin/pip" install --quiet --disable-pip-version-check \
      --require-hashes -r "${_ROOT}/${_f}" || exit 1
  done
)

main() {
  local _want _have _shape _name _files _f _missing _rc=0
  if ! command -v "${_PYTHON}" >/dev/null 2>&1; then
    printf 'ERROR: interpreter not found: %s\n' "${_PYTHON}" >&2
    return 2
  fi
  if ! _want="$(_required_minor)"; then
    printf 'ERROR: cannot read requires-python = "==X.Y.*" from %s\n' "${_ROOT}/pyproject.toml" >&2
    return 2
  fi
  _have="$("${_PYTHON}" -c 'import sys; print("%d.%d" % sys.version_info[:2])')" || _have=""
  if [[ "${_have}" != "${_want}" ]]; then
    printf 'ERROR: %s is Python %s; pyproject.toml requires %s\n' "${_PYTHON}" "${_have:-unknown}" "${_want}" >&2
    return 2
  fi
  if [[ ! -d "${_TMP_ROOT}" || ! -w "${_TMP_ROOT}" ]]; then
    printf 'ERROR: temp root not writable: %s\n' "${_TMP_ROOT}" >&2
    return 2
  fi

  for _shape in "${_SHAPES[@]}"; do
    _name="${_shape%%:*}"
    read -r -a _files <<< "${_shape#*:}"
    _missing=0
    for _f in "${_files[@]}"; do
      if [[ ! -f "${_ROOT}/${_f}" ]]; then
        printf 'MISSING: %s\n' "${_f}" >&2
        _missing=1
      fi
    done
    if [[ "${_missing}" -eq 0 ]] && _install_shape "${_name}" "${_files[@]}"; then
      printf 'OK: %s\n' "${_name}"
    else
      printf 'FAILED: %s\n' "${_name}" >&2
      _rc=1
    fi
  done
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

main "$@"
exit $?
