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
       run-bash-coverage.sh --file-coverage <file> <trace_file>

Measures bash line coverage using BASH_ENV + PS4 xtrace tracing of the
full bats suite. Prints a per-file coverage table and overall percentage.

  --json /path/out.json   Also write a shields.io badge JSON to given path

Inspecting the figure without a full run (all three exit immediately):

  --list-sources          Print the instrumented set — setup_env.sh plus
                          tracked config/*.sh, lib/*.sh, and scripts/*.sh
                          (plus the extensionless hooks scripts/pre-push and
                          scripts/commit-msg), less scripts/bash-tracer.sh,
                          derived at run time from git, not a literal list
  --count-coverable FILE  Print one file's static coverable-line count, the
                          heuristic half of its denominator. Exits 2 on a
                          missing, unreadable, or absent argument rather than
                          printing 0
  --file-coverage FILE TRACE_FILE
                          Print FILE's covered count, union-corrected
                          coverable count (heuristic ∪ what TRACE_FILE
                          actually contains for FILE), and any heuristic
                          disagreements — the same computation the full run
                          does per file, against a trace file you supply
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
# are added: every library under lib/, the config/ files those libraries source
# (lib/detect_env.sh sources config/profiles.sh, lib/git_hooks.sh sources
# config/hook_repos.sh, and the bats suites exercise both paths), plus the entry
# point, plus the operational scripts under scripts/ — every one of which the
# bats suite executes as a subprocess, so BASH_ENV reaches them and their trace
# lines were already being collected and then discarded by a predicate that
# globbed only config/ and lib/. This retracts an earlier version of this
# comment, which called scripts/ deliberately out of scope on the grounds that
# nothing under test sources them; that was asserted, never measured, and it
# was wrong — measured 2026-08-08, every tracked file under scripts/ is
# executed by the bats suite, between 2 and 29 times each. That is the test the
# predicate applies: is this file reached by the suite, not where does it live.
# Tracked files, via git — not a filesystem glob. A glob also picks up a
# developer's untracked scratch file under lib/, which silently joins the
# denominator locally and makes `make bash-coverage` disagree with CI on the
# same commit. It is also what the regression test asserts against, so a glob
# would let the two drift apart without either complaining.
INCLUDE_FILES=("${REPO_ROOT}/setup_env.sh")
while IFS= read -r _src; do
    [[ -n "${_src}" ]] && INCLUDE_FILES+=("${REPO_ROOT}/${_src}")
done < <(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    git -C "${REPO_ROOT}" ls-files 'config/*.sh' 'lib/*.sh' 'scripts/*.sh' \
    'scripts/pre-push' 'scripts/commit-msg' 2>/dev/null)

# scripts/bash-tracer.sh is excluded AFTER the git ls-files derivation above,
# not by narrowing the scripts/*.sh predicate itself — the predicate must keep
# matching scripts/*.sh generally; only this one file is structurally
# uncoverable. It is the file BASH_ENV points every traced subprocess at, and
# `set -x` is its own LAST command: its five preceding lines run before
# tracing turns on, and nothing follows it, so zero trace lines are ever
# attributed to it. Verified:
#   _COV_TRACE_FILE=$PWD/tr.txt BASH_ENV=scripts/bash-tracer.sh bash -c 'x=1; y=2'
#   grep -c 'bash-tracer.sh' tr.txt   -> 0
#   wc -l < tr.txt                    -> 2   (the traced subprocess's own
#                                              commands DO appear)
# It measures 0/6 and would sit there permanently dragging the denominator
# down — that is uncoverable by construction, not untested, so it is excluded
# with the measurement rather than left to look like a testing gap.
_filtered_include_files=()
for _f in "${INCLUDE_FILES[@]}"; do
    [[ "${_f}" == "${TRACER}" ]] && continue
    _filtered_include_files+=("${_f}")
done
INCLUDE_FILES=("${_filtered_include_files[@]}")
unset _filtered_include_files

# Falling back to the glob would reintroduce the local-vs-CI drift above, and a
# silently short instrumented set is exactly this script's original defect.
if [[ "${#INCLUDE_FILES[@]}" -le 1 ]]; then
    printf "ERROR: no tracked config/*.sh or lib/*.sh found — is this a git checkout?\n" >&2
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
# Matches: brew), mas), OK), *), oh-my-zsh|tpm|tfenv|zsh-autosuggestions), -h | --help),
# sync | check) ;; (an empty-body arm — the trailing ;; is part of the label line and
# carries no command, so xtrace never emits it either; a label followed by a REAL
# command before the ;; is deliberately excluded from this pattern and still counts).
_case_label_re="^-{0,2}[a-zA-Z_*][a-zA-Z0-9_.*-]*([[:space:]]*[|][[:space:]]*-{0,2}[a-zA-Z0-9_.*-]+)*[)][[:space:]]*(;;)?[[:space:]]*$"

# Regex for a heredoc opener: `<<` or `<<-`, optional whitespace, optional quote,
# then the delimiter identifier. Deliberately does not require the closing quote to
# match (POSIX ERE has no backreferences) — the delimiter word alone is enough to
# find the terminator line later. Stored in variable for the same zsh-parse reason
# as _case_label_re, even though this one has no `|`.
_heredoc_open_re='<<-?[[:space:]]*["'"'"']?([A-Za-z_][A-Za-z0-9_]*)'

# There is deliberately no function-declaration exclusion here. A synthetic
# single-process fixture (bash -x -c 'source f; f') suggested a bare
# `name() {` header line is never traced, but a real tracer pass over the
# bats suite contradicted that at scale — 150 of 189 measured heuristic
# disagreements were function-declaration lines the trace actually emitted
# (e.g. lib/detect_env.sh:4 `detect_env() {`, traced twice). Under BASH_ENV
# with xtrace already active — how the real tracer runs, not how the
# synthetic fixture ran it — defining a function IS a traced command.
# Removing the exclusion (rather than narrowing it) trusts the measured
# fleet data over the one fixture; header lines now count like any other
# code, which can only lower the reported percentage, never inflate it.

# Regex for a line ending in a run of trailing backslashes — a candidate line
# continuation. Whether it actually IS one depends on the run's parity, not
# just its presence: outside quotes, a lone trailing backslash escapes the
# newline and splices the next physical line onto the same logical command,
# so xtrace only ever emits the FIRST physical line. A run of TWO trailing
# backslashes is an escaped (literal) backslash character — the pair cancels
# out and the real newline terminates the statement normally. Verified with
# PS4='T:${LINENO}: ': `printf '%s\n' \` + a continued arg traces once, on
# the opener; `echo "foo" \\` traces on its own line and the next line traces
# separately too. Captured via BASH_REMATCH and length-checked for parity
# rather than counted by hand, the same idiom the heredoc quote-parity check
# above already uses.
_continuation_re='\\+$'

# Regex for a top-level compound-list operator (||, &&, |, ;) appearing
# anywhere on a continuation-swallowed line. A PURE-argument continuation
# line (e.g. a lone `-H "..."` flag, or a bare string in a multi-line
# `printf` arg list) is never separately traced — it's just more words in
# the same command. But a continuation line that itself BEGINS OR CONTAINS a
# new command is traced on its own line number, verified with
# PS4='T:${LINENO}: ': `curl ... \` + `-H ... || true` traces both physical
# lines, because `|| true` starts a fresh command on the second one. Applied
# to a comment-stripped line so a separator character inside a trailing
# comment cannot trigger it. Deliberately over-inclusive where genuinely
# ambiguous (e.g. a `|`/`;` inside an unstripped quoted argument would still
# match) — an under-excluded line only lowers the reported percentage, which
# is the conservative direction per tdd.md's Coverage Denominators section;
# an over-excluded one is the failure this whole class of fix exists for.
_cmd_sep_re='(\|\||&&|\||;)'

# Regex for a continuation-swallowed line that closes a command substitution
# with a bare `)` at end of line — e.g. the second physical line of
# `var=$(cmd "a" \` / `  "b")`. Verified with
# BASH_ENV=scripts/bash-tracer.sh against exactly that shape: for a
# `var=$(...)` assignment whose command substitution spans a backslash
# continuation, bash attributes the WHOLE assignment's xtrace line to
# wherever the substitution's closing `)` lands — the LAST physical line —
# not the opener, unlike every other continuation shape here. Applied to a
# comment-stripped line, same as `_cmd_sep_re`. Deliberately over-inclusive
# for a plain (non-assignment) command whose continuation also closes with
# `$(...)` on the last line — verified that real xtrace still attributes
# those to the opener, so treating the closer as coverable too only ever
# lowers the reported percentage, never inflates it.
_cont_close_paren_re='\)[[:space:]]*$'

# The python3 -c opener pattern, held in a variable rather than inlined as a
# literal in the `%%` prefix-extraction below — zsh's parser (unlike bash's)
# rejects a raw `"` inside a single-quoted literal nested inside a
# double-quoted parameter expansion (`"${_code%%'python3 -c "'*}"`), the same
# class of nesting problem `_case_label_re`/`_heredoc_open_re` already avoid
# by living in variables. Verified with `zsh -n` directly.
_pyc_pattern='python3 -c "'

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
#
# Also excludes heredoc bodies and their terminator line (any interpreter, any
# quoting: `<<'EOF'`, `<<EOF`, `<<-EOF`) — xtrace only ever emits the opener line,
# never the body or the terminator, verified the same way as the python3/array
# cases above. A bare `{` on its own line is excluded too, as purely
# structural. Function-declaration header lines are NOT excluded — see the
# "deliberately no function-declaration exclusion" comment near the top of
# this file for why.
#
# `_mode` selects the output shape: "count" (default) prints the final total
# only, exactly the original contract every existing caller relies on.
# "lines" instead prints each coverable line's 1-indexed line number as it is
# found, and prints no total — used by _file_coverage_report below to union
# this static prediction against what a trace file actually contains. Static
# behavior (mode=count) is byte-for-byte unchanged by this parameter existing.
_count_coverable_lines() {
    local _file="${1}" _mode="${2:-count}" _line _trimmed _after _code
    local _coverable=0 _in_embedded=0 _in_array=0 _in_heredoc=0 _heredoc_delim=""
    local _in_continuation=0 _bs_run _lineno=0
    local _hd_scan _hd_match _hd_delim _hd_prefix _hd_sq _hd_dq
    local _pyc_prefix _pyc_sq _pyc_dq
    # `|| [[ -n "${_line}" ]]` belongs on the read, not after done: read returns
    # non-zero on a final line with no trailing newline, having still populated
    # _line. Without it that last line is dropped, undercounting the denominator
    # and inflating the percentage.
    while IFS= read -r _line || [[ -n "${_line}" ]]; do
        ((_lineno++))
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
        # Heredoc body/terminator: checked early, like the python3-c region above,
        # because a heredoc body can contain arbitrary text — including lines that
        # look like bash comments or blank lines — none of which should be run
        # through bash-specific logic while still inside the body. The terminator
        # line itself is excluded too (bash never traces it); _trimmed already has
        # leading whitespace stripped, which is sufficient to match both the plain
        # and `<<-` (leading-tab-stripped) forms without tracking which was used.
        if [[ "${_in_heredoc}" -eq 1 ]]; then
            if [[ "${_trimmed}" == "${_heredoc_delim}" ]]; then
                _in_heredoc=0
                _heredoc_delim=""
            fi
            continue
        fi
        # Continuation-swallowed line: the previous physical line ended in a
        # real trailing backslash, so THIS line is spliced onto it as the same
        # logical command. Checked before the blank/comment skips below, and
        # unconditionally, because a swallowed line must never be evaluated by
        # ITS own blank/comment logic — it isn't a line in its own right.
        #
        # But "spliced onto the same logical command" does not mean "never
        # traced": a swallowed line that itself begins or contains a new
        # top-level command (a `||`/`&&`/`|`/`;` compound-list operator) IS
        # traced, on its own line number — only a PURE-argument continuation
        # (more words in the same one command, e.g. a lone `-H "..."` flag)
        # is truly inert. Verified: `curl ... \` + `-H ... || true` traces
        # BOTH physical lines, because `|| true` starts a fresh command on
        # the second one, while `curl ... \` + `-H "Authorization: ..." \`
        # traces only the opener. A comment ends the continuation outright: a
        # `#` starts a real comment consuming the rest of the (still single)
        # logical line, so its trailing content — separator or backslash —
        # is inert either way. Verified against real bash: `a=1 \` followed
        # by a blank line, or by a `# comment` line, both trace only the
        # opener — the statement after either is a fresh one, not spliced in.
        #
        # A line ending in a bare `)` also falls through — see
        # `_cont_close_paren_re`'s definition for the command-substitution
        # attribution this covers.
        if [[ "${_in_continuation}" -eq 1 ]]; then
            if [[ "${_trimmed}" == "#"* ]]; then
                _in_continuation=0
                continue
            fi
            if [[ "${_trimmed%%#*}" =~ ${_cmd_sep_re} || "${_trimmed%%#*}" =~ ${_cont_close_paren_re} ]]; then
                # A real command lives on this line — fall through to normal
                # processing (do NOT `continue`) so it gets counted. Reset
                # continuation state now; the "opens a continuation" check
                # further down re-derives whether THIS line also chains
                # further, from its own trailing backslash (e.g. a run of
                # `&&  \` lines all fall through this way in turn).
                _in_continuation=0
            else
                if [[ "${_line}" =~ ${_continuation_re} ]]; then
                    _bs_run="${BASH_REMATCH[0]}"
                    if (( ${#_bs_run} % 2 == 1 )); then
                        _in_continuation=1
                    else
                        _in_continuation=0
                    fi
                else
                    _in_continuation=0
                fi
                continue
            fi
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
        # Known limit, measured with PS4='+LINE:${LINENO}': a PREFIXED opener
        # (declare/readonly/local) is traced at the opener line, which is what
        # this counts. A BARE `PLAIN=(` is traced at the CLOSING paren instead,
        # so for that form the counted opener is never traced and the traced
        # paren is excluded — ±1 line, self-cancelling in aggregate. There are
        # no bare multi-line arrays in the instrumented set; all 5 are prefixed.
        #
        # Element lines of a multi-line array literal are not separate commands.
        # bash xtrace emits the whole assignment as one line — verified:
        #   declare -A M=(\n [a]="one"\n [b]="two"\n)  ->  + M=([a]=one [b]=two)
        # so counting each element inflates the denominator with lines no test
        # can reach, exactly as the embedded-Python case above does. In
        # config/profiles.sh that is 13 of 15 counted lines, which is why adding
        # config/ to the instrumented set moved the figure almost entirely by
        # adding uncoverable denominator. The opening line is a real command and
        # still counts; the closing ")" is already skipped as structural.
        if [[ "${_in_array}" -eq 1 ]]; then
            [[ "${_trimmed}" == ")"* ]] && _in_array=0
            continue
        fi
        [[ "${_trimmed%%#*}" =~ =\($ ]] && _in_array=1

        # Match the opener against the line with any trailing comment removed.
        # Testing the raw line meant `b=2  # see python3 -c "import json` opened
        # a skip region and swallowed the rest of the file — inflating the
        # percentage, the fail-green direction. Moving the leading-comment skip
        # above this check only fixed the case where the comment starts the line.
        #
        # The quote-parity check on the prefix (same idea as the heredoc
        # opener's `_hd_prefix` check below) rejects a match that is itself
        # inside an already-open quoted string — e.g. this detector's own
        # source, `if [[ "${_code}" == *'python3 -c "'* ]]; then`, mentions
        # the pattern as a single-quoted literal for comparison, not as a
        # real invocation. Without the check, that line opened a false
        # region that swallowed every real line after it until one happened
        # to start with a bare `"`; found by running this heuristic against
        # its own source file, not by reasoning about it.
        _code="${_trimmed%%#*}"
        if [[ "${_code}" == *"${_pyc_pattern}"* ]]; then
            _pyc_prefix="${_code%%"${_pyc_pattern}"*}"
            _pyc_sq="${_pyc_prefix//\'/}"
            _pyc_dq="${_pyc_prefix//\"/}"
            if (( (${#_pyc_prefix} - ${#_pyc_sq}) % 2 == 0 && (${#_pyc_prefix} - ${#_pyc_dq}) % 2 == 0 )); then
                _after="${_code#*python3 -c \"}"
                [[ "${_after}" != *'"'* ]] && _in_embedded=1
            fi
        fi
        # Heredoc opener. `<<<` (here-string, single-line, no body/terminator) is
        # blanked out first — without that, its trailing `<` reads as the tail of
        # a truncated `<<` match (e.g. `read -r x <<< foo` would otherwise be
        # misread as opening a heredoc with delimiter "foo", consuming every line
        # after it as an unterminated body). The quote-parity check on the prefix
        # rejects a `<<` that is itself inside an already-open string, e.g.
        # `msg='See <<EOF for docs'` — not a real heredoc, ordinary bash line.
        # Known limitation: does not track escaped quotes (\") inside the prefix.
        _hd_scan="${_code//"<<<"/  }"
        if [[ "${_hd_scan}" =~ ${_heredoc_open_re} ]]; then
            _hd_match="${BASH_REMATCH[0]}"
            _hd_delim="${BASH_REMATCH[1]}"
            _hd_prefix="${_hd_scan%%"${_hd_match}"*}"
            _hd_sq="${_hd_prefix//\'/}"
            _hd_dq="${_hd_prefix//\"/}"
            if (( (${#_hd_prefix} - ${#_hd_sq}) % 2 == 0 && (${#_hd_prefix} - ${#_hd_dq}) % 2 == 0 )); then
                _in_heredoc=1
                _heredoc_delim="${_hd_delim}"
            fi
        fi
        case "${_trimmed}" in
            "{" | "}" | "fi" | "done" | "esac" | ";;" | "then" | "do" | "else") continue ;;
        esac
        [[ "${_trimmed}" =~ ^[[:space:]]*\)$ ]] && continue
        # Case branch labels (brew), mas), OK), *), oh-my-zsh|tpm|..., -h | --help),
        # sync | check) ;;) — xtrace never emits them.
        # Regex in variable avoids zsh parse error on | inside inline character class
        [[ "${_trimmed}" =~ ${_case_label_re} ]] && continue
        # done with any redirect (done <<< ..., done < <(...), done < file)
        [[ "${_trimmed}" =~ ^done[[:space:]] ]] && continue
        # Continuation lines of multi-line pipelines (> outfile, > /dev/null)
        [[ "${_trimmed}" =~ ^\> ]] && continue
        # Closing group command with redirect (} >> file, } | cmd)
        [[ "${_trimmed}" =~ ^\}[[:space:]] ]] && continue
        # This line survived every exclusion above and is real code — it still
        # counts here as the continuation's opener/anchor, same as a heredoc or
        # array opener does. Checked against the RAW line, not the
        # comment-stripped `_code`: a trailing comment means the backslash is
        # not actually the line's last character, so it cannot be a real
        # continuation either — matches real bash, which only treats a
        # backslash immediately before the newline as line continuation.
        if [[ "${_line}" =~ ${_continuation_re} ]]; then
            _bs_run="${BASH_REMATCH[0]}"
            (( ${#_bs_run} % 2 == 1 )) && _in_continuation=1
        fi
        ((_coverable++))
        [[ "${_mode}" == "lines" ]] && printf '%s\n' "${_lineno}"
    done < "${_file}"
    # An unterminated region means every line after it was skipped, which
    # inflates the percentage — the fail-green direction against a gate with one
    # point of headroom. Nothing else would report it: the count still looks
    # like a plausible number. Both remaining ways to reach this are documented
    # limits of the heuristic (a Python line starting with a double quote closes
    # a region early; a `#` inside a quoted string truncates the opener match),
    # so this converts a silent wrong answer into a loud refusal.
    #
    # `_in_continuation` is deliberately NOT part of this check. Unlike the
    # three regions above, a continuation can only ever swallow ONE further
    # physical line at a time, freshly re-evaluated on each; it never swallows
    # silently "to EOF". If the file's last line ends in a real continuation
    # backslash, there is simply no next line to splice onto it — nothing was
    # mis-attributed, so nothing needs to be reported.
    if [[ "${_in_embedded}" -eq 1 || "${_in_array}" -eq 1 || "${_in_heredoc}" -eq 1 ]]; then
        local _unterminated_kind
        if [[ "${_in_embedded}" -eq 1 ]]; then
            _unterminated_kind="python3 -c block"
        elif [[ "${_in_array}" -eq 1 ]]; then
            _unterminated_kind="array literal"
        else
            _unterminated_kind="heredoc"
        fi
        printf "ERROR: %s: unterminated %s — lines after it were not counted\n" \
            "${_file}" "${_unterminated_kind}" >&2
        return 1
    fi
    if [[ "${_mode}" == "count" ]]; then
        printf '%s\n' "${_coverable}"
    fi
    return 0
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
    _count_coverable_lines "${2}" || exit 1
    exit 0
fi

# Distinct traced line numbers for one file, extracted from a trace file —
# shared between the full-run loop and the --file-coverage debug entry point
# below, so both compute "what did the tracer actually emit" the same way.
# Uses end-of-line anchor to avoid matching :51 inside :516, etc.
_traced_lines_for_file() {
    local _src_file="${1}" _trace_file="${2}"
    grep -F "${_src_file}:" "${_trace_file}" 2>/dev/null \
        | grep -oE ':[0-9]+$' \
        | tr -d ':' \
        | sort -un
}

# One file's covered count, coverable count, and heuristic disagreements.
#
# `_count_coverable_lines` is a static heuristic — it can be wrong, and it
# has been: lib/detect_env.sh line 4, `detect_env() {`, used to be dropped
# from the coverable set by a function-declaration exclusion rule, but a real
# tracer run over the bats suite emitted that exact line twice. That specific
# rule is gone now (removed entirely rather than patched — see the
# "deliberately no function-declaration exclusion" comment near the top of
# this file), but the union below stays: a static
# heuristic over shell text can always be wrong about some other construct,
# and if the tracer emitted a line, that line IS coverable, by definition,
# regardless of what the static heuristic predicted.
#
# So the coverable denominator here is the UNION of the heuristic's static
# count and whatever the trace file actually contains for this file.
# `covered` is untouched — still exactly the count of distinct traced lines
# — which is what makes `covered <= coverable` hold by construction rather
# than by luck: every traced line is a member of the union, so it can never
# exceed it.
#
# This does make the denominator depend on what THIS run traced: a file whose
# covering tests are later deleted loses the union-added lines and its
# denominator can shrink back down. That is an acceptable, honest trade —
# coverage would have dropped anyway — and it does not excuse a bad
# heuristic: every union-added line is a disagreement (the heuristic excluded
# it, the trace didn't), and the caller prints every one of them, so a
# systematically wrong exclusion rule stays visible instead of being quietly
# absorbed into a higher denominator.
#
# Prints two lines (covered, coverable) followed by zero or more bare line
# numbers — the disagreements for this file, one per line. Returns 1,
# printing nothing, if the heuristic itself hit an unterminated region
# (propagated from _count_coverable_lines — same failure the caller already
# handles for the plain heuristic count).
_file_coverage_report() {
    local _src_file="${1}" _trace_file="${2}"
    local _coverable_lines _traced_lines _union_lines _disagreement_lines
    local _covered=0 _coverable=0

    _coverable_lines="$(_count_coverable_lines "${_src_file}" lines)" || return 1
    _traced_lines="$(_traced_lines_for_file "${_src_file}" "${_trace_file}")"

    if [[ -n "${_traced_lines}" ]]; then
        _covered=$(printf '%s\n' "${_traced_lines}" | wc -l | tr -d '[:space:]')
    fi

    _union_lines="$(printf '%s\n%s\n' "${_coverable_lines}" "${_traced_lines}" | grep -v '^$' | sort -un)"
    if [[ -n "${_union_lines}" ]]; then
        _coverable=$(printf '%s\n' "${_union_lines}" | wc -l | tr -d '[:space:]')
    fi

    # comm requires its two inputs sorted in the shell's collating order —
    # what plain `sort -u` produces — not numeric order (`sort -un`). For
    # multi-digit line numbers the two diverge (e.g. "9" sorts before "10"
    # numerically but after it lexicographically: '9' > '1'), and comm does
    # not error on the mismatch — it silently desyncs partway through and
    # emits spurious "unique to A" lines for values that are actually present
    # in both streams, just not where comm's merge walk expected them. Sort
    # lexicographically for comm's own requirement, then re-sort the true
    # result numerically so the printed disagreement list still reads in
    # line-number order.
    _disagreement_lines=""
    if [[ -n "${_traced_lines}" ]]; then
        _disagreement_lines="$(comm -23 \
            <(printf '%s\n' "${_traced_lines}" | grep -v '^$' | sort -u) \
            <(printf '%s\n' "${_coverable_lines}" | grep -v '^$' | sort -u) | sort -n)"
    fi

    printf '%s\n' "${_covered}"
    printf '%s\n' "${_coverable}"
    [[ -n "${_disagreement_lines}" ]] && printf '%s\n' "${_disagreement_lines}"
    return 0
}

# Debug/inspection entry point, same spirit as --count-coverable and
# --list-sources: lets the union-corrected coverable count and the
# disagreement list for ONE file be checked against a hand-built trace file,
# without running the multi-minute full suite under the tracer.
if [[ "${1:-}" == "--file-coverage" ]]; then
    if [[ -z "${2:-}" || -z "${3:-}" ]]; then
        printf "ERROR: --file-coverage requires a source file and a trace file\n" >&2
        exit 2
    fi
    if [[ ! -f "${2}" || ! -r "${2}" ]]; then
        printf "ERROR: --file-coverage: no such readable file: %s\n" "${2}" >&2
        exit 2
    fi
    if [[ ! -f "${3}" || ! -r "${3}" ]]; then
        printf "ERROR: --file-coverage: no such readable trace file: %s\n" "${3}" >&2
        exit 2
    fi
    _file_coverage_report "${2}" "${3}" || {
        printf "ERROR: cannot compute a trustworthy denominator for %s\n" "${2}" >&2
        exit 1
    }
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

# States what the run below actually measures, so an operator reading a
# percentage does not have to reverse-engineer the predicate from the source.
# Deliberately separate from the "Overall bash coverage: %d%%" line further
# down — CI's `.github/workflows/ci.yml` greps that exact line for every
# integer on it, so a denominator appended there would make the parsed
# percentage multi-line and break the `-lt` comparison.
printf "Instrumented set: setup_env.sh + tracked config/*.sh lib/*.sh scripts/*.sh + hooks, less bash-tracer.sh (%d files)\n" "${#INCLUDE_FILES[@]}"

# Compute per-file coverage
printf "%-30s  %8s  %8s  %8s\n" "File" "Covered" "Total" "Pct"
printf "%-30s  %8s  %8s  %8s\n" "----" "-------" "-----" "---"

total_covered=0
total_coverable=0
all_disagreements=()

for src_file in "${INCLUDE_FILES[@]}"; do
    [[ ! -f "${src_file}" ]] && continue

    if ! _report="$(_file_coverage_report "${src_file}" "${TRACE_FILE}")"; then
        printf "ERROR: cannot compute a trustworthy denominator for %s\n" "${src_file}" >&2
        exit 1
    fi

    covered=$(printf '%s\n' "${_report}" | sed -n '1p')
    coverable=$(printf '%s\n' "${_report}" | sed -n '2p')
    disagreement_lines=$(printf '%s\n' "${_report}" | sed -n '3,$p')

    # Invariant: covered can never legitimately exceed coverable — coverable
    # is now the UNION of the static heuristic count and whatever the trace
    # file actually contains for this file, so a traced line is always a
    # member of its own denominator by construction. This stays as a
    # structural guard rather than being removed: if it fires now, the union
    # computation itself has a bug, not an exclusion heuristic. See tdd.md's
    # Coverage Denominators section.
    if [[ "${covered}" -gt "${coverable}" ]]; then
        printf "ERROR: %s: covered (%d) exceeds coverable (%d) — an exclusion heuristic over-matched\n" \
            "${src_file}" "${covered}" "${coverable}" >&2
        exit 1
    fi

    if [[ "${coverable}" -gt 0 ]]; then
        pct=$(( covered * 100 / coverable ))
    else
        pct=100
    fi

    basename="${src_file##*/}"
    printf "%-30s  %8d  %8d  %7d%%\n" "${basename}" "${covered}" "${coverable}" "${pct}"

    total_covered=$((total_covered + covered))
    total_coverable=$((total_coverable + coverable))

    if [[ -n "${disagreement_lines}" ]]; then
        relpath="${src_file#"${REPO_ROOT}/"}"
        while IFS= read -r _dline; do
            [[ -n "${_dline}" ]] && all_disagreements+=("${relpath}:${_dline}")
        done <<< "${disagreement_lines}"
    fi
done

if [[ "${total_coverable}" -gt 0 ]]; then
    overall=$(( total_covered * 100 / total_coverable ))
else
    overall=0
fi

printf "\n%-30s  %8d  %8d  %7d%%\n" "TOTAL" "${total_covered}" "${total_coverable}" "${overall}"
printf "\nOverall bash coverage: %d%%\n" "${overall}"

# The union above means a wrongly-excluded line raises the denominator
# instead of silently vanishing from it — but a heuristic that is
# systematically wrong should still be fixed, not just neutralized forever.
# This is the list that makes that possible: every line an exclusion rule
# dropped that the trace actually emitted, so the specific rule can be
# tightened later. Printed unconditionally, with an explicit "none" and
# "total: 0" when clean, so the absence is visible rather than inferred.
printf "\nHeuristic disagreements (excluded but traced) — these indicate an over-matching rule:\n"
if [[ "${#all_disagreements[@]}" -eq 0 ]]; then
    printf "  none\n"
else
    for _d in "${all_disagreements[@]}"; do
        printf "  %s\n" "${_d}"
    done
fi
printf "  total: %d\n" "${#all_disagreements[@]}"

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
