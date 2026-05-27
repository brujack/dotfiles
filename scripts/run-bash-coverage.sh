#!/usr/bin/env bash
# Measures bash line coverage using BASH_ENV + PS4 xtrace approach.
# Compatible with bats-core (does not conflict with bats's own DEBUG trap).
# Uses a named pipe to filter trace output in real-time — keeps disk usage small.
#
# Usage: bash scripts/run-bash-coverage.sh [--json /path/out.json]
#   --json  Also write shields.io badge JSON to given path

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACER="${REPO_ROOT}/scripts/bash-tracer.sh"
OUTPUT_DIR="${REPO_ROOT}/coverage"
TRACE_FILE="${OUTPUT_DIR}/bash_trace.txt"
TRACE_FIFO="${OUTPUT_DIR}/bash_trace.fifo"

INCLUDE_FILES=(
    "${REPO_ROOT}/setup_env.sh"
    "${REPO_ROOT}/lib/constants.sh"
    "${REPO_ROOT}/lib/detect_env.sh"
    "${REPO_ROOT}/lib/helpers.sh"
    "${REPO_ROOT}/lib/workflows.sh"
    "${REPO_ROOT}/lib/update_summary.sh"
    "${REPO_ROOT}/lib/developer.sh"
    "${REPO_ROOT}/lib/linux_shared.sh"
    "${REPO_ROOT}/lib/linux_ubuntu.sh"
    "${REPO_ROOT}/lib/macos.sh"
)

mkdir -p "${OUTPUT_DIR}"
rm -f "${TRACE_FILE}" "${TRACE_FIFO}"
mkfifo "${TRACE_FIFO}"

# Filter trace in background — only keep lines from our repo files, normalized.
# Uses python3 normpath to resolve tests/foo/../../lib/bar.sh → lib/bar.sh.
# Prevents trace file from ballooning to GBs by filtering in real-time.
grep -F "COVTRACE:${REPO_ROOT}/" "${TRACE_FIFO}" \
    | grep -oE 'C*COVTRACE:[^:]+:[0-9]+' \
    | grep -F "COVTRACE:${REPO_ROOT}/" \
    | sed 's/^C*COVTRACE://' \
    | python3 -c "
import sys, os
for line in sys.stdin:
    line = line.rstrip()
    if ':' in line:
        p, lineno = line.rsplit(':', 1)
        print(os.path.normpath(p) + ':' + lineno)
    else:
        print(line)
" >> "${TRACE_FILE}" &
grep_pid=$!

test_count=$(grep -rl '^@test' "${REPO_ROOT}/tests/" 2>/dev/null \
    | xargs grep -ch '^@test' 2>/dev/null \
    | awk '{s+=$1} END{print s}')
printf "Running %d tests with coverage tracer...\n" "${test_count}"

# Run bats with tracer — fd 9 goes to the FIFO
export BASH_ENV="${TRACER}"
export _COV_TRACE_FILE="${TRACE_FIFO}"
bats --recursive "${REPO_ROOT}/tests/" 2>&1 | tail -3
unset BASH_ENV _COV_TRACE_FILE

# Allow bg filter to drain and exit
rm -f "${TRACE_FIFO}"
wait "${grep_pid}" 2>/dev/null || true

if [[ ! -f "${TRACE_FILE}" || ! -s "${TRACE_FILE}" ]]; then
    printf "ERROR: no trace data produced — check bash-tracer.sh\n" >&2
    exit 1
fi

trace_lines=$(wc -l < "${TRACE_FILE}")
printf "\nTrace: %d filtered lines\n\n" "${trace_lines}"

# Compute per-file coverage
printf "%-30s  %8s  %8s  %8s\n" "File" "Covered" "Total" "Pct"
printf "%-30s  %8s  %8s  %8s\n" "----" "-------" "-----" "---"

total_covered=0
total_coverable=0

for src_file in "${INCLUDE_FILES[@]}"; do
    [[ ! -f "${src_file}" ]] && continue

    # Count executable lines — exclude blank, comment, and structural keywords.
    # Structural keywords (fi, done, }, else, then, do, esac, ;;) are not
    # emitted by bash xtrace, so counting them as coverable would skew results.
    coverable=0
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "${trimmed}" ]] && continue
        [[ "${trimmed}" == "#"* ]] && continue
        case "${trimmed}" in
            "}"|"fi"|"done"|"esac"|";;"|"then"|"do"|"else") continue ;;
        esac
        [[ "${trimmed}" =~ ^[[:space:]]*\)$ ]] && continue
        ((coverable++))
    done < "${src_file}"

    # Count unique line numbers hit in this file from the filtered trace.
    # Use end-of-line anchor to avoid matching :51 inside :516, etc.
    covered=$(grep -F "${src_file}:" "${TRACE_FILE}" \
        | grep -oE ':[0-9]+$' \
        | tr -d ':' \
        | sort -un \
        | wc -l | tr -d '[:space:]')

    [[ "${covered}" -gt "${coverable}" ]] && covered="${coverable}"

    if [[ "${coverable}" -gt 0 ]]; then
        pct=$(( covered * 100 / coverable ))
    else
        pct=100
    fi

    basename="${src_file##*/}"
    printf "%-30s  %8d  %8d  %7d%%\n" "${basename}" "${covered}" "${coverable}" "${pct}"

    total_covered=$((total_covered + covered))
    total_coverable=$((total_coverable + coverable))
done

if [[ "${total_coverable}" -gt 0 ]]; then
    overall=$(( total_covered * 100 / total_coverable ))
else
    overall=0
fi

printf "\n%-30s  %8d  %8d  %7d%%\n" "TOTAL" "${total_covered}" "${total_coverable}" "${overall}"
printf "\nOverall bash coverage: %d%%\n" "${overall}"

# Optionally write shields.io badge JSON
if [[ "${1:-}" == "--json" && -n "${2:-}" ]]; then
    if [[ "${overall}" -ge 90 ]]; then
        color="brightgreen"
    elif [[ "${overall}" -ge 75 ]]; then
        color="yellow"
    else
        color="red"
    fi
    printf '{"schemaVersion":1,"label":"bash coverage","message":"%d%%","color":"%s"}\n' \
        "${overall}" "${color}" > "${2}"
    printf "Badge JSON written to %s\n" "${2}"
fi
