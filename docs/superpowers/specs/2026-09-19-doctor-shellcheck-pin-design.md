# doctor: the resolved shellcheck must match SHELLCHECK_VER

**Status:** Spec
**Closes backlog rows:** "the pinned shellcheck is outranked by linuxbrew on both Linux boxes' PATH",
"`run_check_versions` checks the shellcheck on PATH, not the one the pin manages",
"doctor arm: the RESOLVED shellcheck must match `SHELLCHECK_VER`"

## Problem

`make lint` runs whichever `shellcheck` the invoking shell resolves first
(`Makefile:12`, `SHELLCHECK := $(shell command -v shellcheck)`). The repo pins it only on
Linux: `_install_ubuntu_shellcheck` installs `SHELLCHECK_VER` (0.11.0) into
`/usr/local/bin`. On `claude`, `/home/linuxbrew/.linuxbrew/bin` is at PATH position 5 and
`/usr/local/bin` at position 9, so a `brew install shellcheck` would silently put an
unmanaged copy in front of the pin, and the lint gate would run it. Competing copies were
removed by hand on 2026-09-18, so nothing stops a recurrence and nothing would report one.

On macOS, shellcheck comes from `Brewfile:108` (`brew "shellcheck"  # [HAS_DEVTOOLS]`),
which is unpinned. It matches CI's pinned 0.11.0 today only because brew's current release
is also 0.11.0.

Premise verified 2026-09-19 with `command grep -n shellcheck lib/helpers.sh`: `run_doctor`
has no shellcheck check, and every hit in `lib/helpers.sh` is a directive comment. Resolved
copies measured the same day from an interactive zsh: Studio `/opt/homebrew/bin/shellcheck`
0.11.0; `claude` and `workstation` `/usr/local/bin/shellcheck` 0.11.0, with neither
`/home/linuxbrew/.linuxbrew/bin/shellcheck` nor `/usr/bin/shellcheck` present. So on all
three development machines, a check added today passes.

## Design

Add shellcheck to `_doctor_check_versions` (`lib/helpers.sh`) through the existing
`_doctor_check_one_version`, which already does what the row asks. It resolves the binary
with `command -v`, parses its version, prefix-matches the pin, and names the resolved path
in both the PASS and the mismatch message.

One change to that helper: an optional fifth argument, `_on_mismatch` (`fail`, the
default, or `warn`). Every existing caller keeps FAIL. `warn` reports through
`doctor_warn`, which counts toward the summary's warnings, not `log_warn`, which counts
nothing. The shellcheck call passes `warn` only when `MACOS` is set and omits the argument
otherwise, so Linux takes the helper's default.

| platform | on mismatch                                                                        | why                                                                                                                       |
| -------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Linux    | **FAIL**, naming the resolved path and the pin                                     | the repo pins it there, and the remedy is concrete: remove the competing copy, or run `-t developer` to reinstall the pin |
| macOS    | **WARN**: local lint runs a different shellcheck than CI (installed, path, CI pin) | brew-managed and unpinned; a FAIL would stay red with no remedy this repo provides. Operator decision, 2026-09-19         |

Not installed keeps the helper's existing behaviour: a WARN, "not installed (skipping
version check)", the same as go, python3, ruby and zsh today.

**Actor.** `command -v` answers for the shell `doctor` runs in, which is the same shell a
`make lint` launched from it resolves through. A hook started by an editor or cron gets a
different `PATH` (see `CLAUDE.md`'s actor table) and is out of scope; the report names the
path it checked, so a reader can tell which copy the verdict is about.

## Rows closed

- **Outranked pin**: the recurrence now turns `doctor` red on Linux and names the copy.
- **`run_check_versions` reads PATH**: it reports on the same artifact `doctor` now asserts
  is the pin. It is correct whenever `doctor` passes, and `doctor` catches the case where it
  is not. No change to `run_check_versions` itself.
- **Doctor arm**: this change.

## Testing

Real-function tests in `tests/setup_env/unit.bats`, beside the existing
`_doctor_check_versions real:` cases. Stubs are `#!/bin/sh` scripts that print
`version: X`, placed in stub directories. Each test builds `PATH` as its stub directories
plus `/usr/bin:/bin`, so `grep` and `head` still resolve. `MACOS`, `LINUX` and `UBUNTU` are
set explicitly in every test: `load_setup_env` leaves them as inherited, and a Mac
developer's shell exports `MACOS`.

| #   | setup                                                                          | expected                                                                             |
| --- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| 1   | Linux, stub 0.11.0                                                             | PASS naming the stub's path                                                          |
| 2   | **negative control**: Linux, stub 0.10.0 in a directory ahead of a stub 0.11.0 | FAIL naming the 0.10.0 stub's path, not the pinned one                               |
| 3   | macOS, stub 0.12.0                                                             | WARN (not FAIL) naming path, installed version and CI pin; `_DOCTOR_WARN` +1, `_DOCTOR_FAILED` stays 0 |
| 4   | macOS, mismatched `python3` stub                                               | still FAIL, which proves the WARN severity is scoped to shellcheck                   |
| 5   | Linux, stub printing no version                                                | WARN "could not parse", unchanged helper path                                        |

Test 2 is the one the backlog row demands. The check passes on every machine today, so
without a case where a competing copy is present and wins, the check would ship untested
against the only failure it exists to catch. Three mutations are part of verification, one per decision:

- deleting the new call line turns 1–3 red;
- passing `warn` for shellcheck unconditionally turns 2 red;
- changing the helper's `_on_mismatch` default to `warn` turns 4 red, and 2 as well
  because the Linux call relies on the default.

## Verification

- `make test` green; the five cases above pass; all three mutations go red.
- On `claude`: `setup_env.sh -t doctor` shows `[PASS] shellcheck (0.11.0) — /usr/local/bin/shellcheck`.
- On the Studio: the same line with `/opt/homebrew/bin/shellcheck`, and a WARN rather than a
  FAIL the day brew moves past 0.11.0.

## Out of scope

- Pinning shellcheck on macOS (`brew pin`, or a pinned download). The Mac verdict is a WARN
  by decision; revisit if Mac-vs-CI lint skew ever costs a red CI run.
- Resolving as a non-interactive actor (hooks started from editors, cron).
- Doctor checks for `tflint`/`tfsec` pins, which have their own backlog row.
