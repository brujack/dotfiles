#!/usr/bin/env bash
# Measures bash line coverage using BASH_ENV + PS4 xtrace approach.
# Compatible with bats-core (does not conflict with bats's own DEBUG trap).
# Uses a named pipe to filter trace output in real-time — keeps disk usage small.
#
# Usage: bash scripts/run-bash-coverage.sh [--json /path/out.json]
#   --json  Also write shields.io badge JSON to given path
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: run-bash-coverage.sh [--json /path/out.json]
       run-bash-coverage.sh --list-sources
       run-bash-coverage.sh --count-coverable <file>

Measures bash line coverage using BASH_ENV + PS4 xtrace tracing of the
full bats suite. Prints a per-file coverage table and overall percentage.

  --json /path/out.json   Also write a shields.io badge JSON to given path

Inspecting the figure without a full run (both exit immediately):

  --list-sources          Print the instrumented set — setup_env.sh plus
                          lib/*.sh, derived at run time, not a literal list
  --count-coverable FILE  Print one file's coverable-line count, the
                          denominator of its percentage. Exits 2 on a missing,
                          unreadable, or absent argument rather than printing 0
USAGE
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACER="${REPO_ROOT}/scripts/bash-tracer.sh"
OUTPUT_DIR="${REPO_ROOT}/coverage"
TRACE_FILE="${OUTPUT_DIR}/bash_trace.txt"
TRACE_FIFO="${OUTPUT_DIR}/bash_trace.fifo"

# The instrumented set is derived, not listed. A literal array cannot fail
# loudly: an omitted file is absent from the numerator AND the denominator, so
# the reported percentage is unchanged by its absence rather than lowered by it.
# That is how lib/git_hooks.sh went missing, and how lib/package_capture.sh
# stayed missing afterwards — 13 of 36 tracked .sh files were measured while the
# report read 91%.
#
# The predicate is stated rather than enumerated so it keeps holding as files
# are added: every library under lib/, plus the entry point that sources them.
# Standalone operational scripts (kubernetes_stuff/, scripts/) are deliberately
# out of scope — no bats suite sources them, so including them would add pure
# zeros to the denominator and measure nothing.
# Tracked files, via git — not a filesystem glob. A glob also picks up a
# developer's untracked scratch file under lib/, which silently joins the
# denominator locally and makes `make bash-coverage` disagree with CI on the
# same commit. It is also what the regression test asserts against, so a glob
# would let the two drift apart without either complaining.
INCLUDE_FILES=("${REPO_ROOT}/setup_env.sh")
while IFS= read -r _src; do
    [[ -n "${_src}" ]] && INCLUDE_FILES+=("${REPO_ROOT}/${_src}")
done < <(git -C "${REPO_ROOT}" ls-files 'lib/*.sh' 2>/dev/null)

# Falling back to the glob would reintroduce the local-vs-CI drift above, and a
# silently short instrumented set is exactly this script's original defect.
if [[ "${#INCLUDE_FILES[@]}" -le 1 ]]; then
    printf "ERROR: no tracked lib/*.sh found — is this a git checkout?\n" >&2
    exit 1
fi

# Lets the set be asserted without running the full suite under the tracer,
# which takes minutes. Also answers "what is actually measured?" for an operator
# reading a coverage number.
if [[ "${1:-}" == "--list-sources" ]]; then
    printf '%s\n' "${INCLUDE_FILES[@]}"
    exit 0
fi

# Regex for case branch labels — stored in variable to avoid zsh parse error on | inside inline character class
# Matches: brew), mas), OK), *), oh-my-zsh|tpm|tfenv|zsh-autosuggestions), etc.
_case_label_re="^[a-zA-Z_*][a-zA-Z0-9_.*-]*([|][a-zA-Z0-9_.*-]+)*[)]$"


# Counts executable bash lines in one file — the denominator for its percentage.
# Extracted from the loop below so it can be asserted directly; the whole tracer
# run takes minutes, which is too slow to be a unit test of the arithmetic.
#
# Excludes blank lines, comments, and structural keywords (fi, done, }, else,
# then, do, esac, ;;) — bash xtrace never emits those, so counting them would
# report them as permanently uncovered.
#
# Also excludes the body of a multi-line `python3 -c "..."`. Those lines are
# Python: xtrace emits one line for the whole invocation, so counting the body
# inflates the denominator with lines no test can ever cover. In
# lib/package_capture.sh that was 50 of 107 counted lines — the file read 22%
# against a ceiling it could not reach. Bash line coverage does not measure
# embedded Python, and excluding it says so rather than scoring it as missing.
# A single-line `python3 -c "..."` closes its quote on the same line and is
# ordinary bash, so it still counts.
_count_coverable_lines() {
    local _file="${1}" _line _trimmed _after
    local _coverable=0 _in_embedded=0
    while IFS= read -r _line; do
        _trimmed="${_line#"${_line%%[![:space:]]*}"}"
        if [[ "${_in_embedded}" -eq 1 ]]; then
            # The closing delimiter is a line whose first non-space character is
            # the double quote that ends the -c argument. It carries whatever
            # bash follows on the same line: bare ", or ") , or " \ , or
            # " >> file &. Matching only the bare forms leaves the counter stuck
            # inside the string to end of file, silently swallowing every
            # remaining line — which is how the first version of this fix read a
            # 8-line fixture as 2 coverable lines.
            # Limitation: a Python line starting with a double quote would end
            # the region early. None exists in the instrumented set, and the
            # convention in these blocks is single-quoted Python strings.
            [[ "${_trimmed}" == '"'* ]] && _in_embedded=0
            continue
        fi
        # Blank and comment skips MUST come before the opener detection below.
        # The opener is matched against the raw line, so a comment that merely
        # mentions `python3 -c "` would set the skip state, and since no later
        # line starts with a quote, every remaining line in the file gets
        # swallowed to EOF. That inflates the percentage rather than lowering it
        # — the one direction a gate at exactly 90% with no headroom fails green
        # instead of red. Writing such a comment above one of
        # lib/package_capture.sh's blocks is now the natural thing to do, since
        # this change is what made those blocks special.
        [[ -z "${_trimmed}" ]] && continue
        [[ "${_trimmed}" == "#"* ]] && continue
        if [[ "${_line}" == *'python3 -c "'* ]]; then
            _after="${_line#*python3 -c \"}"
            [[ "${_after}" != *'"'* ]] && _in_embedded=1
        fi
        case "${_trimmed}" in
            "}" | "fi" | "done" | "esac" | ";;" | "then" | "do" | "else") continue ;;
        esac
        [[ "${_trimmed}" =~ ^[[:space:]]*\)$ ]] && continue
        # Case branch labels (brew), mas), OK), *), oh-my-zsh|tpm|...) — xtrace never emits them
        # Regex in variable avoids zsh parse error on | inside inline character class
        [[ "${_trimmed}" =~ ${_case_label_re} ]] && continue
        # done with any redirect (done <<< ..., done < <(...), done < file)
        [[ "${_trimmed}" =~ ^done[[:space:]] ]] && continue
        # Continuation lines of multi-line pipelines (> outfile, > /dev/null)
        [[ "${_trimmed}" =~ ^\> ]] && continue
        # Closing group command with redirect (} >> file, } | cmd)
        [[ "${_trimmed}" =~ ^\}[[:space:]] ]] && continue
        ((_coverable++))
    done < "${_file}"
    printf '%s\n' "${_coverable}"
}

# Same purpose as --list-sources: make an input to the reported percentage
# checkable without running the suite under the tracer.
#
# Both error paths matter more than they look. A missing file used to print 0
# and exit 0 — a confident wrong answer from the one flag whose job is auditing
# the denominator, which is the same failure this script was just fixed for. And
# a bare --count-coverable with no argument used to fall through to a full
# multi-minute tracer run, so a typo cost several minutes and then reported a
# coverage number the operator never asked for.
if [[ "${1:-}" == "--count-coverable" ]]; then
    if [[ -z "${2:-}" ]]; then
        printf "ERROR: --count-coverable requires a file argument\n" >&2
        exit 2
    fi
    if [[ ! -f "${2}" ]]; then
        printf "ERROR: --count-coverable: no such file: %s\n" "${2}" >&2
        exit 2
    fi
    if [[ ! -r "${2}" ]]; then
        printf "ERROR: --count-coverable: not readable: %s\n" "${2}" >&2
        exit 2
    fi
    _count_coverable_lines "${2}"
    exit 0
fi

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

    coverable="$(_count_coverable_lines "${src_file}")"

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
