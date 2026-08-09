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
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"
  [studio]="mac_workstation"
  [reception]="mac_workstation"
  [office]="mac_mini"
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
  [server]="devtools aws"
)
