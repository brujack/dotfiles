# Brewfile Profile Split Design

**Date:** 2026-04-02
**Status:** Approved

## Goal

Replace ~50 manual `if ! app_dir_exists ...; then brew_install_cask ...; fi` blocks in `setup_env.sh` (lines 157–370) with three `brew bundle`-managed Brewfiles split by capability. Eliminates brittle `app_dir_exists` path checks, removes old hostname-var profile gates, and makes the cask list declarative and easy to maintain.

---

## Background

The current code:

- Uses `app_dir_exists "/Applications/Foo.app"` as an install guard — fragile, paths drift
- Gates installs with legacy hostname vars (`LAPTOP`, `STUDIO`, `RECEPTION`, etc.) instead of `HAS_*` capability vars
- Has a comment claiming casks "fail if already installed via Brewfile" — this has not been true since Homebrew 2.x; `brew bundle` is fully idempotent

---

## Architecture

Three Brewfiles in the repo root:

| File                | Condition          | Contents                                  |
| ------------------- | ------------------ | ----------------------------------------- |
| `Brewfile`          | always (all macOS) | Existing formulae/casks + universal casks |
| `Brewfile.gui`      | `HAS_GUI`          | Desktop-only apps                         |
| `Brewfile.devtools` | `HAS_DEVTOOLS`     | Dev tools                                 |

`brew bundle` tracks installation state itself — no `app_dir_exists` checks needed.

---

## File Contents

### `Brewfile` — add these casks (universal, all macOS machines)

```ruby
cask "1password"
cask "adobe-acrobat-reader"
cask "alfred"
cask "appcleaner"
cask "beyond-compare"
cask "daisydisk"
cask "expressvpn"
cask "firefox"
cask "flycut"
cask "github"
cask "google-chrome"
cask "istat-menus"
cask "iterm2"
cask "macdown"
cask "malwarebytes"
cask "powershell"
cask "slack"
cask "spotify"
cask "teamviewer"
cask "tidal"
cask "visual-studio-code"
cask "vlc"
cask "warp"
cask "zed"
cask "zoom"
```

### `Brewfile.gui` — new file (`HAS_GUI` machines)

```ruby
cask "adobe-creative-cloud"
cask "balenaetcher"
cask "bambu-studio"
cask "chatgpt"
cask "claude"
cask "discord"
cask "logi-options-plus"
cask "microsoft-office"
cask "obs"
cask "sonos"
```

### `Brewfile.devtools` — new file (`HAS_DEVTOOLS` machines)

```ruby
cask "carbon-copy-cloner"
cask "cursor"
cask "dbeaver-community"
cask "docker"
cask "fork"
cask "funter"
cask "google-cloud-sdk"
cask "lens"
cask "mysqlworkbench"
cask "oracle-jdk"
cask "postman"
cask "session-manager-plugin"
cask "sourcetree"
cask "steam"
cask "vagrant"
cask "virtualbox"
```

---

## Orchestration

In `setup_env.sh`, replace lines 137–139 (the existing `brew bundle check/bundle` block) and lines 157–370 (all if/then cask blocks) with:

```bash
brew bundle --file "${BREWFILE_LOC}/Brewfile"

local dotfiles_dir="${PERSONAL_GITREPOS}/${DOTFILES}"
[[ -n ${HAS_GUI} ]]      && brew bundle --file "${dotfiles_dir}/Brewfile.gui"
[[ -n ${HAS_DEVTOOLS} ]] && brew bundle --file "${dotfiles_dir}/Brewfile.devtools"
```

The `if ! brew bundle check; then brew bundle; fi` wrapper is removed — `brew bundle` performs its own check and is a no-op when everything is installed.

**Stays in shell (not moving to Brewfile):** tap-based installs (`chef/chef/inspec`, `dotnet`, `miro`, `snyk`, `go-task`, `speedtest`, `redpanda`, `telepresence-arm64`, `cloudflared`) and `claude-code` (has post-install plugin logic). Lines 140–153 are unchanged.

---

## Over-installation Acceptance

Mapping the old per-hostname conditions to `HAS_*` capability buckets means some apps install on slightly more machines than before:

- `adobe-creative-cloud`, `sonos`: previously LAPTOP+STUDIO+RECEPTION only → now all `HAS_GUI` (adds OFFICE, HOMES). Accepted.
- `cursor`: previously STUDIO+RECEPTION+LAPTOP → now all `HAS_DEVTOOLS`. Accepted.

---

## Files Changed

| File                                  | Action                                                                         |
| ------------------------------------- | ------------------------------------------------------------------------------ |
| `Brewfile`                            | Modify — append 25 universal casks                                             |
| `Brewfile.gui`                        | Create — 10 GUI casks                                                          |
| `Brewfile.devtools`                   | Create — 16 devtools casks                                                     |
| `setup_env.sh`                        | Modify — replace lines 137–139 + 157–370 with 4-line brew bundle orchestration |
| `tests/setup_env/install_guards.bats` | Modify — add brew bundle orchestration tests                                   |

---

## Testing

Add tests to `tests/setup_env/install_guards.bats` verifying:

- `brew bundle` is called with `Brewfile` path on all macOS runs
- `brew bundle` is called with `Brewfile.gui` path when `HAS_GUI` is set
- `brew bundle` is NOT called with `Brewfile.gui` path when `HAS_GUI` is unset
- `brew bundle` is called with `Brewfile.devtools` path when `HAS_DEVTOOLS` is set
- `brew bundle` is NOT called with `Brewfile.devtools` path when `HAS_DEVTOOLS` is unset

Mock pattern: set `MOCK_CALLS_FILE` and assert `grep -q "brew bundle.*Brewfile.gui"` etc.
