#!/usr/bin/env bash
# Boot-time repo tmux sessions: installer and doctor check for
# config/systemd/repo-sessions.service (spec 2026-11-19-repo-session-management).
#
# N1: nothing here creates, kills or restarts a tmux session or starts the unit.
# The unit is only enabled, so it acts from the next boot. Linger is enabled
# FIRST: enabling linger with no user manager running starts one, and a manager
# started after `enable` would start the unit and create sessions.

_repo_sessions_repo_root() {
    printf '%s/%s' "${PERSONAL_GITREPOS}" "${DOTFILES}"
}

# Prints this host's REPO_SESSIONS entry (space-separated dirs), or nothing when the
# list is unreadable or has no entry for the host. The list is sourced in a subshell,
# as bin/repo-session does, so its variables stay out of this shell.
_repo_sessions_entry() {
    local _list="${REPO_SESSIONS_FILE:-$(_repo_sessions_repo_root)/config/repo-sessions.sh}"
    local _host="${_REPO_SESSION_HOST:-$(hostname -s)}"
    [[ -r "${_list}" ]] || return 0
    (
        # shellcheck source=/dev/null # path is a runtime seam, not statically known
        source "${_list}" && printf '%s' "${REPO_SESSIONS[${_host}]-}"
    ) 2> /dev/null
    return 0
}

# _repo_sessions_link <src> <dest> <label>: mkdir the parent, then safe_link.
_repo_sessions_link() {
    local _src="$1" _dest="$2" _label="$3"
    run_cmd mkdir -p "$(dirname "${_dest}")" || {
        log_warn "repo-sessions: mkdir failed for $(dirname "${_dest}") (${_label})"
        return 1
    }
    safe_link "${_src}" "${_dest}" || {
        log_warn "repo-sessions: cannot link ${_label}"
        return 1
    }
}

_repo_sessions_install_macos() {
    local _root="$1"
    # A fresh ~/.ssh must not be group- or world-readable; an existing one is left alone.
    if [[ ! -d "${HOME}/.ssh" ]]; then
        run_cmd mkdir -m 700 "${HOME}/.ssh" || {
            log_warn "repo-sessions: mkdir failed for ${HOME}/.ssh"
            return 1
        }
    fi
    _repo_sessions_link "${_root}/bin/home-lan-probe" \
        "${HOME}/.local/bin/home-lan-probe" "home-lan-probe" || return 1
    _repo_sessions_link "${_root}/.ssh/known_hosts_home" \
        "${HOME}/.ssh/known_hosts_home" "known_hosts_home" || return 1
}

_repo_sessions_install_linux() {
    local _root="$1"
    local _systemctl="${_SYSTEMCTL_BIN:-systemctl}" _loginctl="${_LOGINCTL_BIN:-loginctl}"
    local _unit_dir="${_SYSTEMD_USER_DIR:-${HOME}/.config/systemd/user}"
    local _linger

    _repo_sessions_link "${_root}/bin/repo-session" \
        "${HOME}/.local/bin/repo-session" "repo-session" || return 1

    # Linger first (N1 above).
    _linger="$("${_loginctl}" show-user "${USER}" -p Linger 2> /dev/null)" || {
        log_warn "repo-sessions: cannot read linger state for ${USER}"
        return 1
    }
    # Same predicate as doctor: anything but a positive Linger=yes needs enabling.
    if [[ "${_linger}" != "Linger=yes" ]]; then
        run_cmd sudo "${_loginctl}" enable-linger "${USER}" || {
            log_warn "repo-sessions: sudo loginctl enable-linger ${USER} failed"
            return 1
        }
    fi

    run_cmd mkdir -p "${_unit_dir}" || {
        log_warn "repo-sessions: mkdir failed for systemd user dir ${_unit_dir}"
        return 1
    }
    safe_link "${_root}/config/systemd/repo-sessions.service" \
        "${_unit_dir}/repo-sessions.service" || {
        log_warn "repo-sessions: cannot link repo-sessions.service"
        return 1
    }

    run_cmd "${_systemctl}" --user daemon-reload || {
        log_warn "repo-sessions: systemctl --user daemon-reload failed"
        return 1
    }
    # Already enabled is a no-op, so a second run changes nothing.
    # Keyed on the word: `enabled-runtime` also exits 0 but does not survive a reboot.
    [[ "$("${_systemctl}" --user is-enabled repo-sessions.service 2> /dev/null)" == "enabled" ]] && return 0
    run_cmd "${_systemctl}" --user enable repo-sessions.service || {
        log_warn "repo-sessions: systemctl --user enable repo-sessions.service failed"
        return 1
    }
}

install_repo_sessions() {
    local _root
    _root="$(_repo_sessions_repo_root)"
    if [[ -n "${MACOS:-}" ]]; then
        _repo_sessions_install_macos "${_root}" || return 1
    elif [[ -n "${LINUX:-}" ]]; then
        [[ -n "$(_repo_sessions_entry)" ]] || return 0
        _repo_sessions_install_linux "${_root}" || return 1
    fi
    return 0
}

_doctor_check_repo_sessions() {
    local _entry _dir _name _missing="" _issues=0
    local _systemctl="${_SYSTEMCTL_BIN:-systemctl}" _loginctl="${_LOGINCTL_BIN:-loginctl}"
    local _tmux="${_TMUX_BIN:-tmux}"
    local -a _dirs
    # Hosts without an entry have no sessions by design: silent, not PASS.
    _entry="$(_repo_sessions_entry)"
    [[ -n "${_entry}" ]] || return 0

    printf '\nRepo sessions:\n'

    # Anything but a positive Linger=yes (including an unreadable state) is a FAIL.
    if [[ "$("${_loginctl}" show-user "${USER}" -p Linger 2> /dev/null)" != "Linger=yes" ]]; then
        doctor_fail "repo-sessions" "linger is off — run: sudo loginctl enable-linger \"\$USER\""
        _issues=$((_issues + 1))
    fi
    # Keyed on the word, not the exit code: `enabled-runtime` exits 0 but is not
    # persistent, and a linked, not-yet-enabled unit prints `linked` with rc 1.
    if [[ "$("${_systemctl}" --user is-enabled repo-sessions.service 2> /dev/null)" != "enabled" ]]; then
        doctor_fail "repo-sessions" "unit not enabled — run: ./setup_env.sh -t setup_user"
        _issues=$((_issues + 1))
    fi
    if [[ "$("${_systemctl}" --user is-failed repo-sessions.service 2> /dev/null)" == "failed" ]]; then
        doctor_fail "repo-sessions" \
            "unit failed — run: systemctl --user restart repo-sessions.service"
        _issues=$((_issues + 1))
    fi

    read -ra _dirs <<< "${_entry}"
    for _dir in "${_dirs[@]}"; do
        _name="${_dir##*/}"
        "${_tmux}" has-session -t "=${_name}" 2> /dev/null \
            || _missing="${_missing:+${_missing}, }${_name}"
    done
    if [[ -n "${_missing}" ]]; then
        doctor_warn "repo-sessions" \
            "no tmux session for: ${_missing} — run: repo-session --detached --all"
        _issues=$((_issues + 1))
    fi

    [[ "${_issues}" -eq 0 ]] && doctor_pass "repo-sessions: unit enabled, sessions present"
    return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
