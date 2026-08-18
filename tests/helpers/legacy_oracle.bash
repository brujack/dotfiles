#!/usr/bin/env bash
# tests/helpers/legacy_oracle.bash — shared oracle for the legacy identity
# variable each PROFILE_MAP hostname is expected to resolve to. Used by both
# tests/zshrc.d/profiles.bats (zsh-side) and tests/setup_env/profiles.bats
# (bash-side) so there is exactly one copy of this mapping and one copy of
# its diagnostic message.
#
# Deliberately hand-typed rather than derived from PROFILE_LEGACY in
# config/profiles.sh, and the reason is measured rather than stylistic.
#
# Swap two values in that table -- [laptop]="STUDIO", [studio]="LAPTOP" -- and
# both names are still present and the key count is unchanged, so every
# permutation-invariant assertion built from the table still passes. Measured at
# 12e302c, once both production readers consume the table: that swap fails
# exactly 2 tests, one per language side --
#
#     tests/setup_env/profiles.bats   not ok 25   (bash, via lib/detect_env.sh)
#     tests/zshrc.d/profiles.bats     not ok  1   (zsh, via config/profiles.zsh)
#     tests/zshrc.d/cross_shell.bats  0 failures
#
# That last line is the point. cross_shell compares the two productions to each
# other, so when both read the same wrong table they still agree and it stays
# GREEN. Two implementations that agree can be wrong together; only an oracle
# derived by a different mechanism notices. Both failures above are per-host
# assertions comparing production output against THIS file.
#
# (Before 12e302c nothing read the table, so the same swap was invisible -- 0
# failures across all three suites -- and what this oracle caught instead was a
# swap in the two readers' own hand-written case arms. Those arms are gone now;
# the mechanism is identical and the target moved.)
#
# So: do not source config/profiles.sh here, and do not derive this case
# statement from it by any indirect route (eval, a runtime-built variable name,
# or sourcing something that itself sources it). A derived oracle follows the
# table it is checking and both rows above become 0. The plan's Decision 1
# carries the full chain.
_legacy_oracle_expected_var() { # <hostname>
  case "$1" in
  laptop | laptop-1) printf 'LAPTOP' ;;
  studio | studio-1) printf 'STUDIO' ;;
  reception | reception-1) printf 'RECEPTION' ;;
  ratna | ratna-1) printf 'RATNA' ;;
  office | office-1) printf 'OFFICE' ;;
  home-1) printf 'HOMES' ;;
  workstation) printf 'WORKSTATION' ;;
  cruncher) printf 'CRUNCHER' ;;
  *)
    # Returns non-zero rather than printing empty: an empty "expected"
    # string is indistinguishable from "this host legitimately has no
    # legacy var" (a caller's own no_legacy exception set), so an unmapped
    # host has to fail loudly here rather than compare "" to "" and pass.
    # Callers propagate this return rather than composing their own
    # message, so there is exactly one copy of this text to keep current.
    printf 'PROFILE_MAP host "%s" has no legacy-variable mapping in tests/helpers/legacy_oracle.bash (the hand-typed oracle, checked against PROFILE_LEGACY in config/profiles.sh). Add a case arm for it, or add it to the no_legacy exception set if it should intentionally have none.\n' "$1" >&2
    return 1
    ;;
  esac
}
