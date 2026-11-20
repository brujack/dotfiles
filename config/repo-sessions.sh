#!/usr/bin/env bash
# Per-host list of repo directories (relative to ~/git-repos/personal) that
# bin/repo-session --detached --all keeps alive as tmux sessions. Keyed by `hostname -s`.
# Keep each host's entry on one line: run_all reads it with `read -ra`, which stops at
# the first newline.
# shellcheck disable=SC2034 # REPO_SESSIONS is read by bin/repo-session run_all, which sources this file in a subshell
declare -A REPO_SESSIONS=(
  [claude]="etch-cli etch-config dotfiles ai-config ai-devops math"
  [workstation]="terraform_ansible/ansible"
)
