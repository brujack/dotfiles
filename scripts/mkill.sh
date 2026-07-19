#!/usr/bin/env bash

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: mkill.sh <pattern>

Finds every process matching <pattern> (via pgrep) and sends SIGKILL
to each one individually, using sudo.
USAGE
  exit 0
fi

pattern="${1:?Usage: mkill.sh <pattern>}"

for pid in $(pgrep "${pattern}"); do
  sudo kill -9 "${pid}"
done
