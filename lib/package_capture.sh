#!/usr/bin/env bash
# Package diff capture for state ledger.
# Produces JSON diffs (added/removed/upgraded) per package source.

PACKAGE_CAPTURE_ENABLED="${PACKAGE_CAPTURE_ENABLED:-true}"
LEDGER_BIN="${HOME}/.local/bin/ledger"
MACHINE_ID_PATH="${HOME}/.config/dotfiles/machine-id"

_list_brew_packages() {
    command -v brew &>/dev/null || { printf '[]'; return 0; }
    brew list --versions 2>/dev/null \
        | awk '{print $1" "$2}' \
        | python3 -c "
import sys, json
pkgs = []
for line in sys.stdin:
    parts = line.strip().split(None, 1)
    if len(parts) == 2:
        pkgs.append({'name': parts[0], 'version': parts[1]})
print(json.dumps(pkgs))
"
}

_list_apt_packages() {
    command -v dpkg-query &>/dev/null || { printf '[]'; return 0; }
    dpkg-query -W -f '${Package}\t${Version}\n' 2>/dev/null \
        | python3 -c "
import sys, json
pkgs = []
for line in sys.stdin:
    parts = line.strip().split('\t', 1)
    if len(parts) == 2:
        pkgs.append({'name': parts[0], 'version': parts[1]})
print(json.dumps(pkgs))
"
}

_list_pip_packages() {
    command -v pip3 &>/dev/null || command -v pip &>/dev/null || { printf '[]'; return 0; }
    local _pip_cmd
    _pip_cmd="$(command -v pip3 || command -v pip)"
    "${_pip_cmd}" list --format=json 2>/dev/null \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(json.dumps([{'name': p['name'], 'version': p['version']} for p in data]))
"
}

capture_package_diff() {
    local _source="${1}"
    local _machine_id="${2}"
    local _run_id="${3}"
    local _prev="${4:-[]}"
    local _curr="${5:-[]}"

    local _diff_entry
    _diff_entry=$(python3 -c "
import json, sys, re

VCS_PAT = re.compile(r'^(git\+ssh://|git\+https://|vcs\+|file://|[0-9a-f]{40}$)')

def sanitize(ver):
    return '<vcs-redacted>' if VCS_PAT.match(ver) else ver

prev_list = json.loads(sys.argv[1])
curr_list = json.loads(sys.argv[2])
source = sys.argv[3]
machine_id = sys.argv[4]
run_id = sys.argv[5]
captured_at = sys.argv[6]

prev = {p['name']: p['version'] for p in prev_list}
curr = {p['name']: sanitize(p['version']) for p in curr_list}

added = [{'name': n, 'version': v} for n, v in curr.items() if n not in prev]
removed = [{'name': n, 'version': v} for n, v in prev.items() if n not in curr]
upgraded = [
    {'name': n, 'from': sanitize(prev[n]), 'to': v}
    for n, v in curr.items()
    if n in prev and prev[n] != v
]

if not added and not removed and not upgraded:
    print('SKIP')
    sys.exit(0)

entry = {
    'schema_version': '1.0',
    '_type': 'package',
    'run_id': run_id,
    'machine_id': machine_id,
    'captured_at': captured_at,
    'source': source,
    'added': added,
    'removed': removed,
    'upgraded': upgraded,
}
print(json.dumps(entry))
" \
        "${_prev}" "${_curr}" "${_source}" "${_machine_id}" "${_run_id}" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)") || return 1

    [[ "${_diff_entry}" == "SKIP" ]] && return 0

    if command -v "${LEDGER_BIN}" &>/dev/null; then
        printf '%s' "${_diff_entry}" | "${LEDGER_BIN}" write || true
    else
        printf "WARNING: ledger not found, package diff not recorded\n" >&2
    fi
}

capture_all_packages() {
    [[ "${PACKAGE_CAPTURE_ENABLED}" == "true" ]] || return 0
    local _run_id="${1}"
    local _machine_id
    _machine_id="$(cat "${MACHINE_ID_PATH}" 2>/dev/null)" || {
        printf "WARNING: machine-id not found, skipping package capture\n" >&2
        return 0
    }

    if command -v brew &>/dev/null; then
        local _curr_brew
        _curr_brew="$(_list_brew_packages)"
        capture_package_diff "brew" "${_machine_id}" "${_run_id}" "[]" "${_curr_brew}"
    fi

    if command -v dpkg-query &>/dev/null; then
        local _curr_apt
        _curr_apt="$(_list_apt_packages)"
        capture_package_diff "apt" "${_machine_id}" "${_run_id}" "[]" "${_curr_apt}"
    fi

    local _curr_pip
    _curr_pip="$(_list_pip_packages)"
    [[ "${_curr_pip}" != "[]" ]] && \
        capture_package_diff "pip" "${_machine_id}" "${_run_id}" "[]" "${_curr_pip}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
capture_all_packages "$@"
