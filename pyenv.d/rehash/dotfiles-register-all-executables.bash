#!/usr/bin/env bash
# Sourced by pyenv-rehash between make_shims and install_registered_shims.
# pyenv-versions --executables pipes basenames through `sort -u`; uutils sort
# (Ubuntu 26.04) collates py.test and pytest as equal and drops one, so the
# pytest shim is never registered and remove_stale_shims deletes it. Registering
# the same glob here, without sort, restores it for every caller. See
# docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md.
declare -f make_shims > /dev/null || return 0
# shopt -p exits 1 when any named option is off, and pyenv-rehash runs under
# set -e, so an unguarded capture aborts every rehash. Measured: rc 1, zero shims.
_dotfiles_rehash_opts="$(shopt -p nullglob dotglob || true)"
shopt -s nullglob dotglob
make_shims "${PYENV_ROOT}"/versions/*/bin/* "${PYENV_ROOT}"/versions/*/envs/*/bin/*
eval "${_dotfiles_rehash_opts}"
unset _dotfiles_rehash_opts
