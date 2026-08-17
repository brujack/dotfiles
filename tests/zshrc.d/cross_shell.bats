#!/usr/bin/env bats
# tests/zshrc.d/cross_shell.bats — bash and zsh must derive identical
# identity from the single shared config/profiles.sh table.
#
# tests/setup_env/profiles.bats and tests/zshrc.d/profiles.bats each derive
# their own expectations from PROFILE_MAP and check exactly one resolver
# (lib/detect_env.sh in bash, config/profiles.zsh in zsh). Each is internally
# consistent, so a derivation that is correct for one shell and wrong for
# the other passes both suites -- behavior.md: a check derived from the same
# decision as the thing it checks cannot falsify it.
#
# This file is the oracle produced by a DIFFERENT mechanism: it runs both
# resolvers for the same hostname and asserts their outputs are identical,
# rather than asserting either output against a hand-derived expectation.
# That is not hypothetical here -- zsh does not word-split unquoted
# parameter expansions (SH_WORD_SPLIT is off by default, unlike bash), so
# the natural bash idiom `for cap in ${PROFILE_CAPS[$PROFILE]}` would
# silently produce ONE capability named after the whole string in zsh.
# config/profiles.zsh uses `${=...}` for exactly that reason; this file pins
# that the two shells still agree, not just that each individually looks
# plausible.
#
# load_mocks() is deliberately NOT called at setup() scope -- prepending
# tests/mocks/ to the outer PATH corrupts PATH for zsh subprocesses (see
# tests/zshrc.d/unit.bats's setup() comment). The hostname mock is injected
# inside each subprocess invocation instead, exactly as both
# tests/setup_env/profiles.bats's _profile_snapshot and
# tests/zshrc.d/profiles.bats's _profiles_snapshot already do.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

# Resolves lib/detect_env.sh for one hostname in an isolated bash subprocess
# and prints PROFILE, which (if any) legacy identity variable got set, and
# the sorted set of HAS_* vars it declared. Mirrors
# tests/setup_env/profiles.bats's _profile_snapshot exactly (same isolation,
# same output shape) so the two shells' snapshots are directly comparable.
#
# Both LAPTOP/STUDIO/... and every ambient HAS_* are unset before sourcing:
# this process may itself have been launched from an interactive login shell
# whose .zprofile already exported STUDIO=1 and a full HAS_* set, which would
# otherwise leak into the subprocess and make PROFILE/HAS_*/LEGACY match
# regardless of what lib/detect_env.sh actually resolves for the hostname
# under test.
#
# Deliberately NOT `set -euo pipefail`: a genuinely zero-capability host
# (e.g. mac_mini) makes `grep '^HAS_'` legitimately match nothing and exit
# 1, and pipefail would turn that correct outcome into a false failure.
# Instead the two steps that must not silently no-op -- sourcing the
# library and running detect_env -- are checked explicitly, and a
# postcondition that PROFILE actually got set. A prior task's snapshot ended
# its pipeline with `sort`, so it exited 0 even when the source failed and
# two degenerate empty strings compared equal -- the explicit checks below
# and the non-empty guard in the calling test are what prevent that here.
_bash_identity_snapshot() { # <hostname>
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
      fi
    done
    compgen -v | grep '^HAS_' | sort
    exit 0
  "
}

# zsh-side twin of _bash_identity_snapshot above. Mirrors
# tests/zshrc.d/profiles.bats's _profiles_snapshot, minus the STDERR=
# capture: config/profiles.zsh's only stderr output is the drift-arm warning
# for a PROFILE_MAP key with no case arm, which is a case the "table key"
# mutation proof below deliberately produces and expects to still resolve
# identical PROFILE/HAS_*/LEGACY on both sides (see that mutation's comment)
# -- so stderr is discarded here rather than folded into the compared
# snapshot, which would make this file fail for a divergence the per-shell
# suites already own.
_zsh_identity_snapshot() { # <hostname>
  local hn="$1"
  zsh -c "
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_HOSTNAME_OUTPUT='${hn}'
    if ! source '${REPO_ROOT}/config/profiles.zsh' 2>/dev/null; then
      printf 'ERROR: could not source config/profiles.zsh\n' >&2
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

# ── the one check that matters ──────────────────────────────────────────────
# Derived from PROFILE_MAP itself (source config/profiles.sh, iterate
# "${!PROFILE_MAP[@]}") rather than a typed-out host list, so a machine added
# tomorrow is compared automatically instead of silently going untested.
# Guarded: assert the derived list is non-empty before looping, so a broken
# source path can't silently turn this into a loop that asserts nothing. Not
# also asserting the count equals "${#PROFILE_MAP[@]}" -- that expression is
# where `keys` came from one line above, so the two counts are equal by
# construction and no input could make them differ.

@test "bash and zsh derive identical PROFILE, HAS_* set, and legacy var for every PROFILE_MAP key" {
  source "${REPO_ROOT}/config/profiles.sh"
  local -a keys
  keys=("${!PROFILE_MAP[@]}")
  [ "${#keys[@]}" -gt 0 ]

  local hn bash_snap zsh_snap
  for hn in "${keys[@]}"; do
    bash_snap="$(_bash_identity_snapshot "${hn}")"
    zsh_snap="$(_zsh_identity_snapshot "${hn}")"

    # Each snapshot always contains at least "PROFILE=..." on success --
    # real detect_env/profiles.zsh always assign PROFILE, falling back to
    # "unknown", never leaving it empty. An empty capture here means the
    # subprocess failed before printing anything, which two degenerate
    # empty strings would otherwise compare equal and pass silently.
    [[ -n "${bash_snap}" ]] || {
      printf 'bash snapshot resolved nothing for host "%s" -- subshell likely failed before printing PROFILE\n' "${hn}" >&2
      return 1
    }
    [[ -n "${zsh_snap}" ]] || {
      printf 'zsh snapshot resolved nothing for host "%s" -- subshell likely failed before printing PROFILE\n' "${hn}" >&2
      return 1
    }

    [ "${bash_snap}" = "${zsh_snap}" ] || {
      printf 'identity mismatch for host "%s":\n--- bash (lib/detect_env.sh) ---\n%s\n--- zsh (config/profiles.zsh) ---\n%s\n' \
        "${hn}" "${bash_snap}" "${zsh_snap}" >&2
      return 1
    }
  done
}
