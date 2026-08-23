#!/usr/bin/env bats
# tests/setup_env/profiles.bats — profile and capability resolution tests

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  source "${REPO_ROOT}/tests/helpers/legacy_oracle.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_UNAME_S="Darwin"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Resolves detect_env for one hostname in an isolated subshell and prints
# PROFILE, which (if any) legacy identity variable got set, and the sorted
# set of HAS_* vars it declared. Isolated because detect_env sets several
# `readonly` vars (MACOS, LAPTOP, ...) — sourcing it twice in the same
# process errors on the second `readonly` assignment, so a wired/wireless
# comparison needs two separate processes, not two sourcings.
#
# The legacy vars and PROFILE are explicitly unset, and every ambient HAS_*
# is stripped, before sourcing. This process may itself have been launched
# from an interactive login shell whose .zprofile already exported STUDIO=1
# and a full HAS_* set (config/profiles.zsh uses `export`, not `readonly`,
# precisely so login shells can re-source it) -- both groups would otherwise
# leak into this bash -c subprocess and make every assertion on either pass
# regardless of what lib/detect_env.sh actually does. `${!HAS_@}` is bash's
# name-matching expansion; unsetting it when nothing matches is a no-op, not
# an error.
#
# Deliberately NOT `set -euo pipefail`: a genuinely zero-capability host
# (unmapped hostname, empty hostname) makes `grep '^HAS_'` legitimately
# match nothing and exit 1, and pipefail would turn that correct outcome
# into a false failure. Instead the two steps that must not silently no-op
# -- sourcing the library and running detect_env -- are checked explicitly,
# plus a postcondition that PROFILE actually got set. Real detect_env always
# assigns PROFILE (falling back to "unknown", never leaving it empty), so an
# empty PROFILE here can only mean source/detect_env didn't run at all --
# e.g. lib/detect_env.sh moved, or the PATH/mock wiring drifted. Without
# this, a broken subshell prints "PROFILE=" with exit 0 (grep-then-sort
# swallows everything upstream), and a caller comparing two equally-broken
# snapshots for equality gets a false pass instead of a red test.
_profile_snapshot() {
  local hn="$1"
  bash -c "
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset \${!HAS_@}
    export MOCK_HOSTNAME_OUTPUT='${hn}'
    export MOCK_UNAME_S='Darwin'
    export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
    if ! source '${REPO_ROOT}/lib/detect_env.sh'; then
      printf 'ERROR: could not source lib/detect_env.sh\n' >&2
      exit 1
    fi
    if ! detect_env; then
      printf 'ERROR: detect_env failed\n' >&2
      exit 1
    fi
    if [[ -z \${PROFILE:-} ]]; then
      printf 'ERROR: detect_env did not set PROFILE\n' >&2
      exit 1
    fi
    printf 'PROFILE=%s\n' \"\${PROFILE}\"
    for v in LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA; do
      if [[ -n \${!v} ]]; then
        printf 'LEGACY=%s\n' \"\${v}\"
        [[ \$(declare -p \"\${v}\") == declare\ -*r* ]] || printf 'LEGACY_NOT_READONLY=%s\n' \"\${v}\"
      fi
    done
    compgen -v | grep '^HAS_' | sort
    exit 0
  "
}

# ── profile resolution ────────────────────────────────────────────────────────

@test "detect_env sets PROFILE=personal_laptop for hostname laptop" {
  export MOCK_HOSTNAME_OUTPUT="laptop"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "personal_laptop" ]
}

@test "detect_env sets PROFILE=mac_workstation for hostname studio" {
  export MOCK_HOSTNAME_OUTPUT="studio"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

@test "detect_env sets PROFILE=mac_workstation for hostname reception" {
  export MOCK_HOSTNAME_OUTPUT="reception"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

@test "detect_env sets PROFILE=mac_mini for hostname office" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_mini" ]
}

@test "detect_env sets PROFILE=unknown for unrecognised hostname" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "unknown" ]
}

# ── capability vars ───────────────────────────────────────────────────────────

@test "HAS_DEVTOOLS is set for personal_laptop" {
  export MOCK_HOSTNAME_OUTPUT="laptop"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_DEVTOOLS is set for mac_workstation" {
  export MOCK_HOSTNAME_OUTPUT="studio"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_DEVTOOLS is unset for mac_mini" {
  unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
  unset "${!HAS_@}"
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_DEVTOOLS:-}" ]
}

@test "HAS_GUI is set for all Mac profiles" {
  for hn in laptop studio reception office; do
    result=$(bash -c "
      export MOCK_HOSTNAME_OUTPUT='${hn}'
      export MOCK_UNAME_S='Darwin'
      export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
      source '${REPO_ROOT}/lib/detect_env.sh'
      detect_env
      printf '%s' \"\${HAS_GUI:-}\"
    ")
    [ -n "${result}" ] || {
      printf "HAS_GUI not set for hostname: %s\n" "${hn}" >&2
      return 1
    }
  done
}

@test "HAS_DOCKER is unset for mac_mini" {
  unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
  unset "${!HAS_@}"
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_DOCKER:-}" ]
}

@test "CHRUBY_LOC is set on macOS for unknown hostname" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  export MOCK_UNAME_S="Darwin"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${CHRUBY_LOC:-}" ]
}

@test "CHRUBY_LOC points to homebrew path on macOS" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  export MOCK_UNAME_S="Darwin"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${CHRUBY_LOC}" = "/opt/homebrew/opt/chruby/share" ]
}

@test "CHRUBY_LOC points to local share on Linux" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  export MOCK_AWK_OS_NAME="Ubuntu"
  unset MACOS
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${CHRUBY_LOC}" = "/usr/local/share" ]
}

@test "HAS_PRINTING is set for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_PRINTING}" ]
}

@test "detect_env sets PROFILE=linux_workstation for hostname workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "linux_workstation" ]
}

@test "detect_env sets PROFILE=wsl2_workstation for hostname cruncher" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "wsl2_workstation" ]
}

@test "HAS_SNAP is set for linux_workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_SNAP}" ]
}

@test "HAS_SNAP is unset for wsl2_workstation" {
  unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
  unset "${!HAS_@}"
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_SNAP:-}" ]
}

@test "HAS_DEVTOOLS is set for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_RUST is set for linux_workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_RUST}" ]
}

@test "HAS_RUST is set for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_RUST}" ]
}

@test "detect_env sets RESOLUTE=1 for Ubuntu 26.04" {
  export MOCK_UNAME_S="Linux"
  export MOCK_AWK_OS_NAME="Ubuntu"
  export MOCK_LSB_RELEASE_RS="26.04"
  export MOCK_HOSTNAME_OUTPUT="workstation"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [[ -n ${RESOLUTE} ]]
}

# ── wireless hostname equivalence ─────────────────────────────────────────────
# A `-1` suffix is the machine's wireless-interface hostname (see the comments
# in config/profiles.sh for the two named exceptions). `hostname -s` returns
# it whenever the machine is on wifi, so PROFILE_MAP must resolve it
# identically to its wired twin -- the PROFILE string AND the full HAS_* set,
# not just the former. A matching profile with a divergent capability set is
# exactly the class of bug this coverage exists to catch.
#
# The invariant is derived from PROFILE_MAP itself rather than enumerated by
# hostname: five hand-picked pairwise tests only re-confirm today's five
# hosts, so adding a machine tomorrow without its -1 twin -- the exact
# defect this task exists to prevent -- would pass all of them. Iterating
# "${!PROFILE_MAP[@]}" means a future addition is covered automatically.
@test "every wired PROFILE_MAP key has a wireless -1 twin on the same profile" {
  source "${REPO_ROOT}/config/profiles.sh"
  # Deliberately wired-only (see config/profiles.sh's own comment) -- not a
  # gap, so excluded rather than expected to fail.
  local -A wired_only=([workstation]=1 [cruncher]=1)
  local k found=0
  for k in "${!PROFILE_MAP[@]}"; do
    # Every existing "-1" key IS a wireless twin (home-1 included -- its
    # suffix is part of the machine's actual name, not a twin marker, but it
    # has no bare "home" counterpart to require one of, so skipping it here
    # is a correct no-op rather than an evasion).
    [[ ${k} == *-1 ]] && continue
    [[ -n ${wired_only[${k}]:-} ]] && continue
    found=1
    [ "${PROFILE_MAP[${k}-1]:-MISSING}" = "${PROFILE_MAP[${k}]}" ]
  done
  [ "${found}" -eq 1 ]
}

# Data-level coverage above proves PROFILE_MAP itself is symmetric; this
# keeps one snapshot-based case exercising the real detect_env resolution
# path end-to-end, so a future change that branches on hostname directly
# (bypassing PROFILE_MAP/PROFILE_CAPS) would still be caught.
@test "wired and wireless studio resolve to the same PROFILE and HAS_* set" {
  local wired wireless
  wired=$(_profile_snapshot studio)
  wireless=$(_profile_snapshot studio-1)
  [ "${wired}" = "${wireless}" ]
}

# ── legacy identity variables ─────────────────────────────────────────────────
# lib/detect_env.sh derives LAPTOP/STUDIO/RECEPTION/RATNA/OFFICE/HOMES/
# WORKSTATION/CRUNCHER from the same PROFILE_MAP table config/profiles.zsh
# uses. The KEY SET under test comes from PROFILE_MAP itself (as with the
# wireless-twin test above), not a hand-typed host list, so a machine added
# tomorrow without a case arm here is caught rather than silently untested.
#
# The expected legacy variable for each hostname comes from the shared
# oracle (tests/helpers/legacy_oracle.bash, sourced in setup()) rather than
# a function local to this file -- see that file for why it is hand-typed
# rather than derived from the production table, and
# tests/zshrc.d/profiles.bats for the zsh-side suite that shares it.

@test "every PROFILE_MAP hostname sets the right legacy identity variable in bash" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a keys
  keys=("${!PROFILE_MAP[@]}")
  [ "${#keys[@]}" -gt 0 ]

  local hn expected_legacy snapshot
  for hn in "${keys[@]}"; do
    expected_legacy="$(_legacy_oracle_expected_var "${hn}")" || return 1
    snapshot="$(_profile_snapshot "${hn}")"
    printf '%s\n' "${snapshot}" | grep -qx "LEGACY=${expected_legacy}" || {
      printf 'expected legacy var %s not set for %s\nsnapshot:\n%s\n' "${expected_legacy}" "${hn}" "${snapshot}" >&2
      return 1
    }
    printf '%s\n' "${snapshot}" | grep -q '^LEGACY_NOT_READONLY=' && {
      printf 'legacy var for %s is not readonly:\nsnapshot:\n%s\n' "${hn}" "${snapshot}" >&2
      return 1
    }
  done
  # Explicit success: without this, the function's implicit return status is
  # whatever the last statement in the final loop iteration produced -- and
  # that statement is the `grep -q ... && { ... }` guard above, whose exit
  # code is 1 (grep's "not found") in exactly the case this test wants to
  # PASS. A bare `&&`/`||` guard as the final command of a loop body is the
  # same last-command-exit-status trap documented in
  # tests/zshrc.d/profiles.bats's idempotent re-source test.
  return 0
}

@test "unmapped hostname sets no legacy identity variable" {
  local snapshot
  snapshot="$(_profile_snapshot unknownhost)"
  printf '%s\n' "${snapshot}" | grep -q '^LEGACY=' && {
    printf 'unexpected legacy var set for unmapped hostname:\n%s\n' "${snapshot}" >&2
    return 1
  }
  [ "${snapshot}" = "PROFILE=unknown" ]
}

# ── legacy var is table-driven, not a hardcoded case arm ───────────────────
# Mirrors tests/zshrc.d/profiles.bats's "resolves ... not a hardcoded case
# arm" test (commit 1007ab1). The oracle test above proves lib/detect_env.sh
# agrees with the shared table's CONTENT -- it cannot discriminate a
# table-driven reader from a hardcoded-case reader, since PROFILE_LEGACY and
# the case arms were hand-typed to encode the same mapping and so agree
# regardless of which one production actually reads (behavior.md: a check
# derived from the same decision as the thing it checks cannot falsify it).
# This test breaks that symmetry by mutating a COPY of the table and
# asserting the resolved legacy var follows the mutation.
#
# The fixture copies lib/detect_env.sh alongside a sed-modified
# config/profiles.sh, preserving the real lib/ + ../config relative layout --
# detect_env.sh resolves its own directory via ${BASH_SOURCE[0]} and sources
# "../config/profiles.sh" from there, so sourcing the fixture's copy of
# detect_env.sh makes it read the fixture's table, not the real one. The
# assertion is driven from the fixture's own mutated value (STUDIO), not a
# literal describing the real table, so deleting the fixture's sed line
# would make this test fail loudly rather than pass vacuously.
@test "lib/detect_env.sh resolves the legacy var from PROFILE_LEGACY, not a hardcoded case arm" {
  local fx="${BATS_TEST_TMPDIR}/fx-legacy-swap-bash"
  mkdir -p "${fx}/lib" "${fx}/config"
  cp "${REPO_ROOT}/lib/detect_env.sh" "${fx}/lib/"
  sed 's/\[laptop\]="LAPTOP"/[laptop]="STUDIO"/' \
    "${REPO_ROOT}/config/profiles.sh" >"${fx}/config/profiles.sh"

  local got
  got="$(bash -c "
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset \${!HAS_@}
    export MOCK_HOSTNAME_OUTPUT='laptop'
    export MOCK_UNAME_S='Darwin'
    export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
    if ! source '${fx}/lib/detect_env.sh'; then
      printf 'ERROR: could not source fixture detect_env.sh\n' >&2
      exit 1
    fi
    if ! detect_env; then
      printf 'ERROR: detect_env failed\n' >&2
      exit 1
    fi
    [[ -n \${STUDIO:-} ]] && printf 'STUDIO'
    [[ -n \${LAPTOP:-} ]] && printf 'LAPTOP'
    exit 0
  ")"
  [ "${got}" = "STUDIO" ] || {
    printf 'expected the legacy var to follow the mutated PROFILE_LEGACY table (STUDIO), got %s\n' "${got}" >&2
    return 1
  }
}

# ── PROFILE_LEGACY map ────────────────────────────────────────────────────────
# PROFILE_LEGACY maps every PROFILE_MAP hostname key directly to its legacy
# identity variable name. It is hand-written rather than derived from
# PROFILE_MAP's keys (e.g. strip "-1", uppercase) because home-1 -> HOMES
# breaks that derivation -- the mechanical result would be HOME, and
# `export HOME=1` in a login shell repoints the user's home directory.

@test "every PROFILE_MAP key has a PROFILE_LEGACY entry" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a keys
  keys=("${!PROFILE_MAP[@]}")
  # Load-bearing: an empty key expansion makes the loop below vacuous, so the
  # test would report ok having asserted nothing.
  [ "${#keys[@]}" -gt 0 ]

  local k
  for k in "${keys[@]}"; do
    [ -n "${PROFILE_LEGACY[${k}]:-}" ] || {
      printf 'PROFILE_MAP host "%s" has no PROFILE_LEGACY entry\n' "${k}" >&2
      return 1
    }
  done
}

# The mirror of the key-coverage test above, and it needs its own test rather
# than falling out of that one: the two tables are now adjacent in one file, so
# a hand-edit can add a key to either side alone. The forward direction
# (PROFILE_MAP key with no PROFILE_LEGACY entry) is caught both here and by a
# production warning in config/profiles.zsh. The reverse direction had neither
# -- measured, adding [ghosthost]="STUDIO" to PROFILE_LEGACY alone reddened 0
# tests across all four suites while both readers resolved PROFILE=unknown with
# zero HAS_* AND STUDIO=1 set, rc 0, stderr silent.
#
# That state is worse than it looks: .config/.zshrc.d/7_final.zsh:60 reads the
# eight legacy vars as a proxy for "is this host mapped", so it would answer
# mapped while every HAS_* gate answers unmapped -- a half-initialised login
# identity with nothing reporting it.
#
# Deliberately test-only, with no matching production warning. The forward
# warning earns its place because a machine legitimately gets added to
# PROFILE_MAP by an operator following CLAUDE.md's Adding a New Machine steps,
# so that drift reaches a real shell. Reverse drift can only come from editing
# PROFILE_LEGACY directly, which this test gates before merge -- so a loop over
# the table on every login shell would buy nothing and cost every shell start.
@test "every PROFILE_LEGACY key exists in PROFILE_MAP" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a keys
  keys=("${!PROFILE_LEGACY[@]}")
  # Same non-vacuity guard as the sibling test above, for the same reason.
  [ "${#keys[@]}" -gt 0 ]

  local k
  for k in "${keys[@]}"; do
    [ -n "${PROFILE_MAP[${k}]:-}" ] || {
      printf 'PROFILE_LEGACY key "%s" is not in PROFILE_MAP -- it would set a legacy identity variable on a host that resolves PROFILE=unknown with zero HAS_* capabilities. Add "%s" to PROFILE_MAP, or remove it from PROFILE_LEGACY.\n' "${k}" "${k}" >&2
      return 1
    }
  done
}

@test "PROFILE_LEGACY values are exactly the eight legacy identity variable names" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a values
  values=("${PROFILE_LEGACY[@]}")
  [ "${#values[@]}" -gt 0 ]

  # This set-equality is the guard against deriving PROFILE_LEGACY from
  # PROFILE_MAP's keys: the mechanical result is home-1 -> HOME, which fails
  # here and PASSES the key-coverage test above. Do not simplify it to a
  # count or drop it as redundant.
  local got want
  got="$(printf '%s\n' "${values[@]}" | sort -u | tr '\n' ' ')"
  want="$(printf '%s\n' CRUNCHER HOMES LAPTOP OFFICE RATNA RECEPTION STUDIO WORKSTATION | sort -u | tr '\n' ' ')"
  [ "${got}" = "${want}" ]
}

# ── ratna ──────────────────────────────────────────────────────────────────────

@test "detect_env sets PROFILE=mac_workstation for hostname ratna" {
  export MOCK_HOSTNAME_OUTPUT="ratna"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

# ── unmapped / malformed hostname ───────────────────────────────────────────────

@test "unmapped hostname yields PROFILE=unknown and zero HAS_* vars" {
  local snapshot
  snapshot=$(_profile_snapshot unknownhost)
  [ "${snapshot}" = "PROFILE=unknown" ]
}

@test "empty hostname -s output yields PROFILE=unknown" {
  # Routed through _profile_snapshot's subshell rather than a direct,
  # unwrapped `detect_env` call: bash's associative-array lookup emits a
  # harmless "bad array subscript" warning for an empty index (reproduced
  # with a bare `hn=""` outside this suite entirely -- a bash quirk, not
  # something config/profiles.sh causes or this task's scope can fix), and
  # bats runs test bodies under `set -e`, which treats that warning's
  # transient nonzero status as a hard failure and aborts before the
  # assertion. The snapshot's own subshell has no such `set -e`, so the
  # default (`unknown`) is observed the same way production sees it.
  #
  # The argument must be $'\n', not "". tests/mocks/hostname resolves
  # ${MOCK_HOSTNAME_OUTPUT:-testhost}, so an empty string falls through to
  # the `testhost` default and this test silently degrades into a duplicate
  # of the unmapped-hostname case above -- still green, having stopped
  # testing an empty hostname at all. A trailing newline survives the
  # :- fallback and is stripped by command substitution, so `hostname -s`
  # really does return zero bytes.
  local snapshot
  snapshot=$(_profile_snapshot $'\n')
  [ "${snapshot}" = "PROFILE=unknown" ]
}

@test "hostname studio-2 does not fuzzy-match its prefix-sharing sibling studio-1" {
  export MOCK_HOSTNAME_OUTPUT="studio-2"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "unknown" ]
}
