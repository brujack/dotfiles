#!/usr/bin/env bash
# BASH_ENV coverage tracer — injected into every bash subprocess by run-bash-coverage.sh
# Opens fd 9 to append to trace file and enables xtrace with file:line markers.

_cov_file="${_COV_TRACE_FILE:-}"
[[ -z "${_cov_file}" ]] && return 0
# The `2>/dev/null` is scoped to a group rather than written on the `exec`.
# `exec` with redirections and NO command applies EVERY redirection to the
# current shell permanently, so `exec 9>>f 2>/dev/null` silenced the traced
# shell's stderr for the rest of its life — not just this line. Every bash
# subprocess the tracer touched ran with fd 2 pointed at /dev/null. Verified:
#   printf 'exec 9>>/tmp/f 2>/dev/null\necho oops >&2\n' > /tmp/t.sh
#   bash /tmp/t.sh 2>&1 1>/dev/null      # -> nothing: "oops" is gone
# The group form silences only the exec's own failure message and leaves fd 2
# alone; fd 9 still persists, because the `exec` is what opens it.
# Found when ai-config ported this file: a bats test asserting on stderr
# passed standalone and failed under the tracer.
if ! { exec 9>>"${_cov_file}"; } 2>/dev/null; then return 0; fi
export BASH_XTRACEFD=9
export PS4='COVTRACE:${BASH_SOURCE}:${LINENO}: '
set -x
