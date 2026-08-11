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

The failure was observed on a work Mac: `bats` absent, pushes blocked. The mechanism is a
provisioning hole specific to macOS, not an over-strict gate.

Note the precise blast radius: `make lint` carries no `BATS` guard, and all four
`$(error bats not found)` sites sit under `test` and `bash-coverage`. Missing bats therefore
blocks **pushes but not commits** — `make lint` is the pre-commit hook and does not need
bats. An earlier draft of this section said "commits and pushes"; that was wrong.

```
lib/workflows.sh:132   if [[ ${MACOS} || ${UBUNTU} ]]; then install_zsh  || return 1; fi
lib/workflows.sh:140   if [[ -n ${LINUX} ]];            then install_bats || return 1; fi
```

`install_bats` (`lib/linux_shared.sh:23`) shells out to `apt-get` and has no macOS arm. On a
Mac, `bats` arrives solely through `install_macos_casks` → `brew bundle`, which is reachable
by exactly two routes:

```
setup_env.sh:79   [[ -n ${SETUP_BREW:-} ]] && _run_or_exit run_brew_install
                    → lib/workflows.sh:300  install_macos_casks
setup_env.sh:84   [[ -n ${SETUP:-} || -n ${DEVELOPER:-} ]] && _run_or_exit run_setup_or_developer
                    → lib/workflows.sh:220  install_macos_packages
                    → lib/macos.sh:163        install_macos_casks
```

So `-t setup` and `-t developer` both install the Brewfile with **no flag at all**; only the
first route needs `--brew-install`. An earlier draft claimed `SETUP_BREW` was the sole
gate — that was false, and the second route was found by the goal-fit lens rather than by
the original investigation.

The consequence, stated at its true width: a Mac configured with `./setup_env.sh -t setup_user`
**and nothing else**, followed by `make install-hooks`, has the gate installed and the tool
the gate hard-requires absent. A Mac that has ever run `-t setup` or `-t developer` is
unaffected. Linux boxes never reach this state at all, because they get the unconditional
`install_bats` call.

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

Seven of the eight real zsh files are zsh-syntax-checked, by `tests/zshrc.d/unit.bats:15-45`
(**seven** `zsh -n` tests, covering `1_init` through `7_final`). That check lives behind
`bats`, not behind `make lint`.

The eighth — the root `.zshrc` — is checked by **nothing**. `grep -rn 'zsh -n' tests/
.github/ Makefile` returns no hit against it: it matches no `*.sh`/`*.bash` glob, has no
bats test, and the CI `find` selector misses it too. An earlier draft of this section said
"eight tests"; the real count is seven, and the discrepancy is not cosmetic — it means
change B is not the near-duplication it first appeared to be. For `.zshrc`, `make lint`
becomes the only zsh syntax coverage that exists.

One thing pulls the other way and must be handled in the same change:
`tests/setup_env/workflows.bats:283` asserts `zsh -n "${REPO_ROOT}/setup_env.sh"` — the
false-positive surface described above, pinned as a test. It was added in `5142258` (#189)
alongside a `bash -n` assertion on the same file, and the commit's own log line reads
"passes bash -n **and** zsh -n with the git_hooks.sh source line". `git show 5142258 -- setup_env.sh`
shows a single added `source` line and no zsh-driven edit, so it is convention compliance
rather than a regression guard for a parse failure that shipped. It is retired by this
change; leaving it would have the suite enforcing a rule the gate and `CLAUDE.md` no longer
state.

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
| `lib/workflows.sh`       | Delete the `if [[ -n ${LINUX} ]]` block at `:139-141`. Add `install_bats \|\| return 1` inside the existing `if [[ ${MACOS} \|\| ${LINUX} ]]` block at `:136`, beside `install_zsh`.                                                            |
| `lib/workflows.sh`       | New `install_bats` step in `run_update`, with a matching `"bats"` entry in `_UPDATE_SECTION_ORDER` (`lib/update_summary.sh`). See below — this is what makes the fix reach machines that are already broken.                                    |

The rename is a contract change for existing tests, not only for production code. `install_bats`
survives as a name but now means "dispatch by platform" rather than "apt-get install bats",
so any existing test invoking `install_bats` and asserting apt behavior must be repointed at
`install_bats_linux`. Enumerate the call sites before editing any of them —
`grep -rn 'install_bats' lib/ tests/ setup_env.sh` — and check each for whether it wants the
dispatcher or the Linux arm. This is the same discipline `shell.md`'s contract-widening entry
requires, applied to a rename rather than a return value.

**The call-site guard stays `MACOS || LINUX` — it is deliberately not narrowed to `UBUNTU`.**
An earlier draft narrowed it, on the reasoning that `install_bats_linux` invokes `apt-get`
and so cannot deliver on non-Ubuntu Linux anyway. The risk lens established that this is the
wrong direction: `readonly UBUNTU=1` is set only when `/etc/os-release` `NAME` is exactly
`"Ubuntu"` (`lib/detect_env.sh:10-11`), so on any other Linux the narrowed guard **skips the
call silently** — hooks still install at `lib/workflows.sh:206`, bats is absent, and nothing
reports it. That is precisely the failure this spec exists to fix, reproduced on the other
platform. The unnarrowed `LINUX` guard instead lets `apt-get` fail loudly and `|| return 1`
abort the run, which is the correct direction under `USER.md`'s "fail closed on unknown".

The fleet is entirely Ubuntu 24.04, so neither choice changes observable behavior today. The
argument is about which way the latent case fails, not about which is currently exercised.

#### The `run_update` step, and why it is not optional

`install_bats` is reachable only from `run_setup_user`. `-t update` — the command the fleet
actually runs on cadence — never calls it. Without a second call site, change A is inert on
every machine already in the broken state: the work Mac that motivated this spec stays broken
after the PR merges, and change C's one-shot fallback unblocks the operator without ever
closing the hole. `-t setup_user` is a provisioning-time command here, not a cadence one.

So `run_update` gains an `install_bats` step. Two couplings from `CLAUDE.md` apply and are
easy to get wrong:

- The step must be recorded with `_update_record_start`/`_update_record_end` **and** have a
  matching entry added to `readonly _UPDATE_SECTION_ORDER` in `lib/update_summary.sh`.
  Adding the former without the latter means the section is tracked internally and never
  printed, with no error — the same trap the `git-hooks` and `git-repos` sections document.
- `install_bats` returns 0 or 1, not a tri-state, so the `run_update` call site needs no
  rc-mapping of the kind `install_git_hooks_all_repos` requires. Stated explicitly because
  the adjacent sections in that function do map, and copying their shape would be wrong here.

The `quiet_which bats` early return makes the update-path call a no-op on every machine that
already has bats, which is all of them except the affected class.

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

The text **leads with the one-shot** — `brew install bats-core` on macOS,
`sudo apt-get install bats` on Linux, both correct on every fleet platform — and names
`./setup_env.sh -t setup_user` second as the durable fix.

An earlier draft inverted that order, on the reasoning that the durable remedy should come
first. The ergonomics lens established why it is wrong: `run_setup_user` is a ~20-step
provisioning run that, after `install_bats`, performs an unconditional `git pull` in the
operator's own dotfiles checkout and calls `setup_claude_mcp` (which the global `CLAUDE.md`
warns overwrites tracked `~/.claude/mcp.json` when `GITHUB_PAT` is set), then sweeps
`install_git_hooks_all_repos` across every repo. `setup_env.sh:83` runs it under
`_run_or_exit`, so the first failure exits. An operator reads this message _because a push
was blocked_ — meaning unpushed local commits and possibly a dirty tree — and the WSL2
backup-of-last-resort is reached under exactly that pressure. Leading with the heavy path
there is the wrong shape.

Both remedies still appear, so this satisfies "surface more, not less" without making the
emergency path the expensive one.

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
- `tests/setup_env/workflows.bats:282-284`: retire the
  `@test "setup_env.sh passes zsh -n with the git_hooks.sh source line"` assertion. It is
  the last remaining enforcement of `zsh -n` on a bash file; leaving it would have the suite
  requiring a rule that the gate and `CLAUDE.md` both stop stating in this same change. The
  `bash -n` assertion immediately above it at `:278` stays.
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
- `run_update`: calls `install_bats`, records the section, and the section appears in the
  printed summary. The last clause is the one that matters — a `_update_record_*` pair
  without its `_UPDATE_SECTION_ORDER` entry tracks silently and prints nothing, so asserting
  only that the call happened would pass over exactly that bug.
- Scope, in a new `tests/scripts/makefile_lint_scope.bats` beside the existing
  `tests/scripts/pre_push.bats`: **run `make lint` and assert on its output** — a `zsh` line
  for `.zshrc`, and **zero** `zsh` lines whose path matches `*.sh`, `*.bash`, or a hook.

  An earlier draft specified this test as "`ZSH_FILES` non-empty, `SHELL_FILES` non-empty,
  and the two disjoint," with both lists re-derived from the same `git ls-files` pathspecs
  the `Makefile` uses. Goal-fit and Risk independently established that such a test cannot
  fail. Disjointness is a tautology of the pathspec sets — no filename matches both `'*.sh'`
  and `'*.zsh'`, so `comm -12` over them returns nothing regardless of what the `Makefile`
  says. Non-emptiness is preempted by `test: lint`, which exits at the `Makefile`'s own
  empty-list refusal before bats ever runs. And because the test re-derived the pathspecs
  itself rather than reading `ZSH_FILES`, the single drift it could plausibly have caught —
  someone editing the `Makefile` pathspec — was invisible to it.

  Asserting on `make lint`'s output fixes all three: it reads the `Makefile`'s real
  variables, it pins the specific file `.zshrc` rather than a cardinality, and it goes red
  if the scope is ever narrowed back. Run it with the mocks directory stripped from `PATH`
  (per `shell.md`), since a `tests/mocks/git` stub would otherwise empty both lists and make
  every assertion vacuously true.

  The behavioral half for the seven `.zshrc.d` files already exists at
  `tests/zshrc.d/unit.bats:15-45` and is retained.

Mocks follow the existing `MOCK_*` conventions; no test may install a real package or reach
a real Homebrew. Per `tdd.md` E2, each test's _failing_ branch must be inert — a test for
`install_bats_macos` that regresses must not invoke a real `brew install`, so `HOME` and
`PATH` are redirected at `setup()` scope rather than relying on the mock alone.

## Verification

Run before implementation is considered complete. Rows 1-5 depend on code not yet written,
so those expectations are predictions, not recorded results. Row 6 does not depend on the
change and was therefore run now, per `behavior.md`'s rule that a verification command which
can be executed at spec time must be executed rather than predicted — its result is
recorded, not guessed.

| Check                                                                               | Expectation                                                                                       |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `make lint`                                                                         | Exit 0. Output carries eight `zsh   OK` lines, none of them a `.sh`, `.bash`, or hook path.       |
| Inject a zsh-invalid construct into `.config/.zshrc.d/7_final.zsh`, run `make lint` | Non-zero exit naming that file. Revert after.                                                     |
| Inject a bash construct zsh rejects into a tracked `.sh` file, run `make lint`      | Exit 0 — the false-positive surface is gone. Revert after.                                        |
| **Inject a bash-INVALID construct into a tracked `.sh` file, run `make lint`**      | **Non-zero exit naming that file. Proves the surviving `bash -n` loop still inspects something.** |
| `make test`                                                                         | Green. Test count above the CI floor of 840 (1274 at 2026-08-10, expected to rise).               |
| `git ls-files '*.zsh' '.zshrc' \| wc -l`                                            | **8 — measured 2026-08-11, not predicted.**                                                       |

Rows 2-4 are the ones that distinguish this change from a no-op, and row 4 exists because
rows 2-3 alone cannot. Row 3 passes identically whether `zsh -n` was correctly removed from
the `SHELL_FILES` loop **or** the whole loop was broken and `bash -n` now inspects zero
files — an all-PASS suite cannot tell a correct measurement from an absent one. Row 4 pins
the surviving half of `Makefile:44-48` to a specific non-zero result. Added after the lens
review counted the verdicts and found five of five rows unable to fail in that direction.

## Non-goals

- **No `command -v` guards** for `bats` or `zsh`. Both gates stay fail-closed.
- **The CI bash step's selector** stays on `find`. Aligning it with `git ls-files` is a
  separate, pre-existing inconsistency.
- **The partial overlap** between `make lint`'s zsh check and `tests/zshrc.d/unit.bats` is
  retained deliberately: they fire at different gates (pre-commit versus the suite), and the
  cost of running seven `zsh -n` invocations twice is negligible. An earlier draft called
  this "duplication" outright, which was wrong for the eighth file — `.zshrc` has no `zsh -n`
  anywhere today, so `make lint` becomes its only coverage rather than a second copy of
  existing coverage.
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
- **A platform-dependent test break from the rename.**
  `tests/setup_env/install_guards.bats:127,136` export `UBUNTU=1` without unsetting `MACOS`.
  Once `install_bats` becomes a dispatcher branching on `MACOS` first, those tests take the
  macOS arm on all three work Macs, the Mac Studio and the laptop, while still passing on
  the Linux box and on `ubuntu-latest` CI. The failure is therefore invisible to CI and
  visible only locally — the inverse of the usual asymmetry, and worth naming because
  `scripts/pre-push` runs `make test`, so it blocks pushes from every Mac in the fleet.
  Fix by `unset MACOS` in those tests, per `tdd.md`'s test-isolation rule that a test must
  set up all state it depends on rather than inheriting it.

## Multi-Lens Review

Reviewed at commit: `4cbccc4` (Step 7 self-review commit, before Step 8 dispatch)

Three lenses dispatched as independent subagents with no access to the brainstorming
conversation. Two returned findings that falsify claims in the body above; those claims are
left standing in the text so the disposition record shows what was corrected and why.

### Resolved contradiction between lenses

Goal-fit and Risk returned **opposite** verdicts on the spec's Context claim that
`brew bundle` on a Mac runs only under `--brew-install`. Risk called the premise confirmed;
Goal-fit called the second half false. Resolved by direct measurement rather than by
preferring a lens:

```
lib/macos.sh:147     install_macos_packages()
lib/macos.sh:163       install_macos_casks || return 1      # in the brew-present else-branch
lib/workflows.sh:220   install_macos_packages || return 1   # in run_setup_or_developer
setup_env.sh:84        [[ -n ${SETUP:-} || -n ${DEVELOPER:-} ]] && _run_or_exit run_setup_or_developer
```

**Goal-fit is correct; Risk is wrong.** `-t setup` and `-t developer` both reach
`install_macos_casks` with no flag. The hole is real but narrower than the Context section
states: it is specific to a Mac provisioned with `-t setup_user` **only**. The Context
sentence at `:29-32` is wrong as written and must be corrected before implementation.

Recorded because it is the load-bearing lesson: three same-model lenses over shared framing
can disagree on a checkable fact, and lens agreement is not confirmation. Only the command
settles it.

### Goal-Fit

Finding: Change A is worth building, but the persistent test the spec adds cannot fail, so
nothing outside this document holds the change in place. `tests/scripts/makefile_lint_scope.bats`
(`:195-201`) asserts non-empty plus disjointness; disjointness is a tautology of the two
pathspec sets — no filename matches both `'*.sh'` and `'*.zsh'` — and because the test
re-derives the pathspecs itself rather than reading `ZSH_FILES`, the one drift it could
plausibly catch (someone editing the Makefile pathspec) is invisible to it. Non-empty is
additionally preempted by `test: lint`, which exits at the Makefile's own empty-list refusal
before bats runs. Replacement: invoke `make lint` and assert its output contains a `zsh`
line for `.zshrc` and **zero** `zsh` lines matching `*.sh`. Separately, `:63-64` claims eight
existing `zsh -n` tests; there are seven, and the root `.zshrc` has none anywhere — so change
B closes a real gap rather than duplicating the suite, and the Non-goals framing at `:235-237`
is wrong for that file. Also, `tests/setup_env/workflows.bats:283` still asserts `zsh -n` on
`setup_env.sh`, so the "false-positive surface is gone" framing at `:222` does not hold unless
that test is retired in the same change.

Assumption: that change A reaches the machines already broken. `install_bats` is called only
from `run_setup_user`; `-t update` never touches it, so the fix is inert on the motivating
work Mac until someone re-runs `-t setup_user` there — and change C's retained one-shot
fallback unblocks the operator without ever closing the hole. Settled by one question: is
`-t setup_user` re-run on existing machines as a matter of practice, or only at provisioning
time? If the latter, `install_bats` needs a `run_update` section with its
`_UPDATE_SECTION_ORDER` entry.

Disposition: **Addressed.** The assumption was put to the operator and settled against it:
`-t setup_user` is a provisioning-time command on this fleet, not a cadence one. §A gains an
`install_bats` step in `run_update` with its `_UPDATE_SECTION_ORDER` entry, so the fix
reaches machines already in the broken state. The unfailable
`tests/scripts/makefile_lint_scope.bats` was replaced with a `make lint`-output assertion,
the 7-vs-8 test count corrected, and the Non-goals "duplication" framing rewritten — `.zshrc`
has no `zsh -n` anywhere today, so change B closes a gap rather than duplicating.

### Ergonomics

Finding: §C's remedy ordering (`:156-159`) is disproportionate and can fail in exactly the
state that produces the error. `run_setup_user` is a ~20-step provisioning run that, after
`install_bats`, performs an unconditional `git pull` in the operator's own checkout and
touches `setup_claude_mcp` (which the global `CLAUDE.md` warns overwrites tracked
`~/.claude/mcp.json` when `GITHUB_PAT` is set). An operator sees this message _because a push
was blocked_ — unpushed commits, possibly a dirty tree. Invert §C: lead with the one-shot
(`brew install bats-core` / `sudo apt-get install bats`, both correct on every fleet
platform), name `./setup_env.sh -t setup_user` second as the durable fix. Also corrects a
scope claim: `make lint` has no `BATS` guard and the four `$(error)` sites are under
`test`/`bash-coverage` only, so missing bats blocks **pushes but not commits** — the Context
section's framing of the observed failure overstates it. Verification table needs a sixth
row: inject a _bash_-invalid construct into a `.sh` and demand non-zero, because row 3 passes
identically whether `zsh -n` was correctly removed or the whole `SHELL_FILES` loop broke and
`bash -n` now inspects nothing.

Assumption: that the work Mac was provisioned via `-t setup_user` and never via a path that
runs `brew bundle` — i.e. bats was absent because the Brewfile never ran, not because it ran
and `bats-core` later disappeared. Settled on that machine with `brew list --formula | wc -l`
and `brew list bats-core`: 100+ formulae present with `bats-core` missing refutes the stated
cause.

Disposition: **Addressed.** §C's remedy order inverted — one-shot first, `-t setup_user`
second. The Context section's "commits and pushes blocked" corrected to pushes only, and a
sixth verification row added pinning a bash-invalid injection to a non-zero result.

The assumption itself is **not settled** and is carried forward as an open item: the
`brew list --formula | wc -l` check has to run on the affected work Mac, which is not this
machine. It does not block implementation — the `-t setup_user`-only hole is confirmed to
exist by code inspection regardless of which machine hit it — but if that Mac turns out to
carry a full Brewfile with `bats-core` missing, the stated cause is wrong and this spec
fixes a real hole that is not the one that bit. Run it before closing the PR.

### Risk

Finding: two items, one refuted and one upheld.

**Refuted by evidence the lens itself named.** Risk argued `tests/setup_env/workflows.bats:282`
is a committed regression guard proving a bash file _did_ once fail `zsh -n`, which would make
the "false positive by construction" claim false. Checked `git show 5142258`: the commit adds
exactly one line to `setup_env.sh` — `source "$(dirname "${BASH_SOURCE[0]}")/lib/git_hooks.sh"` —
and its own log line reads "test: setup_env.sh passes bash -n **and** zsh -n with the
git_hooks.sh source line", paired with the `bash -n` test immediately above at `:278`. No
zsh-driven change to `setup_env.sh`, no incident. Convention-compliance, not a regression
guard. The structural claim survives — but Risk's downstream point stands independently and
matches Goal-fit: leaving that test in place while removing the Makefile line leaves the repo
asserting a rule in the suite that it deleted from the gate and from `CLAUDE.md`.

**Upheld, and it reverses a decision in §A.** Narrowing the call-site guard from `LINUX` to
`UBUNTU` converts a loud failure into a silent skip on any non-Ubuntu Linux: `readonly UBUNTU=1`
is set only when `/etc/os-release` `NAME` is exactly `"Ubuntu"` (`lib/detect_env.sh:10-11`), so
elsewhere the call is skipped, hooks still install at `lib/workflows.sh:206`, and bats is absent
with no error. That is precisely the failure this spec exists to fix, newly reproduced on Linux.
Low probability given the fleet; wrong direction regardless. Also flags
`tests/setup_env/install_guards.bats:127,136`, which export `UBUNTU=1` without unsetting
`MACOS` — post-rename the dispatcher takes the macOS arm first, so those tests fail on all
three Macs while passing on the Linux box and on `ubuntu-latest` CI.

Assumption: refuted above by `git show 5142258`. No further uncertain assumption named.

Disposition: **Addressed.** The `LINUX` → `UBUNTU` narrowing is reversed — §A now keeps
`MACOS || LINUX` and states why the narrowed form fails in the wrong direction.
`tests/setup_env/workflows.bats:282-284` is retired in §D. The
`install_guards.bats:127,136` `MACOS`-leak is recorded under Risks with its fix.

Worth recording that this lens's headline finding was **wrong** and its secondary finding
was the most valuable single result of the round. A lens whose lead argument fails
verification is not a lens to discount.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. No arm-versus-arm design,
no judge component, and the acceptance criteria are exit codes and file counts rather than
ambiguous ones.
