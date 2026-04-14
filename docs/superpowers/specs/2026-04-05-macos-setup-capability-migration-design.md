# Design: macOS setup_env.sh Capability Migration

**Date:** 2026-04-05
**Status:** Approved

## Summary

Complete the macOS section of `setup_env.sh` compliance with the `HAS_*` capability system and the Brewfile modularization pattern established in recent work. Move all inline `brew_install_cask/formula` calls to the appropriate Brewfiles, remove the now-superseded hostname-var conditional block, and replace remaining old hostname var conditions with `HAS_*` capability vars.

## Motivation

The Brewfile modularization work (Brewfile, Brewfile.gui, Brewfile.devtools) moved cask installs out of `setup_env.sh`. However, several inline `brew_install_cask/formula` calls and their tap prerequisites were left behind in the macOS block. These are inconsistent with the new pattern: `install_macos_casks()` already dispatches `brew bundle` for all three Brewfiles based on capabilities, so inline installs are redundant and unsupported by the capability model.

Additionally, four sites in `setup_env.sh` still use deprecated hostname vars (`LAPTOP`, `STUDIO`, `RECEPTION`, `OFFICE`, `HOMES`, `RATNA`, `WORKSTATION`, `CRUNCHER`) instead of `HAS_*` vars. `RATNA` is a deprecated host and should be removed everywhere.

## Changes

### Brewfile (universal) — add tap + formula

```
tap "teamookla/speedtest"
brew "teamookla/speedtest/speedtest"
```

### Brewfile.gui — add cask

```
cask "miro"
```

### Brewfile.devtools — add taps + formulae/casks

```
tap "chef/chef"
tap "datawire/blackbird"
tap "go-task/tap"
tap "redpanda-data/tap"
tap "snyk/tap"
cask "chef/chef/inspec"
cask "dotnet"
brew "datawire/blackbird/telepresence-arm64"
brew "go-task/tap/go-task"
brew "redpanda-data/tap/redpanda"
brew "snyk/tap/snyk"
```

`telepresence-arm64` was previously gated by all Mac hostname vars — it moves to `Brewfile.devtools` (HAS_DEVTOOLS: personal_laptop + mac_workstation).

### setup_env.sh — macOS brew block (lines 130–155)

Remove all inline brew installs and their tap prerequisites. After the change, the `elif [ -x "$(command -v brew)" ]` block contains only:

```bash
brew_update
printf "Installing other brew stuff...\\n"
brew_tap_if_missing homebrew/bundle
install_macos_casks

printf "Cleaning Homebrew up...\\n"
brew cleanup
```

Specifically removed:

- `brew_install_cask chef/chef/inspec` → moved to Brewfile.devtools
- `brew_tap_if_missing cloudflare/cloudflare` → no longer needed (cloudflared is in universal Brewfile from homebrew-core)
- `brew_install_cask dotnet` → moved to Brewfile.devtools
- `brew_install_formula go-task/tap/go-task` → moved to Brewfile.devtools
- `brew_install_cask miro` → moved to Brewfile.gui
- `brew_tap_if_missing snyk/tap` → moved to Brewfile.devtools as `tap "snyk/tap"`
- `brew_install_formula snyk` → moved to Brewfile.devtools
- `brew_tap_if_missing teamookla/speedtest` → moved to Brewfile as `tap "teamookla/speedtest"`
- `brew_install_formula speedtest` → moved to Brewfile
- `brew_install_formula redpanda-data/tap/redpanda` → moved to Brewfile.devtools
- The entire hostname-gated block (`datawire/blackbird/telepresence-arm64` + `cloudflared`) → telepresence moves to Brewfile.devtools; cloudflared was already in universal Brewfile (duplicate removed)

### setup*env.sh — hostname var → HAS*\* migrations

**macOS aws-cli (line ~1019):** Collapse outer hostname gate + inner `MACOS` check:

```bash
# before
if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
  mkdir -p ${HOME}/software_downloads/awscli
  if [[ -n ${MACOS} ]]; then
    ...
  fi
fi

# after
if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
  mkdir -p ${HOME}/software_downloads/awscli
  ...
fi
```

`HAS_AWS` covers personal_laptop + mac_workstation; mac_mini does not have `HAS_AWS`, which correctly narrows the gate (mac_mini did not need aws-cli).

**Ansible virtualenv (line ~1225):**

```bash
# before
if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]] || [[ -n ${RATNA} ]]; then

# after
if [[ -n ${HAS_DEVTOOLS} ]]; then
```

`HAS_DEVTOOLS` covers personal_laptop + mac_workstation + linux_workstation + server. `WORKSTATION` and `CRUNCHER` (linux_workstation) both have `HAS_DEVTOOLS`, so Linux behaviour is preserved.

**pip update in UPDATE block (line ~1282):**

```bash
# before
if [[ -n ${STUDIO-} || -n ${LAPTOP-} || -n ${RECEPTION-} || -n ${OFFICE-} || -n ${HOMES-} || -n ${WORKSTATION-} || -n ${CRUNCHER-} || -n ${RATNA-} ]]; then

# after
if [[ -n ${HAS_DEVTOOLS} ]]; then
```

Same mapping as above.

## No-Change Items

- Linux aws-cli block (line ~1033, `WORKSTATION || CRUNCHER`) — deferred to Linux spec
- All other Linux-only hostname var usages — deferred to Linux spec
- `detect_env.sh` legacy alias block — kept until all call sites are updated (Linux spec will finish this)
- `lib/macos.sh` `install_macos_casks()` — no changes needed

## Testing

- `bash -n setup_env.sh && zsh -n setup_env.sh` must pass after changes
- `brew bundle check --file Brewfile --no-upgrade` — verify no parse errors
- `brew bundle check --file Brewfile.gui --no-upgrade` — verify no parse errors
- `brew bundle check --file Brewfile.devtools --no-upgrade` — verify no parse errors
- `make test` must exit 0
