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
# The mutation that tests this is a SELF-CONSISTENT swap: [laptop] and
# [laptop-1] both to "STUDIO", [studio] and [studio-1] both to "LAPTOP". Every
# name is still present, the key count is unchanged, and the table stays
# internally consistent -- so every permutation-invariant assertion built from
# the table still passes, and only an oracle derived by a DIFFERENT mechanism
# than the table can notice.
#
# Measured as a 2x2 against a clean archive of 21671b8, isolating the two
# oracle-based per-host assertions (zsh profiles.bats "not ok 1", bash
# profiles.bats "not ok 25"):
#
#     oracle       table             zsh per-host   bash per-host
#     hand-typed   intact            green          green
#     hand-typed   consistent swap   FIRES          FIRES
#     derived      consistent swap   green          green      <- the decision
#     derived      intact            green          green
#
# Row 3 is why this file is not derived. A derived oracle follows the table it
# checks, so production and oracle agree on the swapped values and both
# assertions pass -- the defect ships.
#
# tests/zshrc.d/cross_shell.bats cannot help either, one level out for the same
# reason: it compares the two PRODUCTIONS to each other, so when both read the
# same wrong table they agree. Two implementations that agree can be wrong
# together.
#
# Do NOT verify this with a swap of the non-suffixed keys alone. That leaves the
# table internally INCONSISTENT (laptop -> STUDIO while laptop-1 -> LAPTOP), so
# the wireless-twin assertions catch it without reference to this file at all --
# it reddens 3 tests and demonstrates twin-consistency, not oracle
# independence. Three successive revisions of this comment documented that
# malformed variant, each correcting the previous one's count while none
# questioned whether the mutation tested the property being claimed. See
# ADR-0021 and behavior.md's "the boundary can be wrong on the question, not the
# claim".
#
# So: do not source config/profiles.sh here, and do not derive this case
# statement from it by any indirect route (eval, a runtime-built variable name,
# or sourcing something that itself sources it).
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
