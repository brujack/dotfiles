#!/usr/bin/env bash

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: restart_fah.sh [-h|--help]

Stops FAHClient, kills any lingering "fah" processes, and starts
FAHClient again.
USAGE
  exit 0
fi

sudo systemctl stop FAHClient

sleep 2

for pid in $(pgrep fah); do
  sudo kill -9 "${pid}"
done

sleep 2

sudo systemctl start FAHClient
