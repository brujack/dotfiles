#!/usr/bin/env bats
# Shape of .gitleaks.toml, which CI's secret-scan job reads.
#
# A config without `[extend] useDefault = true` loads zero rules, so the scan
# passes on any secret. A path allowlist suppresses every finding under it;
# measured 2026-11-22 over the full history with gitleaks 8.30.1, the four that
# existed suppressed nothing, so the config carries none and a real false
# positive must be allowlisted narrowly, with a reason, when it appears.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CFG="${REPO_ROOT}/.gitleaks.toml"
}

@test "gitleaks config extends the default rule set" {
  command grep -qE '^\[extend\]' "${CFG}"
  command grep -qE '^useDefault[[:space:]]*=[[:space:]]*true' "${CFG}"
}

@test "gitleaks config allowlists no paths" {
  [ -f "${CFG}" ]
  ! command grep -qE '^[[:space:]]*paths[[:space:]]*=' "${CFG}"
}

@test "every allowlisted commit carries a dated note" {
  local _sha _n=0
  while IFS= read -r _sha; do
    _n=$((_n + 1))
    command grep -qE "\"${_sha}\",[[:space:]]*#.*[0-9]{4}-[0-9]{2}-[0-9]{2}" "${CFG}"
  done < <(command grep -oE '"[0-9a-f]{40}"' "${CFG}" | tr -d '"')
  [ "${_n}" -gt 0 ]
}
