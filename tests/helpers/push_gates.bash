#!/usr/bin/env bash
# Shared by tests/scripts/pre_push.bats: runs scripts/pre-push from a COPY whose
# `_pcg_fetch` is a fake, so no test reaches the network while the push-gates wiring
# (ADR-0099 2A) still executes. The fake serves the ai-config master commit JSON and a
# recorder `push_gates_run` for the gates paths, falls through to the real fetch (the gh
# stub fails it) only for the push-content gate library, and fails every other path.
# Every fetched path is appended to FETCH_LOG. A test that needs the content-gate library
# to load sets PG_PCG_LIB to a file holding a stub library; the fake serves that file for
# the library path instead of falling through.
#
# The copy is LINE-PRESERVING and lives at <dir>/covalias/scripts/pre-push: every line is
# identical to the hook's except the `# >>> _pcg_fetch` marker line, which becomes a
# trampoline into the fake, and the header line after it, which is renamed
# `_pcg_fetch_real() {`; the body and closing marker stay byte-identical. The trampoline
# sits on a comment line of the real file, so the coverage runner drops its trace and
# claims no real line. The runner (scripts/run-bash-coverage.sh) attributes traces under
# `covalias/` to the real hook at the same line numbers, so these runs count as coverage
# of scripts/pre-push. Callers run the copy as plain `bash <copy>`, not `bash -p`: -p
# ignores BASH_ENV, which is how the coverage tracer attaches. The shebang's -p is pinned
# separately in tests/scripts/pre_push.bats.
#
# The hook finds its repo root through `git rev-parse` and never through its own path, so
# moving the copy changes no root.

readonly PG_FAKE_MASTER_SHA="0123456789abcdef0123456789abcdef01234567"

# pg_env <dir> -- creates <dir> and exports the paths and logs the fakes read.
pg_env() {
  PG_DIR="${1}"
  mkdir -p "${PG_DIR}" || return 1
  export GATES_LOG="${PG_DIR}/gates.log" ORDER_LOG="${PG_DIR}/order.log" FETCH_LOG="${PG_DIR}/fetch.log"
  export FAKE_MASTER_SHA="${PG_FAKE_MASTER_SHA}" FAKE_DRIVER="${PG_DIR}/fake_driver.sh"
  export PG_FAKE_FETCH="${PG_DIR}/fake_fetch.sh"
}

# pg_hook_copy <hook> -- writes an executable line-preserving copy of <hook> and prints
# its path. Fails loudly when the markers or header are not where expected, or the line
# counts differ.
pg_hook_copy() {
  local hook="${1}" copy="${PG_DIR}/covalias/scripts/pre-push" start end
  # shellcheck disable=SC2016 # the trampoline text is literal; it expands when the copy runs
  local tramp='_pcg_fetch() { . "${PG_FAKE_FETCH:?}"; _pg_fake_fetch "$@"; }'
  start="$(grep -n "^[#] >>> _pcg_fetch\$" "${hook}" | cut -d: -f1)"
  end="$(grep -n "^[#] <<< _pcg_fetch\$" "${hook}" | cut -d: -f1)"
  if [[ ! "${start}" =~ ^[0-9]+$ || ! "${end}" =~ ^[0-9]+$ ]] || (( end <= start + 1 )) \
    || ! [[ "$(sed -n "$((start + 1))p" "${hook}")" =~ ^_pcg_fetch\(\)\ \{(\ \#.*)?$ ]]; then
    printf 'pg_hook_copy: _pcg_fetch markers not found in %s\n' "${hook}" >&2
    return 1
  fi
  mkdir -p "${PG_DIR}/covalias/scripts" || return 1
  cat > "${FAKE_DRIVER}" <<'DRV'
push_gates_run() {
  printf 'url=%s\nsha=%s\nrefs=%s\n' "${1}" "${3}" "${2}" >> "${GATES_LOG}"
  printf 'gates\n' >> "${ORDER_LOG}"
  return "${GATES_RC:-0}"
}
DRV
  cat > "${PG_FAKE_FETCH}" <<'FAKE'
_pg_fake_fetch() {
  printf '%s\n' "${1}" >> "${FETCH_LOG}"
  case "${1}" in
    repos/brujack/ai-config/commits/master)
      [[ -z "${FAKE_MASTER_FAIL:-}" ]] || return 1
      printf '{"sha":"%s"}\n' "${FAKE_MASTER_SHA}"
      ;;
    "repos/brujack/ai-config/contents/.claude/hooks/push-gates.sh?ref=${FAKE_MASTER_SHA}")
      printf '%s\n' "$(< "${FAKE_DRIVER}")"
      ;;
    repos/brujack/ai-config/contents/.claude/hooks/push-content-gate.sh?ref=master)
      if [[ -n "${PG_PCG_LIB:-}" ]]; then cat "${PG_PCG_LIB}"; else _pcg_fetch_real "${1}"; fi
      ;;
    *) return 1 ;;
  esac
}
FAKE
  awk -v s="${start}" -v e="${end}" -v t="${tramp}" 'NR == s { print t; next } NR == s + 1 { print "_pcg_fetch_real() {"; next } { print }' "${hook}" > "${copy}" || return 1
  # Same line count, the trampoline exactly on the opening marker line, the header line
  # renamed, every body line up to the closing marker byte-identical, and the closing
  # marker unchanged.
  if [[ "$(wc -l < "${copy}")" -ne "$(wc -l < "${hook}")" ]] \
    || [[ "$(sed -n "${start}p" "${copy}")" != "${tramp}" ]] \
    || [[ "$(sed -n "$((start + 1))p" "${copy}")" != "_pcg_fetch_real() {" ]] \
    || ! cmp -s <(sed -n "$((start + 2)),$((end - 1))p" "${copy}") <(sed -n "$((start + 2)),$((end - 1))p" "${hook}") \
    || [[ "$(sed -n "${end}p" "${copy}")" != "$(sed -n "${end}p" "${hook}")" ]]; then
    printf 'pg_hook_copy: copy of %s is not line-preserving\n' "${hook}" >&2
    return 1
  fi
  chmod +x "${copy}" || return 1
  printf '%s' "${copy}"
}
