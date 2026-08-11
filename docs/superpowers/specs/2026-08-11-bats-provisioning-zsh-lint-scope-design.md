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

That is 36 files, none of which is zsh. The **nine** files zsh actually interprets —
`.zshrc`, the seven `.config/.zshrc.d/*.zsh`, and `bruce.zsh-theme` — match none of those
globs and are therefore not covered by `make lint` at all.

Measured on this commit: `bash -n` and `zsh -n` were run over all 36 files. Both exit 0 on
every file; there is no divergence. The check contributes no findings today, and
structurally it can only ever fire on a construct that bash accepts and zsh rejects, in a
file carrying `#!/usr/bin/env bash` that zsh never executes — a false positive by
construction, not a defect discovered.

Seven of the nine are zsh-syntax-checked, by `tests/zshrc.d/unit.bats:15-45` (**seven**
`zsh -n` tests, covering `1_init` through `7_final`). That check lives behind `bats`, not
behind `make lint`.

**The other two — the root `.zshrc` and `bruce.zsh-theme` — are checked by nothing.**
`grep -rn 'zsh -n' tests/ .github/ Makefile` returns no hit against either: neither matches
a `*.sh`/`*.bash` glob, neither has a bats test, and the CI `find` selector misses both.
`bruce.zsh-theme` is symlinked live into `~/.oh-my-zsh/custom/themes/` by
`lib/helpers.sh:678`.

Two earlier drafts got this count wrong in two different ways — first claiming eight
existing `zsh -n` tests when there are seven, then claiming eight zsh files when there are
nine. Neither error is cosmetic. Together they mean change B is not the near-duplication it
first appeared to be: for two of the nine files, this is the first zsh syntax coverage that
has ever existed.

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
2. **Point `zsh -n` at the files zsh interprets** — the nine zsh files — and remove it from
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

| File                       | Change                                                                                                                                                                                                                                          |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/linux_shared.sh:23`   | Rename `install_bats` → `install_bats_linux`, for naming parity with `install_zsh_linux`. Body unchanged.                                                                                                                                       |
| `lib/macos.sh`             | New `install_bats_macos`, modelled on `install_zsh_macos` (`:115`): early return when `quiet_which bats` succeeds; install Homebrew if absent; `brew_install_formula bats-core`; `log_error` and `return 1` when Homebrew is still unavailable. |
| `lib/helpers.sh`           | New `install_bats()` dispatcher placed immediately after `install_zsh()` (ends `:260`), with the same `MACOS` / `LINUX` branch structure.                                                                                                       |
| `lib/workflows.sh:135-137` | Change that block's guard **in place**, from `if [[ -n ${LINUX} ]]` to `if [[ ${MACOS} \|\| ${LINUX} ]]`. It keeps its own block. Do **not** fold `install_bats` into the `install_zsh` block above it.                                         |
| `Brewfile:15`              | Remove the `# [HAS_DEVTOOLS]` tag from `brew "bats-core"`. See §E — this is what makes the gap visible on machines already in the broken state.                                                                                                 |

The rename is a contract change for existing tests, not only for production code. `install_bats`
survives as a name but now means "dispatch by platform" rather than "apt-get install bats",
so any existing test invoking `install_bats` and asserting apt behavior must be repointed at
`install_bats_linux`. Enumerate the call sites before editing any of them —
`grep -rn 'install_bats' lib/ tests/ setup_env.sh` — and check each for whether it wants the
dispatcher or the Linux arm. This is the same discipline `shell.md`'s contract-widening entry
requires, applied to a rename rather than a return value.

#### `install_bats` keeps its own block, and the guard question has a third answer

Two earlier drafts got this wrong in opposite directions, so the reasoning is recorded in
full.

The first narrowed the guard to `UBUNTU` on the grounds that `install_bats_linux` shells out
to `apt-get`. The risk lens objected: `readonly UBUNTU=1` is set only when `/etc/os-release`
`NAME` is exactly `"Ubuntu"` (`lib/detect_env.sh:10-11`), so on any other Linux a narrowed
guard **skips the call silently** while hooks still install at `lib/workflows.sh:206` — the
same failure this spec exists to fix, reproduced on the other platform.

The second draft therefore un-narrowed it and claimed the `LINUX` guard "lets `apt-get` fail
loudly and `|| return 1` abort the run, which is the correct direction." **That is wrong
too**, and the round-2 risk lens showed why: the call site sits at `:135-137`, _ahead of_
`clone_or_update_dotfiles`, `setup_dotfile_symlinks`, and `install_git_hooks_all_repos`
(`:206`). Aborting there does not leave a provisioned machine with a loud bats error — it
leaves an **unprovisioned** machine with no symlinks and no hooks. The narrowed form's
failure (hooks present, bats absent, pushes blocked) is recoverable in thirty seconds; the
un-narrowed form's is not. The real trade is which half of the machine you lose, not
fail-open versus fail-closed, and the second draft presented a weak argument as settled.

Neither is exercised: every Linux machine in the fleet is Ubuntu 24.04.

The resolution takes neither horn. The **call site** keeps `MACOS || LINUX`, matching the
dispatcher's own branch structure, and `install_bats_linux` gains a distro check at its top:
when `UBUNTU` is unset it emits `log_warn` naming the manual remedy and returns **0**. That
is a _loud skip_ — no silent gap, no unprovisioned machine, no abort. The fleet-wide silence
that motivated this whole spec came from a missing call, not from a call that warned.

Returning 0 for "did not install" is a deliberate, bounded exception to `USER.md`'s
fail-closed default: the condition is not unknown, it is precisely identified and reported,
and the alternative costs an unprovisioned machine on a path no fleet member takes.

#### Why there is no `run_update` step

An earlier draft added `install_bats` to `run_update`, reasoning that `-t setup_user` is
provisioning-time and so change A would never reach a machine already broken. All three
round-2 lenses opposed it, and the objections hold:

- **It inverts the contract every comparable section keeps.** `lib/workflows.sh:565-590` —
  tfenv, oh-my-zsh, tpm — all _skip_ what is absent (`_update_skip "<name>" "not installed"`).
  A bats section would be the only one that installs something absent, deviating exactly in
  the case where it does anything at all.
- **No `UPDATE_*` flag group fits.** Every section at `:323-480` is gated
  `[[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_X:-} ]]`. `UPDATE_BREW` is wrong on Linux and
  `UPDATE_PKGS` is wrong on macOS, so an unguarded step means `-t update --claude-only` — a
  deliberately narrow, fast flag — shells out to Homebrew or `sudo apt-get`.
- **The failure disposition is hazardous.** `setup_env.sh:86` runs `run_update` under
  `_run_or_exit`. A copied `|| return 1` aborts the whole update before pip, gems, git-repos
  and the hooks sweep; on macOS `install_bats_macos` can reach `install_homebrew`, which runs
  `xcode-select --install` and `sudo xcodebuild -license accept` on the cadence path.
- **It may not reach the target anyway.** A machine provisioned with `-t setup_user` only is
  by construction one nobody ran the fuller commands on; assuming it is on the update cadence
  is the same optimism that produced the hole.

§E does the reaching instead, at a fraction of the risk.

### E. Untag `bats-core` in the Brewfile

`run_update` already calls `_update_check_brewfile_drift` (`lib/workflows.sh:635`), which
reports `Missing (in Brewfile, not installed)` into the printed summary and
`~/.dotfiles-update.log`. It is a real consumer, already wired to the cadence command, and it
is silent about `bats-core` for exactly one reason:

```
lib/update_summary.sh   _brewfile_parse_section:
  _cap=$(_brewfile_extract_cap "${_line}")
  if [[ -n "${_cap}" ]] && [[ -z "${!_cap:-}" ]]; then continue; fi
```

`Brewfile:15` carries `# [HAS_DEVTOOLS]`, and `office`/`home-1` are `mac_mini`
(`config/profiles.sh`), whose capabilities are `gui printing`. So the entry is dropped from
the drift comparison entirely on precisely the machines that lack bats, and can never appear
under "Missing".

Removing the tag is one line, uses a consumer that already exists, and respects the
report-don't-install contract §A's rejected `run_update` step violated.

**The tag is also simply wrong on its own terms.** `run_setup_user` installs git hooks
unconditionally (`lib/workflows.sh:206`), so a `mac_mini` machine is expected to run
`make test` on every push — which means it needs bats, which means `bats-core` is not a
devtools-optional formula. An earlier draft of this spec declared the tag "not implicated"
because `brew bundle` ignores it. That is true for _installing_ and irrelevant for
_detecting_, and detection is the half that reaches an already-broken machine.

This does not install anything. It makes the next `-t update` on every Mac name the gap, with
change C's error text naming the fix. Provisioning is §A's job; §E's job is that the gap
stops being invisible.

### B. `zsh -n` scope

In `Makefile`, `SHELL_FILES` is unchanged and keeps `bash -n` and `shellcheck`. A second
derived list is added beside it, with the same `env -u` prefix (git exports `GIT_DIR` into
the pre-push hook environment when the push originates from a worktree, and this is a
parse-time assignment):

```make
ZSH_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.zsh' '*.zsh-theme' '.zshrc')
```

**`'*.zsh-theme'` is in that pathspec because leaving it out reproduced this spec's own
subject.** Two drafts used `'*.zsh' '.zshrc'` and reported "8 files" as a measured fact.
There are **nine** tracked zsh files: `bruce.zsh-theme` matches neither pattern, and
`lib/helpers.sh:678` symlinks it live into `~/.oh-my-zsh/custom/themes/`, where zsh
interprets it. A spec whose Context section is about a syntax check aimed at the wrong files
aimed its own replacement pathspec at the wrong files, and the verification row written to
catch that measured the pathspec against its own output — so it returned 8 and read as
confirmation. This is verbatim `shell.md`'s pathspec pitfall ("assert the derived count
equals the tracked count"), which is cited elsewhere in this very document.

Severity is low in itself — the theme passes `zsh -n` today and `ZSH_THEME="bruce"` is
commented out at `.config/.zshrc.d/3_oh_my_zsh.zsh:7` — but the omission is the same defect
class the change exists to remove.

`zsh -n` moves out of the `SHELL_FILES` loop (`Makefile:46`) into its own loop over
`ZSH_FILES`. The empty-list refusal at `:38-42` becomes a refusal when _either_ list is
empty, checked independently so the message names which one: both lists are
`git ls-files`-derived and both go empty under the same conditions (git absent from `PATH`,
or a tree exported without `.git`), and a lint target that reports a pass having inspected
nothing is the failure that guard exists to prevent.

The `Makefile` also gains a one-line introspection target so tests can read the real
variables rather than re-deriving them:

```make
print-%: ; @printf '%s\n' "$($*)"
```

In `.github/workflows/ci.yml`, the zsh step at `:56-61` changes its selector from
`find . -name '*.sh'` to `git ls-files '*.zsh' '*.zsh-theme' '.zshrc'` — the same derivation
the `Makefile` uses, not a literal list of paths, so CI and `make lint` cannot drift apart as
zsh files are added or removed. The `env -u` prefix is unnecessary there: the CI job is a
fresh checkout, not a hook invocation, so no `GIT_DIR` is inherited. The bash step at
`:49-54` is left alone: its `find`-versus-`git ls-files` inconsistency with the `Makefile` is
pre-existing and out of scope here, recorded so the omission reads as a decision rather than
an oversight.

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
- `_update_check_brewfile_drift`: with `HAS_DEVTOOLS` unset, `bats-core` **appears** in the
  parsed Brewfile formula set. This is §E's whole mechanism, and it is the assertion that
  fails if anyone re-adds the tag. Drive it through the existing `_OVERRIDE_BREWFILE_PATH`
  seam (`lib/update_summary.sh:617`) with a fixture Brewfile, so the test does not depend on
  the real file's contents.
- Scope, in a new `tests/scripts/makefile_lint_scope.bats` beside the existing
  `tests/scripts/pre_push.bats`, asserting against `make print-ZSH_FILES` and
  `make print-SHELL_FILES` — the `Makefile`'s **own** variables:
  - `ZSH_FILES` equals the tracked zsh set, compared as a set against
    `git ls-files '*.zsh' '*.zsh-theme' '.zshrc'` — nine paths today, named individually
    rather than counted, so adding a zsh file with an unmatched extension turns it red
    instead of silently passing at a new cardinality.
  - `SHELL_FILES` contains no path from `ZSH_FILES`, and `ZSH_FILES` no path from
    `SHELL_FILES`.
  - Both non-empty.

  Two earlier designs for this test were rejected, both for being unfailable:

  1. _Re-derive both pathspecs in the test and assert disjointness._ Disjointness is a
     tautology of the pathspec sets — no filename matches both `'*.sh'` and `'*.zsh'` — so
     `comm -12` returns nothing regardless of what the `Makefile` says. And re-deriving meant
     the one drift it could catch, a `Makefile` pathspec edit, was invisible to it.
  2. _Shell out to `make lint` and assert on its output._ Measured: `make lint` takes
     **14.7s**, and `test: lint` already runs it, so every `make test` — every pre-push, on
     seven machines — would pay it twice. It also goes red for any lint finding anywhere in
     the repo, so a scope test would fail for scope-unrelated reasons. And a loose grep for
     `zsh` near `.zshrc` is satisfied by a `zsh  FAIL .zshrc` line, so the test would pass on
     a machine where zsh is broken.

  `make print-%` reads the real variables, costs milliseconds, is immune to unrelated lint
  findings, and cannot be satisfied by a FAIL line. Run it with the mocks directory stripped
  from `PATH` (per `shell.md`), since a `tests/mocks/git` stub would otherwise empty both
  lists and make every assertion vacuously true.

- Behavioral zsh coverage for the two files no suite currently reaches: `zsh -n` on `.zshrc`
  and on `bruce.zsh-theme`, added to `tests/zshrc.d/unit.bats` beside the seven existing
  `.zshrc.d` tests at `:15-45`. Cheap, direct, and independent of `make lint`.

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

**Injection procedure, for rows 2-4.** Inject into **`bruce.zsh-theme`** for the zsh rows,
not into `.config/.zshrc.d/*.zsh`. Those files are symlinked live into `$HOME`
(`~/.config/.zshrc.d` → the repo), so a deliberate syntax error there breaks every new
interactive shell on the machine the instant it is written. `bruce.zsh-theme` is symlinked
too, but is **not sourced** — `ZSH_THEME="bruce"` is commented out at
`.config/.zshrc.d/3_oh_my_zsh.zsh:7` — so a broken copy is inert. Restore with an explicit
`git checkout -- <path>` after each row; "revert after" as a bare instruction is how a
half-finished verification leaves a broken shell config behind. Verify the tree is clean
(`git status --short`) before moving to the next row.

| Check                                                                                                        | Expectation                                                                                                     |
| ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `make lint`                                                                                                  | Exit 0. Output carries nine `zsh   OK` lines, none of them a `.sh`, `.bash`, or hook path.                      |
| Inject a zsh-invalid construct into `bruce.zsh-theme`, run `make lint`                                       | Non-zero exit, and a `zsh  FAIL bruce.zsh-theme` line in the output. `git checkout -- bruce.zsh-theme`.         |
| Inject a bash construct zsh rejects into a tracked `.sh` file                                                | `make lint` exit 0 — the false-positive surface is gone. `git checkout -- <path>`.                              |
| **Inject a bash-INVALID construct into a tracked `.sh` file**                                                | **A `bash FAIL <path>` line in `make lint`'s output.** Not the exit code — see below. `git checkout -- <path>`. |
| `make test`                                                                                                  | Green. Test count above the CI floor of 840 (1274 at 2026-08-10, expected to rise).                             |
| `diff <(make print-ZSH_FILES \| tr ' ' '\n' \| sort) <(git ls-files '*.zsh' '*.zsh-theme' '.zshrc' \| sort)` | Empty. **Replaces a row that counted `git ls-files '*.zsh' '.zshrc'` and asserted 8 — see below.**              |

Rows 2-4 distinguish this change from a no-op; row 4 exists because rows 2-3 alone cannot.
Row 3 passes identically whether `zsh -n` was correctly removed from the `SHELL_FILES` loop
**or** the whole loop was broken and `bash -n` now inspects zero files — an all-PASS suite
cannot tell a correct measurement from an absent one.

**Row 4 asserts on the output line, not on the exit code, and that distinction is the second
defect a correction introduced in this review.** Round 1 counted the verdicts, found every
row unable to fail in that direction, and added row 4 pinning "non-zero exit". Round 2
showed that version was equally unfailable: a bash-syntax-invalid `.sh` file also fails
`shellcheck`, and `Makefile:44-48` sets `failed=1` and continues, so `make lint` exits
non-zero whether or not the `bash -n` loop still runs. Only the `bash FAIL <path>` token
proves that specific loop inspected that specific file.

The last row replaces one that read `git ls-files '*.zsh' '.zshrc' | wc -l` → 8 and was
labelled _measured, not predicted_. It measured a pathspec against its own output, so it
could not detect the pathspec being wrong — which it was, by one file. The replacement
compares the `Makefile`'s real `ZSH_FILES` against the tracked zsh set as a **set**, so a
zsh file with an unmatched extension shows up as a diff line rather than as a number that
still looks plausible.

## Non-goals

- **No `command -v` guards** for `bats` or `zsh`. Both gates stay fail-closed.
- **The CI bash step's selector** stays on `find`. Aligning it with `git ls-files` is a
  separate, pre-existing inconsistency.
- **The partial overlap** between `make lint`'s zsh check and `tests/zshrc.d/unit.bats` is
  retained deliberately: they fire at different gates (pre-commit versus the suite), and the
  cost of running nine `zsh -n` invocations twice is negligible. An earlier draft called this
  "duplication" outright, which was wrong for two of the nine — `.zshrc` and
  `bruce.zsh-theme` have no `zsh -n` anywhere today, so this change is their first coverage
  rather than a second copy of existing coverage.
- **No `run_update` step.** Provisioning is §A's job and visibility is §E's; installing on
  the cadence path was considered, specified, and removed. Reasoning in §A.
- **`shellcheck` coverage of the zsh files** is not added. ShellCheck cannot lint zsh; per
  `shell.md`, zsh gets `zsh -n` and human review, and nothing else.

## Risks

- **`brew_install_formula bats-core` on a machine without Homebrew.** Handled the same way
  `install_zsh_macos` handles it — attempt `install_homebrew`, and fail explicitly with
  `log_error` plus `return 1` if it is still unavailable. The `|| return 1` at the call site
  then aborts `run_setup_user` rather than continuing with a half-configured machine.

  Note what that abort costs, since the call sits at `:135-137`, ahead of
  `clone_or_update_dotfiles`, `setup_dotfile_symlinks` and `install_git_hooks_all_repos`
  (`:206`): the machine is left unprovisioned, not merely bats-less. That is acceptable
  **only** because `install_homebrew` failing means the machine cannot be provisioned anyway
  — `install_git` (`:126`) and `install_zsh` (`:132`) already abort on the same condition,
  ahead of this one. It would not be acceptable for a condition the machine could recover
  from, which is exactly why the non-Ubuntu Linux case warns and returns 0 instead.

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

Disposition: **Addressed — then superseded in round 2. See Round 2 › Goal-Fit.** The
assumption was put to the operator and settled against it: `-t setup_user` is a
provisioning-time command on this fleet, not a cadence one. §A therefore gained an
`install_bats` step in `run_update`. All three round-2 lenses opposed that step, the operator
chose §E's `Brewfile` untag instead, and the step was removed. The remaining round-1 fixes
stand: the unfailable `tests/scripts/makefile_lint_scope.bats` was replaced (twice — the
round-1 replacement was itself rejected in round 2), the 7-vs-8 test count corrected, and the
Non-goals "duplication" framing rewritten.

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

---

## Multi-Lens Review — Round 2

Reviewed at commit: `929694d` (the round-1 disposition commit)

All three lenses re-run, not just the ones whose findings prompted revision, because round 1
changed design substance: a guard was un-narrowed, a `run_update` step was added, a test was
replaced, and an existing test was scheduled for retirement. Each of those is new design.
Each lens was told the round-1 review section is history rather than settled findings.

That was the right call. **Round 2 found defects in round 1's corrections — twice — and each
was caught by a lens other than the one whose finding prompted the correction.**

### Goal-Fit

Finding: The spec built a new provisioning path for a formula the repo already tracks, while
dismissing the one thing that silences the existing cadence-time consumer. `run_update`
already calls `_update_check_brewfile_drift` (`lib/workflows.sh:635`), which reports
`Missing (in Brewfile, not installed)` into the summary and `~/.dotfiles-update.log`; it is
silent about `bats-core` only because `Brewfile:15`'s `# [HAS_DEVTOOLS]` tag makes
`_brewfile_parse_section` skip the entry on `mac_mini` machines. The spec declared the tag
"not implicated" because `brew bundle` ignores it — true for installing, irrelevant for
detecting.

Also found a defect the round-1 revision introduced: the Implementation table instructed
adding `install_bats` to "the existing `if [[ ${MACOS} || ${LINUX} ]]` block at `:136`". No
such block exists — `lib/workflows.sh:131` is `if [[ ${MACOS} || ${UBUNTU} ]]`. Followed
literally it reinstates the exact `UBUNTU` narrowing the same revision was written to forbid.
Line numbers were off by four throughout the table.

Assumption: that `-t update` actually runs on the machine class that lacks bats. A machine
provisioned with `-t setup_user` only is by construction one nobody ran the fuller commands
on. Settled on that Mac with `ls -l ~/.dotfiles-update.log`.

Disposition: **Addressed.** The `run_update` step is removed entirely and replaced by §E,
which untags `Brewfile:15`. The Implementation table now specifies that `install_bats` keeps
its **own** block with the guard changed in place at `:135-137`, and states explicitly that
it must not be folded into the `install_zsh` block — the underlying error was not the guard
expression but the assumption that two functions with different platform coverage could share
one block.

### Ergonomics

Finding: The `run_update` step inverts the contract every comparable section keeps —
`lib/workflows.sh:565-590` shows tfenv, oh-my-zsh and tpm all `_update_skip` what is absent,
so a bats section would be the only one installing something absent. It also left two
operator-facing parameters unspecified: no `UPDATE_*` flag group fits (`UPDATE_BREW` is wrong
on Linux, `UPDATE_PKGS` wrong on macOS, so unguarded it fires under `--claude-only`), and no
failure disposition, where the obvious copied `|| return 1` aborts the whole cadence run
because `setup_env.sh:86` wraps `run_update` in `_run_or_exit`.

Second finding, and the sharper one: **verification row 4 — added in round 1 specifically so
the suite could fail if the measurement vanished — cannot fail in that direction either.** A
bash-syntax-invalid `.sh` file also fails `shellcheck`, and `Makefile:44-48` sets `failed=1`
and continues, so `make lint` exits non-zero whether or not the `bash -n` loop survived.

Third: verification rows 2-4 instruct injecting syntax errors into `.config/.zshrc.d/*.zsh`,
which are live symlinks into `$HOME`, with "Revert after" as the entire restore procedure.

Assumption: same as goal-fit — whether `-t update` reaches the affected Mac.

Disposition: **Addressed.** `run_update` step removed, so the contract, flag-group and
failure-disposition objections are moot. Row 4 now asserts on the `bash FAIL <path>` output
token rather than the exit code. The injection procedure now targets `bruce.zsh-theme` — the
one zsh file that is symlinked but not sourced, since `ZSH_THEME="bruce"` is commented at
`3_oh_my_zsh.zsh:7` — and names an explicit `git checkout -- <path>` per row with a
`git status --short` check between rows.

### Risk

Finding: Three items, all upheld.

**Row 6 was a tautology.** `git ls-files '*.zsh' '.zshrc' | wc -l` → 8 measures the pathspec
against its own output. `git ls-files | grep -i zsh` returns **nine** shell files:
`bruce.zsh-theme` matches neither pattern and is symlinked live into
`~/.oh-my-zsh/custom/themes/` by `lib/helpers.sh:678`. This is `shell.md`'s own pathspec
pitfall, reproduced inside the only row the spec labelled _measured, not predicted_, in a
document whose subject is a check aimed at the wrong files.

**The round-1 `LINUX`-not-`UBUNTU` justification does not survive.** The claim was that the
un-narrowed guard "lets `apt-get` fail loudly and abort, which is the correct direction." But
the call site precedes `setup_dotfile_symlinks` and `install_git_hooks_all_repos` (`:206`),
so aborting yields an **unprovisioned** machine, not a provisioned one with a loud error. The
narrowed form's failure is recoverable in thirty seconds. The real trade is which half of the
machine you lose.

**The replaced scope test is unstable.** Measured `make lint` at 14.7s; `test: lint` already
runs it, so a bats test shelling out to it pays that twice on every pre-push across seven
machines, and goes red for any lint finding anywhere in the repo. A loose grep for `zsh` near
`.zshrc` is also satisfied by a `zsh  FAIL .zshrc` line.

Confirmed as safe: retiring `tests/setup_env/workflows.bats:282-284` loses no real coverage —
`setup_env.sh` carries a bash shebang, nothing in `.zshrc`/`.zshrc.d` sources it, and both
`bash -n` at `:278` and `make lint` survive.

Assumption: whether `-t update` reaches the affected machine class — the third independent
statement of the same question.

Disposition: **Addressed.** `ZSH_FILES` now includes `'*.zsh-theme'` (nine files), and the
verification row compares the `Makefile`'s real `ZSH_FILES` against the tracked zsh set as a
**set** rather than asserting a count. The guard rationale is rewritten to take neither horn:
the call site keeps `MACOS || LINUX` and `install_bats_linux` gains a distro check that
warns and returns 0 on non-Ubuntu Linux — a loud skip, so neither a silent gap nor an
unprovisioned machine. The scope test now reads a new `make print-%` target instead of
shelling out to `make lint`, and behavioral `zsh -n` coverage for `.zshrc` and
`bruce.zsh-theme` is added directly to `tests/zshrc.d/unit.bats`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — unchanged from round 1. No comparison, evaluator, or ambiguous-criteria trigger.

### What this round cost and what it bought

Six lens dispatches across two rounds, ~890k subagent tokens. Round 2 was not a formality:
it caught a self-inflicted guard defect that would have reinstated the narrowing round 1
removed, a verification row that round 1 added to close an unfailability hole and which was
itself unfailable, and a pathspec error that reproduced the spec's own subject matter inside
its only "measured" claim. Two of the three were introduced **by** round 1's corrections.

The generalisable lesson is not "run more rounds" — it is that a correction is new design and
inherits none of the scrutiny the thing it corrects received.
