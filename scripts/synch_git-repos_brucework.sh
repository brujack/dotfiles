#!/usr/bin/env bash

[[ $(hostname -s) = "studio" ]] && export STUDIO=1

if [[ ${STUDIO} ]]; then
  rsync -ar --delete ~/git-repos/fortis bruce@brucework:~/git-repos/
  echo "synched git-repos/fortis to brucework"
  rsync -ar --delete ~/git-repos/personal bruce@brucework:~/git-repos/
  echo "synched git-repos/personal to brucework"
  rsync -ar --delete ~/git-repos/other bruce@brucework:~/git-repos/
  echo "synched git-repos/other to brucework"
else
  echo "needs to be run on studio"
fi
