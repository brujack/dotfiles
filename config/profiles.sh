#!/usr/bin/env bash
# config/profiles.sh — requires bash 5+
# Maps hostnames to profiles and profiles to capabilities.
# Edit PROFILE_MAP to add a new machine — no other file needs changing.

# shellcheck disable=SC2034 # file-wide: both maps below are read by lib/detect_env.sh:detect_env
# PROFILE_MAP and PROFILE_CAPS are both read via `source`, which the linter
# cannot see across files. A directive placed before the first real command
# in a file applies file-wide (verified empirically), so this one line
# covers both declarations below — a second directive on PROFILE_CAPS would
# be redundant.
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
