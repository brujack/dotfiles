#!/usr/bin/env bash
# config/hook_repos.sh — repos expected to carry the mandated git hook set
#
# Reporting only: this list decides what counts as a gap in the git-hooks
# sweep (lib/git_hooks.sh) — it never decides what gets installed.
# Installation is pure discovery (a new repo with an install-hooks Makefile
# target gets hooks on the next sweep with no edit here required).
#
# ai-devops is documentation-only today and still belongs here: the mandate in
# repo-structure.md is not conditional on a repo containing code. A docs commit
# still needs the Conventional Commits check (commit-msg) and can still leak a
# credential into a markdown file (pre-commit / ggshield). It may gain code later.
# Not readonly: lib/git_hooks.sh may be sourced more than once in the same
# shell (e.g. re-run tooling, repeated bats sourcing). A readonly array here
# would make the second source's readonly re-declaration fail, and — worse —
# if the empty fallback in lib/git_hooks.sh ever locks in first, this file's
# real list could never load at all, silently. config/profiles.sh made the
# same call for the same reason.
# shellcheck disable=SC2034 # read by lib/git_hooks.sh's sweep (e.g. _git_hooks_gap_repos)
HOOK_EXPECTED_REPOS=(ai-config dotfiles etch-cli state-ledger brucejacksonconsulting-site math ai-devops etch-config terraform_ansible)
