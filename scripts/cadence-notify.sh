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
#
# STDOUT IS FINDINGS-ONLY. One finding per line, nothing else -- no progress
# lines, no "alerting via ntfy" banners, no diagnosis. This wrapper counts
# stdout lines and cannot tell a banner from a finding, so a status line on
# stdout is reported to the operator as a finding. Measured 2026-08-28 against
# ledger_drift_check.sh, which printed a banner on BOTH terminal paths:
#
#   findings path   31 stale entities -> heartbeat recorded 32
#   clean path      0 findings        -> heartbeat recorded 1, every week
#
# The clean-path instance is the damaging one -- it fires when nothing is
# wrong, so the channel reports a finding on a healthy fleet forever. It was
# invisible from this side: the only heartbeat available here came from a run
# that HAD drift, so the findings path was the one that could be measured and
# the clean path had to be found by running the detector. A count sampled on
# one path says nothing about the others. Fixed in ai-config#227; both banners
# now go to stderr, leaving stdout at 9/0/0 across findings/clean/cannot-run.
#
# That is the detector violating this contract, not the wrapper miscounting.
# Every diagnosis goes to STDERR, which is surfaced in the notification and
# never counted.
#
# STDERR IS PUBLISHED. It is POSTed to the ntfy endpoint, capped at the last 20
# lines. A detector must not print credentials, tokens, or full environment
# dumps there -- it was discarded before 2026-08-28, so anything written on the
# assumption that nobody reads it is now delivered.

_rhn_state_dir() {
    printf '%s' "${_RHN_STATE_DIR:-${HOME}/.local/share/dotfiles/cadence}"
}

_rhn_state_name() { printf '%s' "${_RHN_NAME:-cadence}"; }

# The staleness bound is a property of the CADENCE, so the writer emits it and
# any reader uses what was actually written rather than its own copy. A reader
# holding 8 against a writer that has moved to 3 misses four days of staleness
# and reports clean -- silent, permissive, and indistinguishable from health.
# One weekly period plus slack.
_rhn_max_age_days() { printf '%s' "${_RHN_MAX_AGE_DAYS:-8}"; }

# Heartbeat is written on EVERY outcome including failure. A run that errored
# and a run that never happened must not look alike -- that distinction is the
# whole reason doctor reads this file rather than trusting the LaunchAgent.
_rhn_write_heartbeat() {
    local _result="$1" _rc="$2" _count="$3"
    local _dir; _dir="$(_rhn_state_dir)/$(_rhn_state_name)"
    mkdir -p "${_dir}" || return 1
    printf '{"ts": "%s", "result": "%s", "exit_code": %s, "findings": %s, "max_age_days": %s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_result}" "${_rc}" "${_count}" "$(_rhn_max_age_days)" \
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
    #
    # A NEWLINE cannot be escaped -- curl's config format is line-oriented, so a
    # quoted value simply cannot contain one, and everything after it is parsed
    # as FURTHER DIRECTIVES. Measured against curl 8.7.1: a password of
    # $'p\noutput = /tmp/x' made curl obey the smuggled `output` and write the
    # response body to that path; `user-agent`, `url` and `upload-file` are
    # reachable the same way. So this refuses rather than escapes -- and refusing
    # is not a degradation, because the alternative is executing an attacker's
    # curl options. Credentials come from a trusted local.sh today, so this is
    # defence in depth, not a live exploit.
    case "${NTFY_USER}${NTFY_PASSWORD}" in
        *$'\n'* | *$'\r'*)
            printf "renovate-held: credential contains a newline — refusing to build a curl config\n" >&2
            return 0
            ;;
    esac
    # Parameter expansion rather than a sed pipeline: no second process, so the
    # credential never crosses a process boundary at all. Backslash first.
    local _cred="${NTFY_USER}:${NTFY_PASSWORD}"
    _cred="${_cred//\\/\\\\}"
    _cred="${_cred//\"/\\\"}"
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
    local _out _err _rc _count _result _msg
    _RHN_NAME="${_name}"

    if [[ ! -x "${_detector}" ]]; then
        printf "renovate-held: detector not executable at %s\n" "${_detector}" >&2
        _rhn_write_heartbeat "incomplete" 2 0 || return 1
        _rhn_notify "${_name} INCOMPLETE - cannot determine: detector missing"
        return 2
    fi

    # NTFY_URL scrubbed: the detector detects, this script delivers.
    #
    # The two streams are kept SEPARATE and neither is discarded. stdout is the
    # findings channel and is what `_count` measures; stderr is the diagnosis
    # channel -- why a run could not determine an answer -- and is surfaced in
    # the message but never counted. Folding them together would inflate the
    # count by however many lines the diagnosis ran to; discarding stderr, which
    # this did until 2026-08-28, left the operator a push naming no cause at all
    # (measured: `ERROR: ledger binary not found` vanished, the notification
    # said only "cannot determine").
    #
    # A mktemp failure takes the INCOMPLETE path rather than returning early:
    # this file's invariant is that a run that errored and a run that never
    # happened must not look alike, and a bare `return 1` here would write no
    # heartbeat at all -- indistinguishable from an agent that never fired,
    # which is the one distinction doctor reads this file to make.
    #
    # Seamed rather than called by name because BSD `mktemp` with no template
    # ignores TMPDIR, so pointing TMPDIR at a nonexistent directory drives this
    # branch on GNU and not on macOS -- a test that passes on the runner and is
    # inert on every development machine. The override makes the branch
    # reachable identically on both.
    local _errfile _mktemp="${_RHN_MKTEMP:-mktemp}"
    if ! _errfile="$("${_mktemp}")"; then
        printf "cadence-notify: cannot create a temp file for the detector's stderr\n" >&2
        _rhn_write_heartbeat "incomplete" 2 0 || return 1
        _rhn_notify "${_name} INCOMPLETE - cannot determine: no temp file for detector stderr"
        return 2
    fi
    _out="$(env -u NTFY_URL "${_detector}" 2>"${_errfile}")"
    _rc=$?
    #
    # Capped, and the cap is a security property rather than tidiness: this
    # stream is POSTed to the ntfy endpoint, so it leaves the machine. stderr
    # is where tooling prints stack traces, environment dumps and failing URLs
    # -- the places credentials appear -- and it was discarded until now, so a
    # detector author had no reason to treat it as published. 20 lines bounds
    # an accidental dump; it does not make the stream safe, which is why the
    # contract in the header says so outright.
    _err="$(command tail -n 20 "${_errfile}" 2>/dev/null)"
    rm -f "${_errfile}"

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
        [[ -n "${_err}" ]] && _msg="${_msg}"$'\n'"Cause:"$'\n'"${_err}"
        [[ "${_count}" -gt 0 ]] && _msg="${_msg}"$'\n'"Found so far:"$'\n'"${_out}"
    else
        _msg="${_name}: ${_count} finding(s)."$'\n'"${_out}"
        # A detector can find things AND warn while doing it -- "9 repos held,
        # 2 unreachable" is one run with both. Appending under its own label
        # keeps the diagnosis out of the finding list rather than losing it.
        [[ -n "${_err}" ]] && _msg="${_msg}"$'\n'"Diagnostics:"$'\n'"${_err}"
    fi

    _rhn_notify "${_msg}"
    return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
run_cadence_notify "$@"
