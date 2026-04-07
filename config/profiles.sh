#!/usr/bin/env bash
# config/profiles.sh — requires bash 5+
# Maps hostnames to profiles and profiles to capabilities.
# Edit PROFILE_MAP to add a new machine — no other file needs changing.

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
  [linux_workstation]="gui devtools aws k8s docker rust snap"
  [wsl2_workstation]="gui devtools aws k8s docker rust"
  [server]="devtools aws"
)
