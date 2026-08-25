#!/usr/bin/env bash
# Weekly delivery arm for the Renovate held-major cadence.
#
# Detection lives in ai-config (.claude/scripts/renovate_held_check.py) and is
# deliberately silent: it prints findings and exits 0/1/2. This script is the
# thin wrapper that turns that into an ntfy push and a heartbeat.
#
# The split matters. ledger_drift_check.sh makes its own ntfy call, so an unset
# NTFY_URL degrades detection AND delivery together and still returns 0 --
# "no drift" and "no channel" render identically. Here a missing channel is
# reported on stderr and never touches the exit code.
#
# Detector contract:
#   0 = all repos queried, control passed, nothing held
#   1 = all repos queried, control passed, findings on stdout
#   2 = INCOMPLETE: a query or the control failed (dominates 1)
# Any other value is treated as 2 -- an unknown outcome is not a clean one.

_rhn_state_dir() {
    printf '%s' "${_RHN_STATE_DIR:-${HOME}/.local/share/dotfiles/renovate-held}"
}

_rhn_detector() {
    printf '%s' "${_RHN_DETECTOR:-${HOME}/git-repos/personal/ai-config/.claude/scripts/renovate_held_check.py}"
}

# Heartbeat is written on EVERY outcome including failure. A run that errored
# and a run that never happened must not look alike -- that distinction is the
# whole reason doctor reads this file rather than trusting the LaunchAgent.
_rhn_write_heartbeat() {
    local _result="$1" _rc="$2" _count="$3"
    local _dir; _dir="$(_rhn_state_dir)"
    mkdir -p "${_dir}" || return 1
    printf '{"ts": "%s", "result": "%s", "exit_code": %s, "findings": %s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_result}" "${_rc}" "${_count}" \
        > "${_dir}/last-run.json" || return 1
}

# Deliberately void: delivery is best-effort and its outcome must never reach the
# caller's exit code, because a missing or broken channel is not a finding about
# the fleet. Do NOT add `|| return 1` at the call site -- that is the
# ledger_drift_check.sh failure, where detection and delivery fail together and
# "no drift" becomes indistinguishable from "no channel". Both failure branches
# are pinned by tests; the return value is not read and carries no information.
_rhn_notify() {
    local _msg="$1"
    if [[ -z "${NTFY_URL:-}" ]]; then
        printf "renovate-held: NTFY_URL not set, no channel to deliver on\n" >&2
        return 0
    fi
    local _curl="${_RHN_CURL_BIN:-curl}"
    "${_curl}" -fsS -d "${_msg}" "${NTFY_URL}" >/dev/null 2>&1 \
        || printf "renovate-held: ntfy delivery failed\n" >&2
    return 0
}

run_renovate_held_notify() {
    local _detector _out _rc _count _result _msg
    _detector="$(_rhn_detector)"

    if [[ ! -x "${_detector}" ]]; then
        printf "renovate-held: detector not executable at %s\n" "${_detector}" >&2
        _rhn_write_heartbeat "incomplete" 2 0 || return 1
        _rhn_notify "Renovate cadence INCOMPLETE - cannot determine held majors: detector missing"
        return 2
    fi

    _out="$("${_detector}" 2>/dev/null)"
    _rc=$?

    _count=0
    [[ -n "${_out}" ]] && _count=$(printf '%s\n' "${_out}" | command grep -c .)

    case "${_rc}" in
        0) _result="clean" ;;
        1) _result="held" ;;
        *) _result="incomplete"; _rc=2 ;;
    esac

    _rhn_write_heartbeat "${_result}" "${_rc}" "${_count}" || return 1

    if [[ "${_result}" == "clean" ]]; then
        return 0
    fi

    if [[ "${_result}" == "incomplete" ]]; then
        _msg="Renovate cadence INCOMPLETE - cannot determine held majors."
        [[ "${_count}" -gt 0 ]] && _msg="${_msg}"$'\n'"Found so far:"$'\n'"${_out}"
    else
        _msg="Renovate: ${_count} major update(s) held for triage."$'\n'"${_out}"
    fi

    _rhn_notify "${_msg}"
    return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
run_renovate_held_notify "$@"
