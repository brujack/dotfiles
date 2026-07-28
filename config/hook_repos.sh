#!/usr/bin/env bash
# config/hook_repos.sh — repos expected to carry the mandated git hook set
#
# Reporting only: this list decides what counts as a gap in the git-hooks
# sweep (lib/git_hooks.sh) — it never decides what gets installed.
# Installation is pure discovery (a new repo with an install-hooks Makefile
# target gets hooks on the next sweep with no edit here required).
readonly HOOK_EXPECTED_REPOS=(ai-config dotfiles etch-cli state-ledger brucejacksonconsulting-site math ai-devops etch-config terraform_ansible)
