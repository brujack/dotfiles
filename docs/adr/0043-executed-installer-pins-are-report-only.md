# ADR-0043: Pins on executed installers are report-only, checked against the installer's own history

**Date:** 2026-10-08
**Status:** Accepted

## Context

`HOMEBREW_INSTALL_SHA` (`lib/constants.sh`) pins the commit of Homebrew's `install.sh`, which
`lib/macos.sh:install_homebrew` and both bootstrap scripts download and run. ADR-0013 introduced
the pin and said `-t check-versions` would track it.

It never did. Measured 2026-10-07 from `claude`, unauthenticated:

```
Homebrew/install/commits/master   422  "No commit found for SHA: master"   (default_branch: main)
ohmyzsh/ohmyzsh/releases/latest   404  "Not Found"                          (no releases, no tags)
```

Both checks WARNed on every run, so the installer pin went unmonitored from 2026-06-21 until
`install.sh` had moved on to `09c62fc5` (2026-10-01).

Fixing the endpoint raised two further questions.

1. **What to compare against.** Over the 90 days to 2026-10-07, Homebrew/install took 74
   commits, and 9 of them touched `install.sh`. Comparing against the repo tip would report
   OUTDATED for unrelated churn about 8 times in 9.
2. **Whether `--update` may bump it.** Once the check works, the existing
   `_prompt_version_update` path becomes reachable for this pin for the first time. That path
   is a one-keystroke `sed` with no diff shown.

The oh-my-zsh check had a different defect: its pin (`OH_MY_ZSH_VER="master"`) is a branch name
fed to `git clone --branch`, so it has no upstream version to compare.

## Decision

- A pin on a script that is downloaded and executed is **report-only** in `-t check-versions`.
  On drift the check prints `[OUTDATED]` and a `https://github.com/<repo>/compare/<pin>...<latest>`
  URL. It never calls `_prompt_version_update`, with or without `--update`. Bumping the pin is a
  manual edit, made after reading the installer diff.
- The drift reference is the newest commit that touched the executed file
  (`commits?path=install.sh&per_page=1`), not the repository tip. A path query follows the
  default branch, so a branch rename cannot break it as `commits/master` did.
- A pin that is a branch name is not version-checked. `_check_cv_oh_my_zsh` was deleted.
- Every check-versions network call carries `--max-time 10`.

Implemented by #321. #322 added the tests that fail if any part regresses.

## Consequences

**Easier:** an OUTDATED homebrew-install line now means the installer itself changed, and the
review link is in the output. A trust anchor for executed code cannot be moved by a stray `y`.

**Harder / required going forward:**

- `-t check-versions` exits 1 while the pin is behind, until someone reviews the diff and edits
  `lib/constants.sh` by hand. That is deliberate.
- Any future pin on an executed script must follow the same shape: report-only, compared against
  the file's own history, with a test that `_prompt_version_update` is not called.
- `--update` no longer covers every pin; the help text and README say so.

## Related

- [ADR-0013](0013-no-curl-bash-installs.md): introduced the SHA pin. Its "update tracking" consequence is amended here.
- Spec: [2026-10-07-check-versions-curl-max-time-design.md](../superpowers/specs/2026-10-07-check-versions-curl-max-time-design.md)
- PRs: #321 (library change), #322 (tests and README)
