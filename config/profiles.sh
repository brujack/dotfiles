#!/usr/bin/env bash
# config/profiles.sh — requires bash 5+
# Maps hostnames to profiles, profiles to capabilities, and hostnames to
# their legacy identity variable name. Adding a new machine means editing
# PROFILE_MAP and PROFILE_LEGACY below (both in this file), plus adding a
# case arm to tests/helpers/legacy_oracle.bash -- 3 edits across 2 files,
# not the single-file edit this comment used to claim.

# shellcheck disable=SC2034 # file-wide: all three maps below are read by lib/detect_env.sh:detect_env and config/profiles.zsh
# PROFILE_MAP, PROFILE_CAPS, and PROFILE_LEGACY are all read via `source`,
# which the linter cannot see across files. A directive placed before the
# first real command in a file applies file-wide (verified empirically), so
# this one line covers all three declarations below — a second directive on
# PROFILE_CAPS or PROFILE_LEGACY would be redundant.
# A `-1` suffix is the machine's wireless-interface hostname -- hostname -s
# returns it whenever the machine is on wifi -- and every wired key below
# must carry a wireless twin mapped to the same profile, or that machine
# silently resolves PROFILE=unknown (and zero HAS_*) the moment it's off
# ethernet. `workstation` and `cruncher` are wired-only by design and
# correctly have no pair. `home-1` is the one exception to the suffix
# meaning "wireless": there the `-1` is part of the machine's actual name, a
# naming mistake kept because a `home-2` may follow.
#
# `reception` carries mac_workstation rather than mac_mini despite being the
# same hardware class as `office`/`home-1`: it was a full-time dev box at
# work and still has the toolchain, though the work has moved to remote SSH.
#
# `ratna` carries mac_workstation because it was a home dev box for years
# and is now a server-room terminal that keeps the full toolchain
# deliberately.
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"      [laptop-1]="personal_laptop"
  [studio]="mac_workstation"      [studio-1]="mac_workstation"
  [reception]="mac_workstation"   [reception-1]="mac_workstation"
  [ratna]="mac_workstation"       [ratna-1]="mac_workstation"
  [office]="mac_mini"             [office-1]="mac_mini"
  [home-1]="mac_mini"
  [workstation]="linux_workstation"
  [cruncher]="wsl2_workstation"
)

declare -A PROFILE_CAPS=(
  [personal_laptop]="gui devtools aws k8s docker rust printing"
  [mac_workstation]="gui devtools aws k8s docker rust printing"
  [mac_mini]="gui printing"
  [linux_workstation]="gui devtools aws k8s docker rust snap flatpak"
  [wsl2_workstation]="gui devtools aws k8s docker rust"
)

# PROFILE_LEGACY maps every PROFILE_MAP hostname key to its legacy identity
# variable name (LAPTOP, STUDIO, ...). Written out explicitly rather than
# derived from the PROFILE_MAP keys (strip "-1", uppercase) because that
# derivation breaks on home-1 -> HOMES: the mechanical result would be HOME,
# and `export HOME=1` in a login shell repoints the user's home directory.
declare -A PROFILE_LEGACY=(
  [laptop]="LAPTOP"          [laptop-1]="LAPTOP"
  [studio]="STUDIO"          [studio-1]="STUDIO"
  [reception]="RECEPTION"    [reception-1]="RECEPTION"
  [ratna]="RATNA"            [ratna-1]="RATNA"
  [office]="OFFICE"          [office-1]="OFFICE"
  [home-1]="HOMES"
  [workstation]="WORKSTATION"
  [cruncher]="CRUNCHER"
)
