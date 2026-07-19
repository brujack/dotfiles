#!/usr/bin/env bash

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: kill_zombie.sh [-h|--help]

Finds every process matching "<defunct>" (zombie processes, via pgrep)
and sends SIGKILL to each one individually.
USAGE
  exit 0
fi

pattern="<defunct>"

for pid in $(pgrep "${pattern}"); do
  kill -9 "${pid}"
done
