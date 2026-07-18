#!/usr/bin/env bash
# scripts/sync_git_repos.sh — git-native sync for personal/ repos + state-ledger,
# studio-only rsync push for legacy/no-git-access dirs + ratna backup.

_sync_git_repos_usage() {
  cat <<'USAGE'
Usage: sync_git_repos.sh [--git-only|--legacy-only|-h|--help]

Two independent sync modes:

  git sync     Fetches every repo under ~/git-repos/personal/ plus
               ~/.local/share/state-ledger. Fast-forward pulls when
               behind, pushes when ahead, warns and skips dirty or
               diverged repos. Never force-pushes, never auto-merges.
               Safe to run on any machine.

  legacy sync  One-way rsync push (--delete) of legacy/no-git-access
               directories from studio to workstation and laptop-1
               (excluding personal/, which git sync already owns
               there), plus a full-tree backup push to ratna. Runs
               only on studio; no-ops elsewhere.

Options:
  --git-only     Run only the git sync.
  --legacy-only  Run only the legacy rsync sync.
  -h, --help     Show this help and exit.

Exit codes:
  0  everything synced cleanly
  2  completed, but one or more repos/targets were skipped (see warnings above)
USAGE
}

sync_git_repos_main() {
  local _mode="both"
  case "${1:-}" in
    -h|--help)
      _sync_git_repos_usage
      return 0
      ;;
    --git-only)
      _mode="git"
      ;;
    --legacy-only)
      _mode="legacy"
      ;;
    "")
      _mode="both"
      ;;
    *)
      printf "Unrecognized option: %s\n\n" "${1}" >&2
      _sync_git_repos_usage >&2
      return 1
      ;;
  esac

  local _rc=0

  if [[ "${_mode}" == "both" || "${_mode}" == "git" ]]; then
    sync_git_repos || _rc=2
  fi
  if [[ "${_mode}" == "both" || "${_mode}" == "legacy" ]]; then
    sync_legacy_dirs || _rc=2
  fi

  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/workflows.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/git_sync.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/legacy_rsync.sh"

sync_git_repos_main "$@"
exit $?
