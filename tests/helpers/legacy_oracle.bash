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
# The mutation that tests this is a SELF-CONSISTENT swap of two values, both
# members of each wired/wireless pair: [reception] and [reception-1] to "RATNA",
# [ratna] and [ratna-1] to "RECEPTION". All 13 keys remain, all eight names
# remain, and the value multiset is unchanged -- so the table is still
# internally consistent and every permutation-invariant assertion built from it
# still passes.
#
# Measured as a 2x2 against a clean archive per cell, baseline verified green
# first, isolating the two oracle-based per-host assertions (zsh profiles.bats
# "not ok 1", bash profiles.bats "not ok 25"):
#
#     oracle       table                  zsh not ok 1   bash not ok 25
#     hand-typed   intact                 green          green
#     hand-typed   reception<->ratna      FIRES          FIRES
#     derived      reception<->ratna      green          green     <- the point
#     derived      intact                 green          green
#
# Row 3 is why this file is not derived. A derived oracle follows the table it
# checks, so production and oracle agree on the swapped values and both
# assertions pass. Under that swap the hand-typed oracle produces exactly those
# two reds and nothing else across all four affected suites; a derived one
# produces none.
#
# tests/zshrc.d/cross_shell.bats cannot help either, one level out for the same
# reason: it compares the two PRODUCTIONS to each other, so when both read the
# same wrong table they agree. Two implementations that agree can be wrong
# together.
#
# TWO MUTATIONS THAT LOOK EQUIVALENT AND ARE NOT. Both were documented here
# before this one, each correcting the previous one's count while neither asked
# whether the mutation isolated the property being claimed:
#
#   - Swapping only the non-suffixed keys ([laptop] without [laptop-1]) leaves
#     the table internally INCONSISTENT, so the wireless-twin assertions catch
#     it with no reference to this file. It proves twin-consistency.
#   - Swapping [laptop]<->[studio] consistently is caught by two further
#     detectors that are not this oracle and fire even when the oracle IS
#     derived: a hardcoded "STUDIO" literal in tests/zshrc.d/profiles.bats and a
#     studio-specific assertion in tests/zshrc.d/unit.bats. So "the defect
#     ships" is false for that pair -- the suite still goes red.
#
# reception<->ratna is used precisely because no other assertion pins a
# host-specific expectation for either one. Both names DO appear across the
# suites -- in `unset` isolation lists, in `for v in <all eight>` loops, and in
# the set-equality want-list -- but only ever as members of the eight-name set,
# never as "host X must resolve to Y". Measured: STUDIO appears 66 times outside
# this file and LAPTOP 43, and those counts include real per-host assertions,
# which is exactly why the laptop<->studio pair cannot isolate the variable. The
# set-equality test stays green because the swap preserves the value multiset. Choosing a mutation that isolates
# the variable under test is not the same as re-wording a mutation to preserve a
# false count -- an earlier revision of this comment warned against the latter,
# correctly, and that warning does not apply here.
#
# So: do not source config/profiles.sh here, and do not derive this case
# statement from it by any indirect route (eval, a runtime-built variable name,
# or sourcing something that itself sources it). ADR-0021 carries the full
# chain, including the four successive revisions this receipt needed.
#
# (Before 12e302c nothing read the table, so the same swap was invisible -- 0
# failures across all three suites -- and what this oracle caught instead was a
# swap in the two readers' own hand-written case arms. Those arms are gone now;
# the mechanism is identical and the target moved.)
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
