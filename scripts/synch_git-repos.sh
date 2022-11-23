#!/usr/bin/env bash

[[ $(hostname -s) = "studio" ]] && export STUDIO=1

if [[ ${STUDIO} ]]; then
  rsync -ar --delete ~/git-repos bruce@laptop-1:~/
  echo "synched git-repos to laptop-1"
  rsync -ar --delete ~/git-repos bruce@workstation:~/
  echo "synched git-repos to workstation"
  rsync -ar --delete ~/git-repos bruce@ratna:~/
  echo "synched git-repos to ratna"
else
  echo "needs to be run on studio"
fi
