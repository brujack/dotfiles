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
#
# A missing/broken profiles.sh degrades safely without this check —
# PROFILE_MAP and PROFILE_CAPS are simply undefined, every lookup below
# falls back to its `:-` default, and the shell keeps starting. But
# "degrades safely" here means "silently loses PROFILE/HAS_*/legacy vars at
# login", which is exactly the failure mode this whole plan exists to make
# visible instead of silent (behavior.md: fail closed on unknown, surface
# more under pressure). A hard `return`/`exit` is deliberately not used —
# this file is sourced by .zprofile at login, and aborting a login shell
# over a degraded (not broken) profile lookup is worse than the problem.
if ! source "${0:A:h}/profiles.sh"; then
  print -u2 "config/profiles.zsh: failed to source ${0:A:h}/profiles.sh -- PROFILE will default to 'unknown' and no HAS_*/legacy identity variables will be set this session."
fi

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
*)
  # A hostname PROFILE_MAP recognises (PROFILE/HAS_* resolved above) but
  # this case has no arm for is a drifted table, not an unmapped guest
  # machine -- warn rather than fail silently, since the ~19 zsh read sites
  # that branch on LAPTOP/STUDIO/OFFICE/etc. would otherwise skip with no
  # visible symptom. A genuinely unmapped hostname (PROFILE=unknown) is the
  # expected, silent case and does not warn.
  if [[ -n "${PROFILE_MAP[${_profiles_hostname}]:-}" ]]; then
    print -u2 "config/profiles.zsh: host '${_profiles_hostname}' resolved PROFILE=${PROFILE} but has no legacy-identity case arm -- add one for '${_profiles_hostname}'."
  fi
  ;;
esac

unset _profiles_hostname
