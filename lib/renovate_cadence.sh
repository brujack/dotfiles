#!/usr/bin/env bash
# Heartbeat arm for the Renovate held-major cadence (see docs/adr/0024).
#
# The LaunchAgent is silent when the fleet is clean, deliberately -- a weekly
# "still alive" push trains the operator to ignore the channel and destroys the
# signal arm. That silence is also indistinguishable from the agent being
# unloaded, so liveness travels on a second channel: the wrapper writes a
# heartbeat on every outcome and doctor reads it here.
#
# ai-config's ledger-drift.yml is the counter-example. It defers real alerting
# to "an enrolled machine", no machine runs it, and nothing reports that -- the
# deferral reads as reassurance and stops anyone looking.

readonly _RENOVATE_CADENCE_MAX_AGE_DAYS=8   # one weekly period plus slack

_renovate_cadence_state_dir() {
    printf '%s' "${_RHN_STATE_DIR:-${HOME}/.local/share/dotfiles/renovate-held}"
}

# Read one string field out of the heartbeat. Deliberately not `jq` -- doctor
# must not gain a dependency that its own FAIL path would then blame.
_renovate_cadence_field() {
    local _file="$1" _key="$2"
    sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${_file}" | head -1
}

_doctor_check_renovate_cadence() {
    # Studio-only, matching install_renovate_held_agent: on any other machine
    # there is no agent by design, so an absent heartbeat is correct rather than
    # a fault. Silent, not PASS -- a PASS would assert a thing that was never
    # installed.
    _rhn_is_cadence_host || return 0

    printf "\nRenovate cadence:\n"

    local _dir _file _ts _epoch _now _age _result
    _dir="$(_renovate_cadence_state_dir)"
    _file="${_dir}/last-run.json"

    if [[ ! -f "${_file}" ]]; then
        doctor_fail "renovate cadence" \
            "never run (no heartbeat) — run: setup_env.sh -t setup_user"
        return 1
    fi

    _ts="$(_renovate_cadence_field "${_file}" ts)"
    _result="$(_renovate_cadence_field "${_file}" result)"

    # Unparsable is unknown, not healthy. Fail closed.
    if [[ -z "${_ts}" || -z "${_result}" ]]; then
        doctor_fail "renovate cadence" "heartbeat is unparsable: ${_file}"
        return 1
    fi

    _epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${_ts}" +%s 2>/dev/null \
             || date -u -d "${_ts}" +%s 2>/dev/null)
    if [[ -z "${_epoch}" ]]; then
        doctor_fail "renovate cadence" "heartbeat timestamp is unparsable: ${_ts}"
        return 1
    fi

    _now=$(date -u +%s)
    _age=$(( (_now - _epoch) / 86400 ))

    if [[ "${_age}" -gt "${_RENOVATE_CADENCE_MAX_AGE_DAYS}" ]]; then
        doctor_fail "renovate cadence" \
            "last run ${_age}d ago (max ${_RENOVATE_CADENCE_MAX_AGE_DAYS}d) — agent not firing"
        return 1
    fi

    # A fresh run that could not answer is not a pass. "nothing held" and
    # "could not tell" are the pair this design exists to keep apart, and a
    # green doctor would collapse them again.
    if [[ "${_result}" == "incomplete" ]]; then
        doctor_fail "renovate cadence" \
            "last run ${_age}d ago was incomplete — could not determine held majors"
        return 1
    fi

    doctor_pass "renovate cadence: last run ${_age}d ago (${_result})"
    return 0
}

# --- LaunchAgent install -------------------------------------------------
#
# Studio-only, and that is not arbitrary. The check is FLEET-wide -- it queries
# all nine repos -- so a second machine running it produces duplicate pushes for
# the same held PR, which is the fastest way to train the operator to mute the
# channel. One runner is correct; the Studio is the tmux host and is always up.

readonly _RHN_AGENT_LABEL="com.brucejackson.renovate-held"

_rhn_agent_dir() {
    printf '%s' "${_RHN_AGENT_DIR:-${HOME}/Library/LaunchAgents}"
}

_rhn_launchctl() {
    printf '%s' "${_RHN_LAUNCHCTL:-launchctl}"
}

_rhn_dotfiles_root() {
    printf '%s' "${_OVERRIDE_DOTFILES_ROOT:-${PERSONAL_GITREPOS:-${HOME}/git-repos/personal}/dotfiles}"
}

# Identity by capability where possible, but this genuinely IS a single-host
# question -- "which one machine runs the fleet-wide check" has no HAS_* form.
_rhn_is_cadence_host() {
    local _h="${HOSTNAME_SHORT:-$(hostname -s 2>/dev/null)}"
    [[ "${_h}" == "studio" || "${_h}" == "studio-1" ]]
}

install_renovate_held_agent() {
    _rhn_is_cadence_host || return 0

    local _root _src _dst _dir _lctl
    _root="$(_rhn_dotfiles_root)"
    _src="${_root}/LaunchAgents/${_RHN_AGENT_LABEL}.plist"
    _dir="$(_rhn_agent_dir)"
    _dst="${_dir}/${_RHN_AGENT_LABEL}.plist"
    _lctl="$(_rhn_launchctl)"

    if [[ ! -f "${_src}" ]]; then
        printf "renovate cadence: plist template missing at %s\n" "${_src}" >&2
        return 1
    fi

    # The wrapper must exist before the agent that calls it. An agent firing at
    # a missing script logs a failure nobody reads -- the silent-inert shape
    # this whole design is built against.
    if [[ ! -x "${_root}/scripts/renovate-held-notify.sh" ]]; then
        printf "renovate cadence: notify script missing or not executable\n" >&2
        return 1
    fi

    mkdir -p "${_dir}" "${HOME}/.local/share/dotfiles/renovate-held" || return 1

    # Unload BEFORE overwriting: launchd holds the loaded job by label, and
    # loading over a live one is a no-op that silently keeps the old path.
    "${_lctl}" unload "${_dst}" >/dev/null 2>&1

    sed -e "s|__DOTFILES__|${_root}|g" -e "s|__HOME__|${HOME}|g" \
        "${_src}" > "${_dst}" || return 1

    "${_lctl}" load "${_dst}" >/dev/null 2>&1
    return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
