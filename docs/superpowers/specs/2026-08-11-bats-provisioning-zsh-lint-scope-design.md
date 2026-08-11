# Design: bats provisioning parity and `zsh -n` lint scope

**Date:** 2026-08-11
**Status:** Draft — awaiting review
**Backlog row addressed:** "Fail-closed widened the fleet's bats/zsh dependency"

## Context

The backlog row records that ADR-0017's fail-closed pre-push trigger made a new failure
mode reachable: a machine lacking `bats` or `zsh` is now blocked from pushing, because
`make test` hard-errors without bats (`$(error bats not found)`) and `make lint` runs
`zsh -n` unconditionally, unlike `shellcheck` which is guarded by
`if [ -n "$(SHELLCHECK)" ]`. Its proposed remedy was to guard `zsh -n` the way shellcheck
already is.

Investigation on 2026-08-11 established that the row identifies a real symptom, attributes
it to the wrong cause, and omits a live defect sitting next to it.

### The reported failure has a precise, asymmetric cause

The failure was observed on a work Mac: `bats` absent, commits and pushes blocked. The
mechanism is a provisioning hole specific to macOS, not an over-strict gate.

```
lib/workflows.sh:132   if [[ ${MACOS} || ${UBUNTU} ]]; then install_zsh  || return 1; fi
lib/workflows.sh:140   if [[ -n ${LINUX} ]];            then install_bats || return 1; fi
```

`install_bats` (`lib/linux_shared.sh:23`) shells out to `apt-get` and has no macOS arm. On
a Mac, `bats` arrives solely through `install_macos_casks` → `brew bundle`
(`lib/macos.sh:136`), which runs only when `setup_env.sh:79` sees `SETUP_BREW` — that is,
only under the `--brew-install` flag.

The consequence: a Mac configured with `./setup_env.sh -t setup_user`, followed by
`make install-hooks`, has the gate installed and the tool the gate hard-requires absent.
Linux boxes never reach this state because they get the unconditional `install_bats` call.

The `# [HAS_DEVTOOLS]` tag on `Brewfile:15` is not implicated. That tag is read by
`_update_check_brewfile_drift` (`lib/update_summary.sh:616`) to decide which entries the
drift check should ignore on a machine lacking the capability. `brew bundle` does not read
it — it installs every entry in the file. A `mac_mini`-profile machine (`office`, `home-1`
in `config/profiles.sh`, capabilities `gui printing`) running `--brew-install` still gets
`bats-core`.

### `zsh -n` in `make lint` runs against files no zsh ever interprets

`SHELL_FILES` in the `Makefile` derives from:

```
git ls-files '*.sh' '*.bash' 'scripts/pre-push' 'scripts/commit-msg'
```

That is 36 files, none of which is zsh. The eight files zsh actually interprets — `.zshrc`
and `.config/.zshrc.d/*.zsh` — match none of those globs and are therefore not covered by
`make lint` at all.

Measured on this commit: `bash -n` and `zsh -n` were run over all 36 files. Both exit 0 on
every file; there is no divergence. The check contributes no findings today, and
structurally it can only ever fire on a construct that bash accepts and zsh rejects, in a
file carrying `#!/usr/bin/env bash` that zsh never executes — a false positive by
construction, not a defect discovered.

The eight real zsh files are zsh-syntax-checked, but by `tests/zshrc.d/unit.bats:14-47`
(eight `zsh -n` tests). That check therefore lives behind `bats`, not behind `make lint`.

`.github/workflows/ci.yml:56-61` repeats the same misdirection, selecting with
`find . -name '*.sh'`.

### One correction to the row's framing

The row describes the problem as newly reachable via the pre-push path. `make lint` is also
the pre-commit hook (`scripts/pre-commit-hook.sh`), so an unguarded `zsh -n` blocks
_commits_ as well as pushes, and has done so since the lint target was introduced
(`cf38fb4`). That half predates ADR-0017 entirely.

## Decision

Two changes, neither of which weakens a gate.

1. **Give macOS the same unconditional bats provisioning Linux already has.** The path that
   installs the gate becomes the path that installs what the gate needs.
2. **Point `zsh -n` at the files zsh interprets** — the eight zsh files — and remove it from
   the 36 bash files.

No `command -v` guards are added. `make lint` and `make test` stay fail-closed. Guarding
`bats` would make `make test` report success having run no tests, which is the fail-open
direction ADR-0017 rejected on 2026-08-01 and which `USER.md` rejects generally ("fail
closed on unknown; unknown ≠ safe"). Guarding `zsh` was considered and rejected as buying
nothing measurable: macOS ships `/bin/zsh`, and Ubuntu machines get zsh from both
`ubuntu_common_packages.txt:80` and `install_zsh`, so no fleet machine has ever lacked it.

## Implementation

### A. bats provisioning parity

`install_zsh` already implements the required shape — a platform dispatcher at
`lib/helpers.sh:254` delegating to `install_zsh_macos` / `install_zsh_linux`. The bats
change mirrors it exactly rather than inventing a second pattern.

| File                     | Change                                                                                                                                                                                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/linux_shared.sh:23` | Rename `install_bats` → `install_bats_linux`, for naming parity with `install_zsh_linux`. Body unchanged.                                                                                                                                       |
| `lib/macos.sh`           | New `install_bats_macos`, modelled on `install_zsh_macos` (`:115`): early return when `quiet_which bats` succeeds; install Homebrew if absent; `brew_install_formula bats-core`; `log_error` and `return 1` when Homebrew is still unavailable. |
| `lib/helpers.sh`         | New `install_bats()` dispatcher placed immediately after `install_zsh()` (ends `:260`), with the same `MACOS` / `LINUX` branch structure.                                                                                                       |
| `lib/workflows.sh`       | Delete the `if [[ -n ${LINUX} ]]` block at `:139-141`. Add `install_bats \|\| return 1` inside the existing `if [[ ${MACOS} \|\| ${UBUNTU} ]]` block at `:136`, beside `install_zsh`.                                                           |

The rename is a contract change for existing tests, not only for production code. `install_bats`
survives as a name but now means "dispatch by platform" rather than "apt-get install bats",
so any existing test invoking `install_bats` and asserting apt behavior must be repointed at
`install_bats_linux`. Enumerate the call sites before editing any of them —
`grep -rn 'install_bats' lib/ tests/ setup_env.sh` — and check each for whether it wants the
dispatcher or the Linux arm. This is the same discipline `shell.md`'s contract-widening entry
requires, applied to a rename rather than a return value.

The guard on the call site narrows from `LINUX` to `MACOS || UBUNTU`. `install_bats_linux`
invokes `apt-get`, so the existing `LINUX` guard promises coverage on non-Ubuntu Linux that
it cannot deliver — and on such a machine `apt-get` fails, `|| return 1` fires, and the
whole of `run_setup_user` aborts. Every Linux machine in the fleet runs Ubuntu 24.04, so
this changes no observable behavior; it removes a latent failure rather than adding scope.

### B. `zsh -n` scope

In `Makefile`, `SHELL_FILES` is unchanged and keeps `bash -n` and `shellcheck`. A second
derived list is added beside it, with the same `env -u` prefix (git exports `GIT_DIR` into
the pre-push hook environment when the push originates from a worktree, and this is a
parse-time assignment):

```make
ZSH_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.zsh' '.zshrc')
```

`zsh -n` moves out of the `SHELL_FILES` loop (`Makefile:46`) into its own loop over
`ZSH_FILES`. The empty-list refusal at `:38-42` becomes a refusal when _either_ list is
empty, checked independently so the message names which one: both lists are
`git ls-files`-derived and both go empty under the same conditions (git absent from `PATH`,
or a tree exported without `.git`), and a lint target that reports a pass having inspected
nothing is the failure that guard exists to prevent.

In `.github/workflows/ci.yml`, the zsh step at `:56-61` changes its selector from
`find . -name '*.sh'` to `git ls-files '*.zsh' '.zshrc'` — the same derivation the
`Makefile` uses, not a literal list of the eight paths, so CI and `make lint` cannot drift
apart as zsh files are added or removed. The `env -u` prefix is unnecessary there: the CI
job is a fresh checkout, not a hook invocation, so no `GIT_DIR` is inherited. The bash step
at `:49-54` is left alone: its `find`-versus-`git ls-files` inconsistency with the
`Makefile` is pre-existing and out of scope here, recorded so the omission reads as a
decision rather than an oversight.

### C. Error text

`Makefile` carries four identical `$(error bats not found. Install: brew install bats-core
(macOS) or sudo apt-get install bats (Linux))` strings at `:62`, `:79`, `:86`, `:107`. Each
names a one-shot install that fixes the immediate block and leaves the machine able to
drift back into the same state.

The text changes to lead with `./setup_env.sh -t setup_user` — the repo's own remedy, which
after change A also prevents recurrence — retaining the raw package-manager commands as a
fallback. This follows `USER.md`'s "under pressure, surface more, not less": the operator
hitting this is blocked and wants the fix that holds, not only the one that unblocks.

The four duplicates collapse into one variable holding **the message text only**,
referenced as `$(error $(BATS_MISSING))` at each of the four sites. `BATS_MISSING` is a
literal string with no function calls in it, so `:=` is used, matching the rest of the file.

The `$(error ...)` call itself is deliberately not moved into the variable. `$(error)`
fires wherever it is expanded, so a `:=` assignment containing it would abort every `make`
invocation at parse time regardless of target. A recursively-expanded `=` assignment would
technically work, deferring the call to each reference — but it produces a variable whose
mere expansion halts the build, which is a trap for the next reader for no gain over
sharing the string.

### D. Documentation

- `CLAUDE.md`, Key Conventions: retire "For shell syntax-only fixes in `setup_env.sh`,
  validate with both `bash -n setup_env.sh` and `zsh -n setup_env.sh` before commit." That
  line prescribes precisely the check being removed. Replace with the new split — `bash -n`
  for `.sh`/`.bash`/hooks, `zsh -n` for `.zsh`/`.zshrc`.
- `CLAUDE.md`, Testing: the `make lint` description ("bash -n + zsh -n on every tracked
  shell file") is no longer accurate.
- `docs/superpowers/README.md`: move the backlog row into the All Plans table.

## Testing

New coverage, in the existing suites (`tests/setup_env/install_functions.bats`,
`macos.bats`, `install_guards.bats`, `workflows.bats`):

- `install_bats_macos`: Homebrew present (installs), Homebrew absent and uninstallable
  (`return 1` propagates), bats already installed (early return, no install attempted).
  Idempotency — a second call after a successful first produces the same state.
- `install_bats` dispatcher: `MACOS` routes to the macOS arm, `LINUX` routes to the Linux
  arm, neither set is a no-op returning 0.
- `run_setup_user`: calls `install_bats` on macOS, and aborts when it fails. This is the
  assertion whose absence let the hole ship — the Linux path was covered, the macOS path
  did not exist to cover.
- Scope invariant, in a new `tests/scripts/makefile_lint_scope.bats` beside the existing
  `tests/scripts/pre_push.bats`: `ZSH_FILES` is non-empty, `SHELL_FILES` is non-empty, and
  the two are disjoint. The test re-derives both lists with the same `git ls-files`
  pathspecs the `Makefile` uses, run against the real repository with the mocks directory
  stripped from `PATH` (per `shell.md` — a `tests/mocks/git` stub would otherwise return an
  empty list and make every assertion vacuously true). Disjointness is the property that
  matters: it is what guarantees no file is handed to a parser that does not interpret it.
  The behavioral half of the zsh check already exists at
  `tests/zshrc.d/unit.bats:14-47` and is retained.

Mocks follow the existing `MOCK_*` conventions; no test may install a real package or reach
a real Homebrew. Per `tdd.md` E2, each test's _failing_ branch must be inert — a test for
`install_bats_macos` that regresses must not invoke a real `brew install`, so `HOME` and
`PATH` are redirected at `setup()` scope rather than relying on the mock alone.

## Verification

Run before implementation is considered complete. The first four depend on code not yet
written, so those expectations are predictions, not recorded results. The last row does not
depend on the change and was therefore run now, per `behavior.md`'s rule that a
verification command which can be executed at spec time must be executed rather than
predicted — its result is recorded, not guessed.

| Check                                                                               | Expectation                                                                                 |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `make lint`                                                                         | Exit 0. Output carries eight `zsh   OK` lines, none of them a `.sh`, `.bash`, or hook path. |
| Inject a zsh-invalid construct into `.config/.zshrc.d/7_final.zsh`, run `make lint` | Non-zero exit naming that file. Revert after.                                               |
| Inject a bash construct zsh rejects into a tracked `.sh` file, run `make lint`      | Exit 0 — demonstrates the false-positive surface is gone. Revert after.                     |
| `make test`                                                                         | Green. Test count above the CI floor of 840 (1274 at 2026-08-10, expected to rise).         |
| `git ls-files '*.zsh' '.zshrc' \| wc -l`                                            | **8 — measured 2026-08-11, not predicted.**                                                 |

The two injection checks are the ones that distinguish this change from a no-op: the first
proves the zsh check now reaches the zsh files, the second proves it no longer reaches the
bash files. A suite that only asserts `make lint` passes cannot tell either.

## Non-goals

- **No `command -v` guards** for `bats` or `zsh`. Both gates stay fail-closed.
- **The CI bash step's selector** stays on `find`. Aligning it with `git ls-files` is a
  separate, pre-existing inconsistency.
- **The duplication** between `make lint`'s zsh check and `tests/zshrc.d/unit.bats` is
  retained deliberately: they fire at different gates (pre-commit versus the suite), and the
  cost of running eight `zsh -n` invocations twice is negligible.
- **`shellcheck` coverage of the zsh files** is not added. ShellCheck cannot lint zsh; per
  `shell.md`, zsh gets `zsh -n` and human review, and nothing else.

## Risks

- **`brew_install_formula bats-core` on a machine without Homebrew.** Handled the same way
  `install_zsh_macos` handles it — attempt `install_homebrew`, and fail explicitly with
  `log_error` plus `return 1` if it is still unavailable. The `|| return 1` at the call site
  then aborts `run_setup_user` rather than continuing with a half-configured machine.
- **A machine already carrying bats from `brew bundle`.** The `quiet_which bats` early
  return makes the new call a no-op there, matching `install_bats_linux`'s existing guard.
- **`make lint` still hard-requires zsh** after this change, now for a justified reason. If
  a machine is ever found without zsh, that is a provisioning bug of the same class as the
  bats hole and gets the same treatment — not a guard.
