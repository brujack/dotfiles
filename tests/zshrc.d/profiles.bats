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
  source "${REPO_ROOT}/tests/helpers/legacy_oracle.bash"
}

# Resolves config/profiles.zsh for one hostname in an isolated zsh process
# and prints PROFILE, the sorted HAS_* set, which (if any) legacy identity
# variable got set, and any stderr the sourced file produced (as STDERR=
# lines, so a caller can assert on absence of spurious warnings).
#
# The isolation happens INSIDE the zsh -c body, in one place, rather than
# split between an `env -u` prefix and something else: this session's own
# login shell exports STUDIO=1 on the machine these tests are written on
# (the legacy vars), and once .zprofile sources config/profiles.zsh, every
# login shell also exports its own HAS_* set -- which bats itself then
# inherits, since HAS_* is exported, unlike PROFILE_MAP/PROFILE_CAPS.
# Without unsetting both groups before sourcing, every assertion on either
# would pass regardless of what config/profiles.zsh does, because the
# ambient value would already satisfy it. `unset -m` is zsh-only (glob-style
# unset), which is why this can't be folded into the portable `env -u`
# prefix the way the eight legacy names could be -- but folding all nine
# into the same mechanism, in the same place, is exactly what keeps this
# complete: two isolation mechanisms is how the HAS_* gap happened in the
# first place.
#
# Deliberately not `set -e`/pipefail inside the zsh -c body: a genuinely
# zero-capability profile (e.g. mac_mini, or an unmapped hostname) makes the
# HAS_* listing legitimately empty, which is a correct outcome, not a
# failure to propagate.
_profiles_snapshot() { # <hostname>
  local hn="$1" _err_file _line
  _err_file="${BATS_TEST_TMPDIR}/profiles_snapshot_err"
  zsh -c "
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_HOSTNAME_OUTPUT='${hn}'
    if ! source '${REPO_ROOT}/config/profiles.zsh' 2>'${_err_file}'; then
      printf 'ERROR: could not source config/profiles.zsh\n' >&2
      cat '${_err_file}' >&2
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
  local _rc=$?
  # A warning config/profiles.zsh prints to stderr (e.g. the drift-arm
  # warning) doesn't make `source` return non-zero, so the check above
  # can't see it -- fold it into the snapshot under a distinct prefix so a
  # caller can assert on its absence instead of it being silently dropped.
  if [[ -s "${_err_file}" ]]; then
    while IFS= read -r _line; do
      printf 'STDERR=%s\n' "${_line}"
    done <"${_err_file}"
  fi
  rm -f "${_err_file}"
  return "${_rc}"
}

# ── every mapped hostname ─────────────────────────────────────────────────
# The expected legacy variable for each hostname comes from the shared
# oracle (tests/helpers/legacy_oracle.bash, sourced in setup()) rather than
# a function local to this file -- see that file for why it is hand-typed
# rather than derived from the production table, and
# tests/setup_env/profiles.bats for the bash-side suite that shares it.
# Derived from PROFILE_MAP itself (source config/profiles.sh, iterate
# "${!PROFILE_MAP[@]}") rather than a typed-out host list -- a hand-typed
# list would re-drift the moment a machine is added, which is the exact
# failure this task exists to remove. Guarded: assert the derived list is
# non-empty before looping, so a broken source path (PROFILE_MAP sourced as
# empty or undefined) can't silently turn this into a loop that asserts
# nothing. (A count comparison against `${#PROFILE_MAP[@]}` was tried here
# and removed -- `keys` is built FROM that same expression one line above,
# so the two counts are equal by construction and no input could ever make
# them differ. Non-empty is the only real assertion available at this
# point.)

@test "every PROFILE_MAP hostname resolves the right PROFILE, HAS_* set, and legacy var in zsh" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a keys
  keys=("${!PROFILE_MAP[@]}")
  [ "${#keys[@]}" -gt 0 ]

  # Hosts intentionally without a legacy identity variable. Empty today --
  # all 13 PROFILE_MAP keys map to one -- kept as an explicit, reviewable
  # exception set (mirroring config/profiles.sh's own `wired_only` pattern
  # for the wireless-twin check) so a future host that genuinely shouldn't
  # get one is a deliberate addition here, not a silent gap in the case
  # statement below.
  local -A no_legacy=()

  local hn expected_profile expected_legacy expected_has snapshot got_profile
  for hn in "${keys[@]}"; do
    expected_profile="${PROFILE_MAP[${hn}]}"

    if [[ -n "${no_legacy[${hn}]:-}" ]]; then
      expected_legacy=""
    else
      expected_legacy="$(_legacy_oracle_expected_var "${hn}")" || return 1
    fi

    # Guarded rather than piped straight through: `printf '%s\n' ${empty}`
    # (unquoted, word-split) still emits ONE blank line, which `sed
    # 's/^/HAS_/'` then turns into the bare prefix "HAS_" -- a value that
    # matches nothing real but isn't empty either. Unreachable via today's
    # 13 hosts (every PROFILE_CAPS entry is non-empty) but reachable the
    # moment a host lands in no_legacy with a zero-capability profile.
    if [[ -z "${PROFILE_CAPS[${expected_profile}]:-}" ]]; then
      expected_has=""
    else
      expected_has="$(printf '%s\n' ${PROFILE_CAPS[${expected_profile}]} | tr ' ' '\n' | tr '[:lower:]' '[:upper:]' | sed 's/^/HAS_/' | sort)"
    fi

    snapshot="$(_profiles_snapshot "${hn}")"

    printf '%s\n' "${snapshot}" | grep -q '^STDERR=' && {
      printf 'unexpected stderr from config/profiles.zsh for %s:\n%s\n' "${hn}" "${snapshot}" >&2
      return 1
    }

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
    got_has="$(printf '%s\n' "${snapshot}" | grep '^HAS_' || true)"
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
  # Exact equality also pins "no stderr": any STDERR= line _profiles_snapshot
  # folds in would break this match, same as an unexpected LEGACY= or HAS_*
  # line would.
  [ "${snapshot}" = "PROFILE=unknown" ]
}

# ── idempotent re-source ────────────────────────────────────────────────────
# The regression this guards: a `readonly` assignment instead of `export`
# would make the SECOND source() fail once .zprofile and 1_init.zsh both
# source this file in one login+interactive shell (that wiring lands in a
# later task, but the file must already tolerate it).

@test "sourcing config/profiles.zsh twice in one process does not error and is idempotent" {
  # Same isolation as _profiles_snapshot, and for the same reason: HAS_* is
  # exported by config/profiles.zsh itself, so an ambient set (e.g. this
  # login shell's own, once .zprofile sources it) would otherwise leak into
  # both sourcings identically and mask a regression rather than exercising
  # a real first-source.
  run zsh -c "
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
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

# ── shared legacy oracle: unmapped-host diagnostic ──────────────────────────
# All 13 PROFILE_MAP keys have a case arm today, so nothing exercises the
# oracle's `*) return 1` diagnostic -- three stale file references shipped
# in that exact position before this fix, undetected, for precisely that
# reason. This fixture adds a host to a COPY of the table so the diagnostic
# arm is actually reached by something real, not just called directly with
# an arbitrary made-up string.
#
# The fixture copies config/profiles.zsh UNCHANGED and only edits the
# sibling config/profiles.sh it sources -- config/profiles.zsh resolves that
# source path relative to its own directory
# (${${(%):-%x}:A:h}), so pointing the pair at a temp tree needs no override
# seam in production code. PROFILE resolving to mac_mini for "newhost" is
# the discriminator that the FIXTURE table was actually read: the real
# table has no such key and would resolve PROFILE=unknown instead, which
# would make this test pass for the wrong reason (an inert fixture).
@test "an unmapped PROFILE_MAP host reaches the shared oracle's diagnostic arm" {
  local fx="${BATS_TEST_TMPDIR}/fx"
  mkdir -p "${fx}/config"
  cp "${REPO_ROOT}/config/profiles.zsh" "${fx}/config/"
  sed 's|^  \[cruncher\]="wsl2_workstation"|&\n  [newhost]="mac_mini"|' \
    "${REPO_ROOT}/config/profiles.sh" >"${fx}/config/profiles.sh"

  local got_profile
  got_profile="$(zsh -c "
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_HOSTNAME_OUTPUT='newhost'
    source '${fx}/config/profiles.zsh' || exit 1
    printf '%s' \"\${PROFILE}\"
  ")"
  [ "${got_profile}" = "mac_mini" ] || {
    printf 'fixture table was not actually read: got PROFILE=%s (want mac_mini)\n' "${got_profile}" >&2
    return 1
  }

  run _legacy_oracle_expected_var newhost
  [ "$status" -eq 1 ]
  [[ "${output}" == *'PROFILE_MAP host "newhost" has no legacy-variable mapping in tests/helpers/legacy_oracle.bash'* ]]
}

# Negative control for the test above: a host present in BOTH the table and
# the oracle must NOT reach the diagnostic arm. Without this, nothing
# distinguishes "the arm fires correctly for an unmapped host" from "the arm
# always fires" -- a case statement collapsed to a single `*)` would pass
# the positive test above and only this one would catch it.
@test "a mapped PROFILE_MAP host does not reach the shared oracle's diagnostic arm" {
  run _legacy_oracle_expected_var studio
  [ "$status" -eq 0 ]
  [ "${output}" = "STUDIO" ]
}
