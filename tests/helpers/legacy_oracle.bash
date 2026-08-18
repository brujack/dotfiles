#!/usr/bin/env bash
# tests/helpers/legacy_oracle.bash — shared oracle for the legacy identity
# variable each PROFILE_MAP hostname is expected to resolve to. Used by both
# tests/zshrc.d/profiles.bats (zsh-side) and tests/setup_env/profiles.bats
# (bash-side) so there is exactly one copy of this mapping and one copy of
# its diagnostic message.
#
# Deliberately hand-typed rather than derived from the production table: a
# swapped pair in that table (e.g. laptop<->studio) leaves the hostname
# count unchanged, so every permutation-invariant assertion built from the
# same table would still pass -- measured 0 failures across all three
# profile suites for exactly that swap. This oracle is the only thing that
# would ever notice, and only because it asserts each mapping independently
# from a source that cannot be swapped along with the table it is checking.
# Do not source the production table here, and do not derive this case
# statement from it by any indirect route (eval, a runtime-built variable
# name, or sourcing something that itself sources it) -- doing so
# reintroduces exactly the blind spot this file exists to close.
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
    printf 'PROFILE_MAP host "%s" has no legacy-variable mapping in tests/helpers/legacy_oracle.bash. Add a case arm for it, or add it to the no_legacy exception set if it should intentionally have none.\n' "$1" >&2
    return 1
    ;;
  esac
}
