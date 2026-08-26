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

# FALLBACK ONLY. The heartbeat carries the bound its writer actually used; this
# stands in for heartbeats written before that field existed. A default silently
# substituting for a missing value is the collapse
# [[ai-config-count-failure-modes-not-channels]] describes, so the reader reports
# WHICH source it used rather than just the number.
readonly _RENOVATE_CADENCE_MAX_AGE_DAYS=8   # one weekly period plus slack

_renovate_cadence_state_dir() {
    printf '%s' "${_RHN_STATE_DIR:-${HOME}/.local/share/dotfiles/cadence}"
}

# Read one string field out of the heartbeat. Deliberately not `jq` -- doctor
# must not gain a dependency that its own FAIL path would then blame.
# Reads both quoted and unquoted values. `max_age_days` is numeric and therefore
# UNQUOTED, so a quoted-only pattern returns empty for it and the caller silently
# falls back to its default -- defeating the written bound while looking correct.
_renovate_cadence_field() {
    local _file="$1" _key="$2" _v
    _v="$(sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${_file}" | head -1)"
    [[ -n "${_v}" ]] && { printf '%s' "${_v}"; return 0; }
    sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "${_file}" | head -1
}

_doctor_check_cadence() {
    local _cname="${1:?_doctor_check_cadence: name required}"
    # Studio-only, matching install_renovate_held_agent: on any other machine
    # there is no agent by design, so an absent heartbeat is correct rather than
    # a fault. Silent, not PASS -- a PASS would assert a thing that was never
    # installed.
    _rhn_is_cadence_host || return 0

    printf "\nCadence (%s):\n" "${_cname}"

    local _dir _file _ts _epoch _now _age _result
    _dir="$(_renovate_cadence_state_dir)"
    _file="${_dir}/${_cname}/last-run.json"

    if [[ ! -f "${_file}" ]]; then
        doctor_fail "${_cname} cadence" \
            "never run (no heartbeat) — run: setup_env.sh -t setup_user"
        return 1
    fi

    _ts="$(_renovate_cadence_field "${_file}" ts)"
    _result="$(_renovate_cadence_field "${_file}" result)"

    # Unparsable is unknown, not healthy. Fail closed.
    # These two failures MUST stay lexically distinct ("unparsable" vs "not a
    # valid date"). A test asserting a word both branches emit cannot tell them
    # apart and passes when the guard it names is deleted -- measured twice on
    # this very check, the second time on a fix that chose the shared word.
    if [[ -z "${_ts}" || -z "${_result}" ]]; then
        doctor_fail "${_cname} cadence" "heartbeat is unparsable: ${_file}"
        return 1
    fi

    _epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${_ts}" +%s 2>/dev/null \
             || date -u -d "${_ts}" +%s 2>/dev/null)
    if [[ -z "${_epoch}" ]]; then
        doctor_fail "${_cname} cadence" "heartbeat timestamp is not a valid date: ${_ts}"
        return 1
    fi

    local _bound _bound_src
    _bound="$(_renovate_cadence_field "${_file}" max_age_days)"
    if [[ "${_bound}" =~ ^[0-9]+$ ]]; then
        _bound_src="from heartbeat"
    else
        _bound="${_RENOVATE_CADENCE_MAX_AGE_DAYS}"
        _bound_src="default — heartbeat carries none"
    fi

    _now=$(date -u +%s)
    _age=$(( (_now - _epoch) / 86400 ))

    # A future-dated heartbeat yields a NEGATIVE age, and `-N -gt 8` is false
    # for every negative N -- so the staleness guard below could never fire
    # again. That is an unknown reading as clean, in the one check whose whole
    # purpose is detecting an agent that stopped. Trigger: the clock jumps
    # forward (NTP correction after a long sleep, a VM resume), the agent
    # writes a heartbeat at the skewed time, the clock corrects back. If the
    # agent then stops -- exactly the case this check exists for -- doctor
    # reports PASS forever. Fail closed.
    if [[ "${_age}" -lt 0 ]]; then
        doctor_fail "${_cname} cadence" \
            "heartbeat is dated ${_age}d in the future (clock skew?) — cannot judge staleness"
        return 1
    fi

    if [[ "${_age}" -gt "${_bound}" ]]; then
        doctor_fail "${_cname} cadence" \
            "last run ${_age}d ago (max ${_bound}d, ${_bound_src}) — agent not firing"
        return 1
    fi

    # A fresh run that could not answer is not a pass. "nothing held" and
    # "could not tell" are the pair this design exists to keep apart, and a
    # green doctor would collapse them again.
    if [[ "${_result}" == "incomplete" ]]; then
        doctor_fail "${_cname} cadence" \
            "last run ${_age}d ago was incomplete — could not determine held majors"
        return 1
    fi

    if [[ "${_result}" == "pending" ]]; then
        doctor_pass "${_cname} cadence: installed ${_age}d ago, first run not yet due"
        return 0
    fi

    doctor_pass "${_cname} cadence: last run ${_age}d ago (${_result})"
    return 0
}

# --- LaunchAgent install -------------------------------------------------
#
# Studio-only, and that is not arbitrary. The check is FLEET-wide -- it queries
# all nine repos -- so a second machine running it produces duplicate pushes for
# the same held PR, which is the fastest way to train the operator to mute the
# channel. One runner is correct; the Studio is the tmux host and is always up.

# Two agents share one installer and one plist template. Two call sites is the
# threshold that justifies the abstraction; a single one would be the
# premature-helper anti-pattern maintainability.md names.

_rhn_agent_dir()      { printf '%s' "${_RHN_AGENT_DIR:-${HOME}/Library/LaunchAgents}"; }
_rhn_launchctl()      { printf '%s' "${_RHN_LAUNCHCTL:-launchctl}"; }
_rhn_dotfiles_root()  { printf '%s' "${_OVERRIDE_DOTFILES_ROOT:-${PERSONAL_GITREPOS:-${HOME}/git-repos/personal}/dotfiles}"; }
_rhn_ai_config_root() { printf '%s' "${_OVERRIDE_AI_CONFIG_ROOT:-${PERSONAL_GITREPOS:-${HOME}/git-repos/personal}/ai-config}"; }

# Identity by capability where possible, but "which ONE machine runs the
# fleet-wide check" genuinely has no HAS_* form: a second machine running it
# duplicates every push, which is the fastest way to train the operator to mute
# the channel.
_rhn_is_cadence_host() {
    local _h="${HOSTNAME_SHORT:-$(hostname -s 2>/dev/null)}"
    [[ "${_h}" == "studio" || "${_h}" == "studio-1" ]]
}

# _la_install_agent <name> <detector-path> <minute>
_la_install_agent() {
    local _name="$1" _detector="$2" _minute="$3"

    # Same boundary check as cadence-notify.sh, for the same reason one layer
    # up: _name and _minute are substituted into a sed s|..|..| expression and
    # into plist XML. A `|` in either terminates the sed command.
    [[ "${_name}"   =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
        printf "cadence: refusing agent name %q\n" "${_name}" >&2; return 1; }
    [[ "${_minute}" =~ ^[0-9]{1,2}$ ]] || {
        printf "cadence: refusing minute %q\n" "${_minute}" >&2; return 1; }
    local _root _src _dst _dir _lctl _label
    _root="$(_rhn_dotfiles_root)"
    _src="${_root}/LaunchAgents/cadence.plist.template"
    _dir="$(_rhn_agent_dir)"
    _label="com.brucejackson.${_name}"
    _dst="${_dir}/${_label}.plist"
    _lctl="$(_rhn_launchctl)"

    [[ -f "${_src}" ]] || {
        printf "cadence: plist template missing at %s\n" "${_src}" >&2; return 1; }

    # The wrapper must exist before the agent that calls it. An agent firing at
    # a missing script logs a failure nobody reads -- the silent-inert shape
    # this whole design is built against.
    [[ -x "${_root}/scripts/cadence-notify.sh" ]] || {
        printf "cadence: notify script missing or not executable\n" >&2; return 1; }

    # The DETECTOR may legitimately not exist yet (ai-config owns it and may not
    # have landed). That is not an install failure -- the wrapper reports it as
    # `incomplete` and doctor surfaces it, which is strictly better than
    # refusing to install and leaving nothing to report at all.
    [[ -e "${_detector}" ]] || \
        printf "cadence: %s detector absent at %s (agent installs; runs will report incomplete)\n" \
            "${_name}" "${_detector}" >&2

    mkdir -p "${_dir}" "${HOME}/.local/share/dotfiles/cadence/${_name}" || return 1

    # Unload BEFORE overwriting: launchd holds the job by label, and loading
    # over a live one is a no-op that silently keeps the old path.
    "${_lctl}" unload "${_dst}" >/dev/null 2>&1

    # Bash parameter expansion, NOT sed. In a sed replacement `&` means "the
    # entire matched text", so a path containing `&` produces
    #   s|__DOTFILES__|/x/a&b|  ->  /x/a__DOTFILES__b
    # -- a plist that still passes `plutil -lint` (it is valid XML) while
    # pointing at a path that does not exist, so the agent fails silently every
    # week. Measured with a real `&` in the root path: 4 placeholders survived.
    # NOTE the QUOTES around each replacement -- they are the fix, not style.
    # bash >= 5.2 gave ${var//pat/rep} the SAME sed-like `&` semantics, so the
    # unquoted form is corrupt in exactly the way sed was. Measured on 5.3.15
    # and on the workstation (CI's lineage): unquoted -> Xa__P__bY,
    # quoted -> Xa&bY. bash 3.2 lacks the behaviour entirely, so a mac using
    # /usr/bin/bash could never reproduce it -- tdd.md pitfall G.
    local _plist
    _plist="$(<"${_src}")" || return 1
    _plist="${_plist//__DOTFILES__/"${_root}"}"
    _plist="${_plist//__HOME__/"${HOME}"}"
    _plist="${_plist//__NAME__/"${_name}"}"
    _plist="${_plist//__DETECTOR__/"${_detector}"}"
    _plist="${_plist//__MINUTE__/"${_minute}"}"
    printf '%s\n' "${_plist}" > "${_dst}" || return 1

    # A surviving placeholder means substitution silently failed. Never install
    # an agent that points somewhere unresolved.
    # `__[A-Z]*__` misses any placeholder carrying an internal underscore or a
    # digit -- __STATE_DIR__, __VER2__ -- which would then install undetected.
    # Today's five all happen to match, so the narrow form works and cannot be
    # falsified by the current template; that is exactly the shape shell.md
    # records for `[A-Z_]+` vs `[A-Z][A-Z0-9_]+`. Found by a test that used a
    # placeholder the guard could not see.
    if command grep -qE '__[A-Z][A-Z0-9_]*__' "${_dst}"; then
        printf "cadence: placeholder survived substitution in %s\n" "${_dst}" >&2
        rm -f "${_dst}"
        return 1
    fi

    "${_lctl}" load "${_dst}" >/dev/null 2>&1

    # Seed a heartbeat at install time. Without it an agent installed today
    # reads as "never run" until its first fire -- up to a week of a hard fault
    # for something behaving exactly as installed. That is tolerable for a check
    # the operator types deliberately and NOT for one that runs at every session
    # start, which is what the reader is becoming.
    #
    # `pending` is a state, not a grace period: it carries the install time, so
    # the ordinary staleness rule retires it. If the agent fires, the run
    # overwrites it; if it never fires, it goes stale on schedule and reports.
    # An ABSENT heartbeat now means genuinely not installed, which is a real
    # fault rather than an ambiguous one.
    local _hb
    _hb="$(_renovate_cadence_state_dir)/${_name}"
    if [[ ! -f "${_hb}/last-run.json" ]]; then
        mkdir -p "${_hb}" 2>/dev/null &&
        printf '{"ts": "%s", "result": "pending", "exit_code": 0, "findings": 0, "max_age_days": %s}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_RENOVATE_CADENCE_MAX_AGE_DAYS}" \
            > "${_hb}/last-run.json" 2>/dev/null
    fi
    return 0
}

install_renovate_held_agent() {
    _rhn_is_cadence_host || return 0
    _la_install_agent "renovate-held" \
        "$(_rhn_ai_config_root)/.claude/scripts/renovate_held_check.py" 7
}

# Makes ledger-drift.yml's deferral TRUE. That comment says "real drift alerting
# runs from an enrolled machine"; measured 2026-08-25, no machine ran it --
# nothing in launchctl or crontab, and one executing invocation fleet-wide (the
# CI job that says it is not the real one). The machine was enrolled; nothing
# scheduled it. Minute 21 rather than 7 so the two agents do not collide.
install_ledger_drift_agent() {
    _rhn_is_cadence_host || return 0
    _la_install_agent "ledger-drift" \
        "$(_rhn_ai_config_root)/.claude/scripts/ledger_drift_check.sh" 21
}

# Named wrappers so run_doctor reads as a list of checks rather than a list of
# arguments, matching every other _doctor_check_* in lib/helpers.sh.
_doctor_check_renovate_cadence() { _doctor_check_cadence "renovate-held"; }
_doctor_check_ledger_drift_cadence() { _doctor_check_cadence "ledger-drift"; }

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
