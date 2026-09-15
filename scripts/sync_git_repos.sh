#!/usr/bin/env bash
# scripts/sync_git_repos.sh — git-native sync for personal/ repos + state-ledger,
# studio-only rsync push for legacy/no-git-access dirs + ratna backup.

_sync_git_repos_usage() {
  cat <<'USAGE'
Usage: sync_git_repos.sh [--git-only|--legacy-only] [--dry-run] [-h|--help]

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
  --dry-run      Suppress every outbound write: no push, no rsync.
                 NOT a no-op: still fetches from each remote and
                 fast-forwards clean repos that are behind.
                 Composable with --git-only / --legacy-only, but
                 those two together are rejected as ambiguous.
  -h, --help     Show this help and exit.

Exit codes:
  0  everything synced cleanly
  2  completed, but one or more repos/targets were skipped (see warnings above)
USAGE
}

sync_git_repos_main() {
  local _mode="both"
  local _mode_set=0
  local _arg

  for _arg in "$@"; do
    case "${_arg}" in
      -h|--help)
        _sync_git_repos_usage
        return 0
        ;;
      --git-only)
        if [[ "${_mode_set}" -eq 1 && "${_mode}" != "git" ]]; then
          printf "Conflicting mode flags: --git-only and --legacy-only are mutually exclusive\n\n" >&2
          _sync_git_repos_usage >&2
          return 1
        fi
        _mode="git"
        _mode_set=1
        ;;
      --legacy-only)
        if [[ "${_mode_set}" -eq 1 && "${_mode}" != "legacy" ]]; then
          printf "Conflicting mode flags: --git-only and --legacy-only are mutually exclusive\n\n" >&2
          _sync_git_repos_usage >&2
          return 1
        fi
        _mode="legacy"
        _mode_set=1
        ;;
      --dry-run)
        # Deliberately a plain (non-readonly) assignment: this is the
        # standalone entry point's own process, invoked once per run, but a
        # readonly DRY_RUN would make a second parse in the same shell (e.g.
        # a test that calls sync_git_repos_main more than once) fail outright.
        # _dry_run_active reads it back from this same process, so a plain
        # assignment is sufficient.
        # shellcheck disable=SC2034 # consumed by _dry_run_active() in
        # lib/helpers.sh (sourced below at runtime) -- cross-file, so a
        # single-file shellcheck pass over this script cannot see the read.
        DRY_RUN=1
        ;;
      *)
        printf "Unrecognized option: %s\n\n" "${_arg}" >&2
        _sync_git_repos_usage >&2
        return 1
        ;;
    esac
  done

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
