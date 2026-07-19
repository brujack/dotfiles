#!/usr/bin/env bash
# lib/legacy_rsync.sh — one-way rsync push of legacy/no-git-access dirs, studio-only

_is_legacy_sync_host() {
  [[ "$(hostname -s)" == "studio" ]]
}

sync_legacy_dirs() {
  if ! _is_legacy_sync_host; then
    log_info "legacy-rsync: not studio, skipping"
    return 0
  fi

  local _had_failure=0
  local _src="${_OVERRIDE_GIT_REPOS_SRC:-${HOME}/git-repos}/"

  rsync -ar --delete --exclude=personal "${_src}" "bruce@workstation:~/git-repos/" \
    || { log_warn "legacy-rsync: workstation failed"; _had_failure=1; }
  rsync -ar --delete --exclude=personal "${_src}" "bruce@laptop-1:~/git-repos/" \
    || { log_warn "legacy-rsync: laptop-1 failed"; _had_failure=1; }
  rsync -ar --delete "${_src}" "bruce@ratna:~/git-repos/" \
    || { log_warn "legacy-rsync: ratna failed"; _had_failure=1; }

  [[ ${_had_failure} -eq 1 ]] && return 2
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
