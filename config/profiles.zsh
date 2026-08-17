#!/usr/bin/env zsh
# config/profiles.zsh — zsh-side derivation of machine identity from the
# single shared table in config/profiles.sh. Resolves PROFILE, the HAS_*
# capability set, and the legacy per-host identity variables that every
# existing zsh read site (2_functions.zsh, 5_general.zsh, 7_final.zsh,
# .zprofile) still expects.
#
# Both .zprofile (login) and 1_init.zsh (interactive) source this file, so a
# login+interactive shell runs it twice in one process. Every assignment
# below uses `export`, never `readonly` — a `readonly` reassignment on the
# second pass would abort the shell. 1_init.zsh solves the same problem for
# NOBLE/RESOLUTE with a `${VAR+x}` guard; that guard isn't needed here
# because none of these values differ between the two passes, so a plain
# re-export is harmless.

# ${0:A:h} resolves the file's own path — through symlinks — to its
# directory, which is how this works whether this file is reached via the
# repo directly or via the ~/.zprofile / ~/.config/.zshrc.d symlinks the
# setup script creates into $HOME.
source "${0:A:h}/profiles.sh"

_profiles_hostname="$(hostname -s)"
export PROFILE="${PROFILE_MAP[${_profiles_hostname}]:-unknown}"

# zsh does not word-split unquoted parameter expansions (SH_WORD_SPLIT is
# off by default, unlike bash/sh). Without the `=` flag below,
# `${PROFILE_CAPS[$PROFILE]}` would iterate as a SINGLE element holding the
# whole capability string (e.g. "gui devtools aws k8s docker rust
# printing"), producing one absurdly-named HAS_* variable instead of one
# per capability. `${=...}` forces the same splitting bash's `for` gets for
# free from its own field splitting.
for _profiles_cap in ${=PROFILE_CAPS[${PROFILE}]:-}; do
  export "HAS_${(U)_profiles_cap}=1"
done
unset _profiles_cap

# Legacy per-host identity variables. Every existing zsh read site branches
# on these directly rather than on PROFILE/HAS_*, so they must keep being
# set until those call sites are migrated. A wireless twin (`<name>-1`) sets
# the same variable as its wired counterpart, matching PROFILE_MAP.
case "${_profiles_hostname}" in
laptop | laptop-1) export LAPTOP=1 ;;
studio | studio-1) export STUDIO=1 ;;
reception | reception-1) export RECEPTION=1 ;;
ratna | ratna-1) export RATNA=1 ;;
office | office-1) export OFFICE=1 ;;
home-1) export HOMES=1 ;;
workstation) export WORKSTATION=1 ;;
cruncher) export CRUNCHER=1 ;;
esac

unset _profiles_hostname
