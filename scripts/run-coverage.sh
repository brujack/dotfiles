#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/coverage"

declare -A FLOORS=(
  ["setup_env.sh"]=90
  ["constants.sh"]=90
  ["detect_env.sh"]=90
  ["helpers.sh"]=90
  ["workflows.sh"]=90
  ["update_summary.sh"]=90
  ["developer.sh"]=90
  ["linux.sh"]=75
  ["macos.sh"]=75
)

INCLUDE_PATH="${REPO_ROOT}/setup_env.sh:${REPO_ROOT}/lib"

rm -rf "${OUTPUT_DIR}"
kcov --include-path="${INCLUDE_PATH}" "${OUTPUT_DIR}" bats --recursive "${REPO_ROOT}/tests/"

INDEX="${OUTPUT_DIR}/kcov-merged/index.json"
if [[ ! -f "${INDEX}" ]]; then
  printf "ERROR: kcov did not produce %s — verify kcov >= 38\n" "${INDEX}" >&2
  exit 1
fi

failed=0
printf "\n%-30s %10s %10s %10s\n" "File" "Coverage" "Floor" "Status"
printf "%-30s %10s %10s %10s\n" "----" "--------" "-----" "------"

while IFS= read -r file_json; do
  filepath=$(printf '%s' "${file_json}" | jq -r '.file')
  percent=$(printf '%s' "${file_json}" | jq -r '.percent_covered')
  basename="${filepath##*/}"
  floor="${FLOORS[${basename}]:-90}"
  pct_int=$(printf '%.0f' "${percent}")
  if [[ "${pct_int}" -lt "${floor}" ]]; then
    status="FAIL"
    failed=1
  else
    status="PASS"
  fi
  printf "%-30s %9s%% %9s%% %10s\n" "${basename}" "${pct_int}" "${floor}" "${status}"
done < <(jq -c '.files[]' "${INDEX}")

# Gate not yet enabled — measurement mode only
if [[ "${failed}" -ne 0 ]]; then
  printf "\nFiles below floor noted above (gate will be enabled after floors are met)\n"
fi
printf "\nCoverage measurement complete\n"
