# Design: mas App Store Integration via Brewfiles

**Date:** 2026-04-05
**Status:** Approved

## Summary

Move all `mas install` calls from `setup_env.sh` into the existing Brewfile.\* files using `brew bundle`'s native `mas` support. Remove the ~100-line manual mas block from `setup_env.sh`. No new files, no new capabilities, no new functions — `install_macos_casks()` already dispatches all three bundles based on `HAS_GUI` / `HAS_DEVTOOLS`.

## Motivation

The mas install block in `setup_env.sh` uses deprecated hostname vars (`LAPTOP`, `STUDIO`, `RATNA`, etc.) instead of the `HAS_*` capability system introduced during the brew refactor. It also duplicates the guarding logic that `brew bundle` already handles. Consolidating into Brewfiles brings mas installs into the same lifecycle as cask installs: declarative, idempotent, and capability-driven.

## Changes

### Brewfile (universal — all Macs)

Add the following `mas` entries:

```
mas "Better Rename 9", id: 414209656
mas "Brother iPrint&Scan", id: 1193539993
mas "Blackmagic Disk Speed Test", id: 425264550
mas "Flycut", id: 442160987
mas "iNet Network Scanner", id: 403304796
mas "Mactracker", id: 430255202
mas "Magnet", id: 441258766
mas "Markoff", id: 1084713122
mas "Microsoft Remote Desktop", id: 715768417
mas "Remote Desktop", id: 409907375
mas "Simplenote", id: 692867256
mas "Slack", id: 803453959
mas "Speedtest", id: 1153157709
mas "Sync Folders Pro", id: 522706442
mas "The Unarchiver", id: 425424353
mas "Transmit", id: 403388562
```

### Brewfile.gui (HAS_GUI machines)

Add:

```
mas "Evernote", id: 406056744
```

Evernote was previously gated by `LAPTOP || STUDIO || RECEPTION || OFFICE || HOMES` — all Mac profiles, all of which have `HAS_GUI`.

### Brewfile.devtools (HAS_DEVTOOLS machines)

Add:

```
mas "SQLPro for Postgres", id: 1025345625
mas "Valentina Studio", id: 604825918
mas "Keynote", id: 409183694
mas "iMovie", id: 408981434
mas "Numbers", id: 409203825
mas "Pages", id: 409201541
mas "Pixelmator Pro", id: 1289583905
mas "Read CHM", id: 594432954
mas "Telegram", id: 747648890
mas "Xcode", id: 497799835
```

SQLPro and Valentina Studio were previously gated by `LAPTOP || STUDIO`. The iWork suite, iMovie, Pixelmator Pro, Read CHM, and Telegram were previously gated by `RATNA || LAPTOP || STUDIO`. With RATNA deprecated, these map cleanly to `HAS_DEVTOOLS` (personal_laptop + mac_workstation).

### setup_env.sh

Remove the entire mas install block (approximately lines 160–254). The `softwareupdate --install --all --verbose` call is retained — it is separate from mas and unrelated to this change.

Note: Magnet (441258766) appears twice in the current code (once in the common block, once in the "extra" block). The duplicate in the extra block is dropped.

## No-Change Items

- `install_macos_casks()` in `lib/macos.sh` — no changes needed; it already dispatches `Brewfile`, `Brewfile.gui`, and `Brewfile.devtools` based on capabilities
- `config/profiles.sh` — no changes needed; HAS_PRINTING is not added
- `lib/helpers.sh` — `app_dir_exists` guard logic is no longer needed for these apps since `brew bundle` is idempotent by default

## Testing

- Existing `install_macos_casks()` tests cover the bundle dispatch logic
- Any tests in `tests/setup_env/` that mock or assert on the old mas install block are removed or updated
- `MOCK_MAS_EXIT` mock variable is already available for mas-related test scenarios
- `make test` must exit 0 after changes
