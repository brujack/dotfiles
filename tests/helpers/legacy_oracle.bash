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
# permutation-invariant assertion built from the table still passes. Measured
# against a clean archive of HEAD, once both production readers consume the
# table: that swap fails 3 tests --
#
#     tests/setup_env/profiles.bats   not ok 25   (bash, via lib/detect_env.sh)
#     tests/zshrc.d/profiles.bats     not ok  1   (zsh, via config/profiles.zsh)
#     tests/setup_env/profiles.bats   not ok 24   (wired/wireless twin equality)
#     tests/zshrc.d/cross_shell.bats  0 failures
#
# That last line is the point, and it is the load-bearing half: cross_shell
# compares the two productions to each other, so when both read the same wrong
# table they still agree and it stays GREEN. Two implementations that agree can
# be wrong together -- the comparison of two productions does not notice this
# class at all, whatever else does.
#
# What it is NOT: "only an oracle notices". An earlier version of this comment
# said that, and said 2 tests, and both were wrong -- not ok 24 is a third
# detector and it is not this oracle. It is one hardcoded end-to-end snapshot
# case comparing studio against studio-1, and the whole snapshot includes the
# LEGACY= line, so a swap landing on exactly one side of THAT pair breaks it.
#
# Its reach is one host, measured both directions rather than reasoned about:
#
#     swap involving studio     ([laptop]/[studio])        3 red
#     swap not involving studio ([office]/[reception])     2 red
#     swap where neither has a twin ([workstation]/[cruncher])  2 red
#
# So the third detector is incidental to the documented mutation rather than a
# general second line of defence -- it is not a loop over the wired/wireless
# pairs, and 11 of the 13 keys are outside its reach. The two per-host
# assertions above compare production output against THIS file and are what
# catches the class.
#
# The receipt was corrected rather than the mutation. Re-wording the documented
# swap to a pair that avoids studio would have made "exactly 2" true as written
# and kept the stronger claim intact -- which is fitting the evidence to the
# conclusion, the exact failure four commits on this branch already exist to
# undo.
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
