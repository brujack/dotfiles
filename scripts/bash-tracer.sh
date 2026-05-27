#!/usr/bin/env bash
# BASH_ENV coverage tracer — injected into every bash subprocess by run-bash-coverage.sh
# Opens fd 9 to append to trace file and enables xtrace with file:line markers.

_cov_file="${_COV_TRACE_FILE:-}"
[[ -z "${_cov_file}" ]] && return 0
eval "exec 9>>'${_cov_file}'" 2>/dev/null || return 0
export BASH_XTRACEFD=9
export PS4='COVTRACE:${BASH_SOURCE}:${LINENO}: '
set -x
