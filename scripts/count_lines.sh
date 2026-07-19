#!/usr/bin/env bash

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: count_lines.sh directory_path [directory_path_to_ignore]

Recursively counts lines across all files under directory_path (no
trailing slash), optionally pruning one directory_path_to_ignore
(also no trailing slash), and prints a per-file breakdown plus total.
USAGE
  exit 0
fi

if [[ -z "${1:-}" ]]; then
  printf "Usage: %s directory_path directory_path_to_ignore with no trailing slashes\n" "${0}"
  exit 1
fi

dir_path="${1}"
dir_ignore="${2:-}"

total_lines=0

while read -r file; do
  lines=$(wc -l <"${file}")
  total_lines=$((total_lines + lines))
  printf "%s has %s lines\n" "${file}" "${lines}"
done < <(find "${dir_path}" -type d -path "${dir_ignore}" -prune -o -type f -print)

printf "Total lines: %s\n" "${total_lines}"
