#!/usr/bin/env bash
# Generic weekly delivery arm for a cadence check. Usage:
#
#     cadence-notify.sh <name> <detector-path>
#
# Detection lives elsewhere (ai-config) and is deliberately silent: a detector
# prints findings to stdout and exits 0/1/2. This script is the thin wrapper
# that turns that into an ntfy push and a heartbeat.
#
# THE DETECTOR IS RUN WITH NTFY_URL SCRUBBED, deliberately. ledger_drift_check.sh
# makes its own ntfy call, so left alone it would both duplicate this script's
# push and keep the failure mode below. Scrubbing demotes it to a pure detector
# without modifying a script this repo does not own.
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

_rhn_state_name() { printf '%s' "${_RHN_NAME:-cadence}"; }

# Heartbeat is written on EVERY outcome including failure. A run that errored
# and a run that never happened must not look alike -- that distinction is the
# whole reason doctor reads this file rather than trusting the LaunchAgent.
_rhn_write_heartbeat() {
    local _result="$1" _rc="$2" _count="$3"
    local _dir; _dir="$(_rhn_state_dir)/$(_rhn_state_name)"
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
# Resolve the channel. `config/local.sh` is this repo's established home for
# machine-local secrets -- git-ignored and untracked (verified two ways), where
# the plist's EnvironmentVariables is world-readable (`-rw-r--r--`) and would be
# re-emitted by the installer on every setup_user.
#
# Sourced ONLY when NTFY_URL is absent, so an explicit environment still wins and
# tests never inherit the real machine's channel.
_rhn_load_channel() {
    [[ -n "${NTFY_URL:-}" ]] && return 0
    local _cfg="${_RHN_LOCAL_CFG:-$(dirname "${BASH_SOURCE[0]}")/../config/local.sh}"
    # shellcheck disable=SC1090 # path is resolved at runtime; see shell.md SC1091 note
    [[ -r "${_cfg}" ]] && . "${_cfg}" >/dev/null 2>&1
    return 0
}

# ntfy routes by TOPIC PATH. Measured against the live endpoint: a POST to the
# bare host returns 400, host/topic returns 403 anonymously and 200 with
# credentials. NTFY_URL holds the host and NTFY_TOPIC the topic, so a consumer
# that POSTs bare ${NTFY_URL} -- as all three in this fleet did -- cannot deliver.
_rhn_ntfy_target() {
    local _u="${NTFY_URL%/}"
    # An NTFY_URL that already carries a path is taken verbatim; only a bare
    # host gets the topic appended, so setting the full URL still works.
    [[ "${_u}" =~ ^https?://[^/]+$ ]] && [[ -n "${NTFY_TOPIC:-}" ]] && _u="${_u}/${NTFY_TOPIC}"
    printf '%s' "${_u}"
}

_rhn_notify() {
    local _msg="$1"
    _rhn_load_channel
    if [[ -z "${NTFY_URL:-}" ]]; then
        printf "renovate-held: NTFY_URL not set, no channel to deliver on\n" >&2
        return 0
    fi
    # The endpoint requires auth -- anonymous POST measured at 403 -- so absent
    # credentials are a DIFFERENT fault from an absent channel and must not
    # render as the same message. Reporting them alike is how a 403 every week
    # would read as "no channel configured" and never get chased.
    if [[ -z "${NTFY_USER:-}" || -z "${NTFY_PASSWORD:-}" ]]; then
        printf "renovate-held: NTFY_USER/NTFY_PASSWORD unset — credential missing, cannot authenticate\n" >&2
        return 0
    fi
    local _curl="${_RHN_CURL_BIN:-curl}" _target
    _target="$(_rhn_ntfy_target)"
    # --data-raw, never -d: curl's -d OPENS A FILE when the argument begins with
    # `@`, so `-d "${var}"` on any unvalidated string is a latent arbitrary
    # local-file-read that POSTs the contents. curl --help documents --data-raw
    # as "'@' allowed".
    #
    # Credentials go in on STDIN via `-K -`, never `-u`: curl's argv is readable
    # by any `ps` on the box, so `-u user:pass` publishes the password to every
    # local process for the life of the call.
    #
    # curl's -K value is quote-delimited, so a `"` in the credential TERMINATES
    # it early and the rest is dropped. Measured against curl's own parser via
    # --libcurl: `user = "has"quote:pw"` emits USERPWD "has:" -- a truncated
    # username and no password at all. That surfaces as a 403, which this code
    # reports as "delivery failed", i.e. identical to the server being down.
    # Latent today because the current password contains no quote; one rotation
    # away otherwise. Escape backslash first, then quote.
    local _cred
    _cred="$(printf '%s:%s' "${NTFY_USER}" "${NTFY_PASSWORD}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'user = "%s"\n' "${_cred}" \
      | "${_curl}" -fsS -K - --data-raw "${_msg}" "${_target}" >/dev/null 2>&1 \
        || printf "renovate-held: ntfy delivery failed\n" >&2
    return 0
}

run_cadence_notify() {
    local _name="${1:?cadence-notify: name required}"
    # _name is interpolated into a filesystem path and (via the installer) into
    # a sed replacement and plist XML. Constrain it at the boundary rather than
    # escaping at each use: a `|` would terminate the installer's `s|..|..|`
    # expression, `/` or `..` would escape the state directory, and `&` would
    # produce malformed XML.
    if [[ ! "${_name}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        printf "cadence-notify: refusing name %q -- must match ^[a-z0-9][a-z0-9-]*$\n" "${_name}" >&2
        return 2
    fi
    local _detector="${2:?cadence-notify: detector path required}"
    local _out _rc _count _result _msg
    _RHN_NAME="${_name}"

    if [[ ! -x "${_detector}" ]]; then
        printf "renovate-held: detector not executable at %s\n" "${_detector}" >&2
        _rhn_write_heartbeat "incomplete" 2 0 || return 1
        _rhn_notify "${_name} INCOMPLETE - cannot determine: detector missing"
        return 2
    fi

    # NTFY_URL scrubbed: the detector detects, this script delivers.
    _out="$(env -u NTFY_URL "${_detector}" 2>/dev/null)"
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
        _msg="${_name} INCOMPLETE - cannot determine."
        [[ "${_count}" -gt 0 ]] && _msg="${_msg}"$'\n'"Found so far:"$'\n'"${_out}"
    else
        _msg="${_name}: ${_count} finding(s)."$'\n'"${_out}"
    fi

    _rhn_notify "${_msg}"
    return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
run_cadence_notify "$@"
