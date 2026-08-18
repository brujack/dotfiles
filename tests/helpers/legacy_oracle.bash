#!/usr/bin/env bash
# tests/helpers/legacy_oracle.bash — shared oracle for the legacy identity
# variable each PROFILE_MAP hostname is expected to resolve to. Used by both
# tests/zshrc.d/profiles.bats (zsh-side) and tests/setup_env/profiles.bats
# (bash-side) so there is exactly one copy of this mapping and one copy of
# its diagnostic message.
#
# Deliberately hand-typed rather than derived from PROFILE_LEGACY in
# config/profiles.sh. Two measurements, and they describe different commits --
# stating only the first is what made an earlier version of this comment wrong:
#
#   * Today, this oracle's value is catching a swap in the two production
#     readers' own case arms. Swap laptop<->studio in BOTH lib/detect_env.sh
#     and config/profiles.zsh and it fails 2 tests -- while
#     tests/zshrc.d/cross_shell.bats stays GREEN, because that suite compares
#     the two productions to each other and both moved together. That mutual
#     blind spot is precisely what an independent oracle closes.
#
#   * A swap in PROFILE_LEGACY itself is invisible right now -- 0 failures
#     across all three profile suites -- because no production code reads that
#     table yet. Once it does, the same swap fails the same 2 tests, from the
#     table instead of the case arms.
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
