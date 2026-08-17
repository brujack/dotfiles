#!/usr/bin/env bats
# tests/zshrc.d/profiles.bats — zsh-side identity derivation from the shared
# config/profiles.sh table (config/profiles.zsh).
#
# load_mocks() is deliberately NOT called at setup() scope -- prepending
# tests/mocks/ to the outer PATH corrupts PATH for zsh subprocesses (see
# tests/zshrc.d/unit.bats's setup() comment). The hostname mock is injected
# inside each zsh -c invocation instead.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

# Resolves config/profiles.zsh for one hostname in an isolated zsh process
# and prints PROFILE, the sorted HAS_* set, and which (if any) legacy
# identity variable got set. The ambient environment is stripped of every
# legacy variable name before the subprocess runs: this session's own login
# shell exports STUDIO=1 on the machine these tests are written on, and
# without the strip every assertion on a legacy variable would pass
# regardless of what config/profiles.zsh does, because the ambient value
# would already satisfy it.
#
# Deliberately not `set -e`/pipefail inside the zsh -c body: a genuinely
# zero-capability profile (e.g. mac_mini, or an unmapped hostname) makes the
# HAS_* listing legitimately empty, which is a correct outcome, not a
# failure to propagate.
_profiles_snapshot() { # <hostname>
  local hn="$1"
  env -u STUDIO -u LAPTOP -u RECEPTION -u OFFICE -u HOMES -u WORKSTATION -u CRUNCHER -u RATNA \
    zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_HOSTNAME_OUTPUT='${hn}'
    if ! source '${REPO_ROOT}/config/profiles.zsh' 2>/tmp/profiles_snapshot_err; then
      printf 'ERROR: could not source config/profiles.zsh\n' >&2
      cat /tmp/profiles_snapshot_err >&2
      exit 1
    fi
    if [[ -z \${PROFILE:-} ]]; then
      printf 'ERROR: config/profiles.zsh did not set PROFILE\n' >&2
      exit 1
    fi
    printf 'PROFILE=%s\n' \"\${PROFILE}\"
    for v in LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA; do
      if [[ -n \${(P)v:-} ]]; then
        printf 'LEGACY=%s\n' \"\${v}\"
      fi
    done
    print -l \${(k)parameters[(I)HAS_*]} | sort
    exit 0
  "
}

# Maps a PROFILE_MAP hostname key to the legacy variable config/profiles.zsh
# is expected to set for it -- this correspondence isn't data in
# config/profiles.sh (it's implicit in the case statement), so it's the one
# piece of this suite that names hosts explicitly rather than deriving them.
# The KEY SET under test still comes from PROFILE_MAP itself, in the loop
# below, which is what actually prevents drift.
_profiles_expected_legacy() { # <hostname>
  case "$1" in
  laptop | laptop-1) printf 'LAPTOP' ;;
  studio | studio-1) printf 'STUDIO' ;;
  reception | reception-1) printf 'RECEPTION' ;;
  ratna | ratna-1) printf 'RATNA' ;;
  office | office-1) printf 'OFFICE' ;;
  home-1) printf 'HOMES' ;;
  workstation) printf 'WORKSTATION' ;;
  cruncher) printf 'CRUNCHER' ;;
  *) printf '' ;;
  esac
}

# ── every mapped hostname ─────────────────────────────────────────────────
# Derived from PROFILE_MAP itself (source config/profiles.sh, iterate
# "${!PROFILE_MAP[@]}") rather than a typed-out host list -- a hand-typed
# list would re-drift the moment a machine is added, which is the exact
# failure this task exists to remove. Guarded: assert the derived list is
# non-empty and matches the table's own size before looping, so a broken
# source path can't silently turn this into a loop that asserts nothing.

@test "every PROFILE_MAP hostname resolves the right PROFILE, HAS_* set, and legacy var in zsh" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a keys
  keys=("${!PROFILE_MAP[@]}")
  [ "${#keys[@]}" -gt 0 ]
  [ "${#keys[@]}" -eq "${#PROFILE_MAP[@]}" ]

  local hn expected_profile expected_legacy expected_has snapshot got_profile
  for hn in "${keys[@]}"; do
    expected_profile="${PROFILE_MAP[${hn}]}"
    expected_legacy="$(_profiles_expected_legacy "${hn}")"
    expected_has="$(printf '%s\n' ${PROFILE_CAPS[${expected_profile}]} | tr ' ' '\n' | tr '[:lower:]' '[:upper:]' | sed 's/^/HAS_/' | sort)"

    snapshot="$(_profiles_snapshot "${hn}")"

    got_profile="$(printf '%s\n' "${snapshot}" | grep '^PROFILE=' | cut -d= -f2)"
    [ "${got_profile}" = "${expected_profile}" ] || {
      printf 'PROFILE mismatch for %s: got %s want %s\n' "${hn}" "${got_profile}" "${expected_profile}" >&2
      return 1
    }

    if [ -n "${expected_legacy}" ]; then
      printf '%s\n' "${snapshot}" | grep -qx "LEGACY=${expected_legacy}" || {
        printf 'expected legacy var %s not set for %s\nsnapshot:\n%s\n' "${expected_legacy}" "${hn}" "${snapshot}" >&2
        return 1
      }
    fi

    local got_has
    got_has="$(printf '%s\n' "${snapshot}" | grep '^HAS_')"
    [ "${got_has}" = "${expected_has}" ] || {
      printf 'HAS_* mismatch for %s:\n got: %s\nwant: %s\n' "${hn}" "${got_has}" "${expected_has}" >&2
      return 1
    }
  done
}

# ── unmapped hostname ───────────────────────────────────────────────────────

@test "unmapped hostname yields PROFILE=unknown, zero HAS_*, and no legacy var" {
  local snapshot
  snapshot="$(_profiles_snapshot unknownhost)"
  [ "${snapshot}" = "PROFILE=unknown" ]
}

# ── idempotent re-source ────────────────────────────────────────────────────
# The regression this guards: a `readonly` assignment instead of `export`
# would make the SECOND source() fail once .zprofile and 1_init.zsh both
# source this file in one login+interactive shell (that wiring lands in a
# later task, but the file must already tolerate it).

@test "sourcing config/profiles.zsh twice in one process does not error and is idempotent" {
  run env -u STUDIO -u LAPTOP -u RECEPTION -u OFFICE -u HOMES -u WORKSTATION -u CRUNCHER -u RATNA \
    zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_HOSTNAME_OUTPUT='studio'
    source '${REPO_ROOT}/config/profiles.zsh' || exit 1
    first_profile=\"\${PROFILE}\"
    first_studio=\"\${STUDIO:-unset}\"
    first_has_gui=\"\${HAS_GUI:-unset}\"
    source '${REPO_ROOT}/config/profiles.zsh' || exit 1
    if [[ \"\${PROFILE}\" != \"\${first_profile}\" ]]; then
      printf 'PROFILE changed across re-source: %s -> %s\n' \"\${first_profile}\" \"\${PROFILE}\" >&2
      exit 1
    fi
    if [[ \"\${STUDIO:-unset}\" != \"\${first_studio}\" ]]; then
      printf 'STUDIO changed across re-source\n' >&2
      exit 1
    fi
    if [[ \"\${HAS_GUI:-unset}\" != \"\${first_has_gui}\" ]]; then
      printf 'HAS_GUI changed across re-source\n' >&2
      exit 1
    fi
    exit 0
  "
  [ "$status" -eq 0 ]
}

# ── syntax check ─────────────────────────────────────────────────────────────

@test "config/profiles.zsh has valid zsh syntax" {
  run zsh -n "${REPO_ROOT}/config/profiles.zsh"
  [ "$status" -eq 0 ]
}
