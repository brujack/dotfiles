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
  # ratna deliberately has NO --exclude=personal: it is a retired Intel iMac kept
  # only as a backup of the git repos, not a development box, so a full copy
  # including gitignored content is the point. Confirmed by the operator
  # 2026-08-12. Do not "fix" this asymmetry — it has already produced one false
  # security finding from an agent reading the three lines side by side. Revisit
  # if ratna ever becomes a development machine again.
  rsync -ar --delete "${_src}" "bruce@ratna:~/git-repos/" \
    || { log_warn "legacy-rsync: ratna failed"; _had_failure=1; }

  [[ ${_had_failure} -eq 1 ]] && return 2
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
