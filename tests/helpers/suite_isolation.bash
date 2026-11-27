#!/usr/bin/env bash
# Suite-level HOME isolation (docs/superpowers/specs/2026-11-21-bats-sentinel-home-design.md).
# Sourced by setup_suite.bash in each test directory. bats calls setup_suite under
# set -eET and teardown_suite with errexit off, both in one shell, so
# _BATS_SENTINEL is a plain, never-exported variable shared between them.

setup_suite() {
    # A nested bats inherits the outer run's environment; never trust its value.
    unset _BATS_SENTINEL
    local _const="${BASH_SOURCE[0]%/*}/../../lib/constants.sh" _uv_ver="" _uv _root
    if [[ -r "${_const}" ]]; then
        _uv_ver="$(sed -n 's/^UV_VER="\(.*\)"$/\1/p' "${_const}")" || _uv_ver=""
    fi
    if [[ -z "${_uv_ver}" ]]; then
        printf '# bats isolation: cannot read UV_VER from %s\n' "${_const}" >&3
    elif [[ -z "${PINNED_UV_BIN:-}" ]]; then
        # Resolved from the pre-swap HOME: the pinned uv lives in the real home.
        _uv="${HOME}/.local/share/dotfiles/pinned/uv-${_uv_ver}/uv"
        if [[ -x "${_uv}" ]]; then
            export PINNED_UV_BIN="${_uv}"
        fi
    fi
    # BSD mktemp -d with a template ignores TMPDIR; the seam reaches the failure branch.
    _root="${_BATS_SENTINEL_TMP_ROOT:-${TMPDIR:-/tmp}}"
    if ! _BATS_SENTINEL="$(mktemp -d "${_root}/bats-sentinel.XXXXXX")"; then
        unset _BATS_SENTINEL
        printf 'bats isolation: cannot create sentinel under %s\n' "${_root}"
        return 1
    fi
    export HOME="${_BATS_SENTINEL}/home" ZDOTDIR="${_BATS_SENTINEL}/home"
    export TMPPREFIX="${_BATS_SENTINEL}/zsh" PARALLEL_HOME="${_BATS_SENTINEL}/parallel"
    export XDG_CONFIG_HOME="${_BATS_SENTINEL}/xdg/config" XDG_CACHE_HOME="${_BATS_SENTINEL}/xdg/cache"
    export XDG_DATA_HOME="${_BATS_SENTINEL}/xdg/data" XDG_STATE_HOME="${_BATS_SENTINEL}/xdg/state"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    if [[ -z "${MOCK_CALLS_FILE:-}" ]]; then
        export MOCK_CALLS_FILE="${_BATS_SENTINEL}/mock_calls"
    fi
    mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" \
        "${XDG_STATE_HOME}" "${PARALLEL_HOME}"
    # The real sudo must be unreachable from every test, including files that never
    # call load_mocks: a lib function writing as root (`_as=(sudo)`, `sudo install`)
    # otherwise reaches /usr/bin/sudo, which is passwordless on the fleet and
    # once left root-owned stubs in /usr/local/bin. A refusing stub heads PATH;
    # tests/mocks (load_mocks) and recorder functions still take precedence.
    # Each step fails the suite: a missing or non-executable stub would let PATH fall
    # through to the real sudo, so the guard must fail closed.
    mkdir -p "${_BATS_SENTINEL}/nosudo" || return 1
    printf '#!/bin/sh\necho "REAL SUDO BLOCKED $*" >&2\nexit 97\n' > "${_BATS_SENTINEL}/nosudo/sudo" || return 1
    chmod +x "${_BATS_SENTINEL}/nosudo/sudo" || return 1
    export PATH="${_BATS_SENTINEL}/nosudo:${PATH}"
}

teardown_suite() {
    local _s="${_BATS_SENTINEL:-}"
    # bats runs teardown_suite even when setup_suite failed.
    if [[ -z "${_s}" || ! -d "${_s}" || "${_s##*/}" != bats-sentinel.* ]]; then
        printf 'bats isolation: no sentinel to check\n'
        return 1
    fi
    rm -rf "${_s}"
    # Judge by existence: tests/mocks/rm exits 0 even when the removal failed.
    if [[ -e "${_s}" ]]; then
        printf 'bats isolation: cannot remove %s; run: chmod -R u+w %s && rm -rf %s\n' "${_s}" "${_s}" "${_s}"
        return 1
    fi
}
