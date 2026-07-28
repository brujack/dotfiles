# Auto-install git hooks across personal repos

**Date:** 2026-07-28
**Status:** Design approved, plan pending

## Problem

Nothing on any machine installs git hooks automatically. Git does not do it, and
`setup_dotfile_symlinks` does not either — it symlinks `.claude/` into `~/.claude/` and
never touches `.git/hooks/`. Every repo's hooks are installed exactly once, by hand, by
whoever ran `make install-hooks` in that checkout on that machine. From that moment the
installed copy is frozen while the committed source keeps moving.

Measured 2026-07-28:

- **Linux 7950X, ai-config:** all three installed hooks carried a single identical mtime
  from 2026-07-17 — `make install-hooks` had not been run in the 11 days since. The
  installed `pre-push` was missing 54 lines (the entire `_dod_gate` block) and the
  installed `commit-msg` lacked PR #118's role-model guard.
- **Mac Studio:** `etch-cli` `pre-commit` stale; `state-ledger` `pre-push` and
  `brucejacksonconsulting-site` `pre-commit` never installed at all.

The fleet is ~6+ boxes (3 Macs at work, a dev-capable Mac laptop, Linux 7950X, Windows
7900X). A per-box manual runbook re-creates the same drift N times, so the fix has to be
a workflow step, not a documented procedure.

Note: `USER.md`'s Environment section lists only 3 machines and understates the fleet.
Correcting it is out of scope here but worth a separate docs commit.

## Current state

Discovery run on the Mac Studio, 2026-07-28:

| Repo                          | `^install-hooks:`   | Hooks-dir primitive              |
| ----------------------------- | ------------------- | -------------------------------- |
| `ai-config`                   | yes                 | literal `.git/hooks` + `cp`      |
| `dotfiles`                    | yes                 | literal `.git/hooks` + `ln`      |
| `etch-cli`                    | yes                 | literal (unverified)             |
| `state-ledger`                | yes                 | literal (unverified)             |
| `brucejacksonconsulting-site` | yes                 | `git rev-parse --git-path hooks` |
| `math`                        | yes                 | `git rev-parse --git-path hooks` |
| `ai-devops`                   | no Makefile         | —                                |
| `etch-config`                 | no Makefile         | —                                |
| `terraform_ansible`           | Makefile, no target | —                                |

A separate session is adding a Makefile and hook scripts to `etch-config` and
`terraform_ansible`. `ai-devops` remains a known gap.

## Design

### Discovery, not a repo list

`dotfiles` has no canonical repo list. It special-cases `ai-config` at
`lib/workflows.sh:96` and knows nothing about the other repos, so a hardcoded list would
drift the moment a new repo appears. The sweep discovers instead:

```bash
for _dir in "${PERSONAL_GITREPOS}"/*/; do
  [[ -d "${_dir}.git" ]] || continue                   # worktree .git is a FILE — excluded
  git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
  [[ -f "${_dir}Makefile" ]] || continue
  grep -q '^install-hooks:' "${_dir}Makefile" || continue
  run_cmd make -s -C "${_dir}" install-hooks
done
```

The `[[ -d "${_dir}.git" ]]` test does two jobs with one line: it rejects non-repos, and
it rejects linked worktrees, whose `.git` is a file containing a `gitdir:` pointer rather
than a directory. This matters concretely — `ai-config-hook-integrity` is a live worktree
sitting directly in `~/git-repos/personal/` and it does match `^install-hooks:`. Without
this filter the sweep would install hooks into throwaway worktrees. The `*-worktrees`
container directories are excluded by the same line, since they hold no `.git` of their
own. No name-pattern matching, no allowlist, no marker file is required.

Scope is `~/git-repos/personal/` only. `~/git-repos/work/` is excluded.

#### Why both `-d .git` and `rev-parse --git-dir`

The two tests are not interchangeable and neither subsumes the other, so the sweep runs
both in that order:

- `[[ -d "${_dir}.git" ]]` alone accepts a directory that merely contains something named
  `.git` — a partial clone, an interrupted `git clone`, a stray directory.
- `rev-parse --git-dir` alone **succeeds inside a linked worktree**, which would re-admit
  exactly the throwaway worktrees the first test exists to exclude.

The `rev-parse` filter is defence in depth against a measured hazard. An `install-hooks`
recipe whose `HOOKS_DIR := $(shell git rev-parse --git-path hooks)` expands to the empty
string builds the path `/pre-commit` and, running as root on Linux, writes hooks into
`/`. macOS fails safe because `/` is read-only; Linux does not. Confirmed in `ai-config`
on 2026-07-28.

The sweep is not the primary defence — `make -C "${_dir}"` runs with cwd inside an
already-confirmed repo, so `rev-parse` cannot return empty there. The primary defence is
a fail-closed guard in each repo's own Makefile:

```makefile
HOOKS_DIR := $(shell git rev-parse --git-path hooks 2>/dev/null)
_HOOKS_DIR_GUARD = [[ -n "$(HOOKS_DIR)" ]] || { printf "%s: not in a git repository\n" "$@" >&2; exit 1; }
```

Note `=` not `:=` for the guard — `$@` must expand at recipe time, not parse time. The
`2>/dev/null` matters independently: without it, `:=` runs `git rev-parse` at parse time
and `fatal: not a git repository` prints on _every_ target in that repo whenever cwd is
outside one.

That guard belongs to each repo's own port and is out of scope here. The sweep's
`rev-parse` filter exists because the guard is per-repo and only exists where a port has
landed — the sweep must not depend on every repo having been fixed first.

### Trigger points

Called from two places:

1. `run_setup_user()` — after `setup_claude_plugins`, before `_ledger_write_run_entry`.
   Covers a new machine and any explicit config re-run.
2. `run_update()` — **after the `git-repos` section** (`lib/workflows.sh:473-482`), inside
   the `_run_all` block. `-t update` runs weekly on every box and is therefore the
   trigger that actually closes drift windows; `setup_user` alone would have left the
   measured 11-day gap open.

The `run_update` ordering is a hard constraint, not a preference. `sync_git_repos` is what
pulls each repo's hook _sources_; a sweep placed before it installs the previous cycle's
hooks and reports success. This is live, not hypothetical — `state-ledger` was 1 commit
behind upstream on the Mac Studio when this spec was written. Note also that
`sync_git_repos` skips the pull on a dirty checkout and never merges a diverged one, so
a repo left dirty still installs pre-pull sources; the sweep reports what it installed, not
what upstream holds.

`-t doctor` is not modified.

### Fail-closed, not fail-fast

Every discovered repo is attempted. Failures accumulate in a counter and
`install_git_hooks_all_repos()` returns 1 only after the loop completes. A single broken
Makefile therefore marks the sweep as failed without aborting the remaining repos, and —
because the sweep sits late in `run_update` — without costing the package updates that
already ran.

**The `setup_user` call site does not propagate that 1.** See "Return-code handling at the
two call sites" below: `setup_env.sh` dispatches through `_run_or_exit`, which `exit`s the
whole script on any non-zero return, so propagating there would let a broken Makefile in an
unrelated repo abort a full machine bootstrap. Fail-closed applies to `run_update`, where
the rc feeds the summary and is proportionate.

**What "fail-closed" actually buys, stated plainly:** `run_update`'s final statement is
`_update_summary`, so `run_update` returns that function's rc, not the sections'. The
sweep's 1 therefore does not reach the shell's exit status at either call site. What it
does produce is a `[FAIL]` row in the printed summary and a `_failure_stage` entry in the
state-ledger record — the same treatment every other update section gets. That consistency
is the reason to leave it there. Giving the rc teeth would mean changing `run_update` for
all 17 existing sections, which is its own spec.

### Gaps

A repo is a **gap** when it should carry hooks and does not — reported, never fatal, never
affecting the return code. Two distinct conditions produce one:

1. **Target missing or incomplete** — the repo has no `^install-hooks:` target, or the
   target ran cleanly but the repo's hooks directory still lacks a mandated hook.
2. **Infrastructure missing** — the repo is on the expected-repos list (below) but has no
   Makefile at all.

Condition 1's second half is the important one and is a **post-condition, not an exit
code**. `make install-hooks` exiting 0 means the target ran, not that the repo's hooks are
correct, and those two already diverge: `state-ledger`'s target installs only `pre-push`
(its `pre-commit` comes from `ledger init`, and the repo has no `scripts/commit-msg` at
all), so an exit-code-only check reports it green forever while the conventional-commits
gate stays absent on every box. After each `make`, the sweep asserts the mandated set
`{pre-commit, pre-push, commit-msg}` exists and is executable in the repo's hooks
directory, and counts a repo that ran cleanly but is still incomplete as a gap. The
before/after digest already reads that directory twice, so this costs one comparison.

**The assertion is on the installed hooks directory, never on `scripts/`.** A hook that
arrives by a route other than the Makefile satisfies it. This distinction is load-bearing
and easy to misread the other way, so state it plainly: `state-ledger` has no
`scripts/pre-commit`, but `ledger init` installs an executable `.git/hooks/pre-commit`, and
the post-condition therefore **passes** on it. A source-based check would report a false
gap there, weekly, forever — the exact tune-out failure the Reporting section exists to
prevent.

Measured on the Mac Studio 2026-07-28, across all six repos with a target:

| Repo                          | `pre-commit` | `pre-push` | `commit-msg` |
| ----------------------------- | ------------ | ---------- | ------------ |
| `ai-config`                   | ok           | ok         | ok           |
| `dotfiles`                    | ok           | ok         | ok           |
| `etch-cli`                    | ok           | ok         | ok           |
| `math`                        | ok           | ok         | ok           |
| `state-ledger`                | ok           | **absent** | **absent**   |
| `brucejacksonconsulting-site` | **absent**   | ok         | ok           |

Three fires, all true gaps, no false positives.

**The mandate is one uniform set, not per-repo.** `repo-structure.md` requires the same
three hooks of every personal repo with no variation by repo type — a `pre-commit` running
`ggshield` (line 10), `scripts/commit-msg` with "same content across all repos" (line 15),
and a permanent `pre-push` (`ci.md`). A static site and a Rust CLI get the same set. That
is why the expected-repos list below stays a flat list rather than a repo→hook-set map:
the value would be identical in every row.

#### The expected-repos list

Condition 2 needs a list, because no filesystem signal distinguishes a repo that _should_
have hooks from one that legitimately has none. Measured on the Mac Studio 2026-07-28 —
`ai-devops` and `etch-config` (both real gaps) are byte-for-byte indistinguishable from
`homepage`, `kubernetes`, `pfsense_config`, `python-learning`, `truenas-config`, and `ai`
on every candidate signal: no Makefile, no `.github/workflows/`, no hook sources in
`scripts/`. CI presence was the strongest candidate discriminator and it fails.

So a short explicit list of repos expected to carry hooks lives in `config/`, alongside
`profiles.sh`. Its scope is **reporting only**:

- It decides what counts as a gap.
- It does **not** decide what gets installed. Installation stays pure discovery, so a new
  repo with an `install-hooks` target gets hooks on the next sweep with no list edit.

That split confines the list's drift risk to the report. A stale list means a gap goes
unreported — the status quo today — not that a repo goes uninstalled.

**Known cost, stated rather than designed away.** The list lives in `dotfiles/config/` but
describes a property of the other nine repos, with nothing forcing the two to agree. That
is the same shape as `roleModels` — a declaration in one place about behaviour elsewhere —
and its failure mode is this work's own failure mode reintroduced one level up: a repo
gains hooks, nobody updates the list, the gap goes unreported forever. It is accepted here
because the scope split above bounds it to reporting, and because the alternative
(no list) makes the gap claim false for `ai-devops` and `etch-config` today. Worth
revisiting if the list ever starts deciding what gets installed.

### Reporting

The sweep is wrapped in `_update_record_start "git-hooks"` /
`_update_record_end "git-hooks" <rc>` inside `run_update`, and `"git-hooks"` is added to
the `readonly _UPDATE_SECTION_ORDER` array in `lib/update_summary.sh`.

Both edits are mandatory and coupled — `CLAUDE.md` records that adding a
`_update_record_start/end` pair without the matching `_UPDATE_SECTION_ORDER` entry means
the section is tracked internally but never printed.

The summary line reports **checked**, **updated**, gap, and failure counts, naming both the
repos that were actually updated and the repos counted as gaps — e.g.
`6 checked, 2 updated (ai-config, etch-cli), 3 gaps (state-ledger: commit-msg; ai-devops,
etch-config: no Makefile)`. Naming the gaps matters more than counting them: a bare
`3 gaps` is the same unactionable line in a different costume.

"Updated" is computed from a digest of the repo's hooks directory taken immediately before
and after its `make` call. A count of what was _installed_ is signal-free by construction:
because the sweep installs unconditionally, `installed: 6` reads identically whether all
six were already current or all six were 11 days stale. A weekly status line nobody can act
on is the failure mode this work exists to end.

**The digest must be over file contents, with symlinks resolved — never metadata.** This
is not a stylistic preference. Four of the six recipes are `cp`, which rewrites the
destination unconditionally; the other two are `ln -sf`, which unlinks and recreates,
giving a fresh inode. Measured on this machine by running `make install-hooks` twice in
`ai-config`:

```
content-hash (shasum -a 256):   IDENTICAL across runs
stat metadata (%N %m %z):       DIFFERS
```

A `stat`-based digest — the natural implementation, and what "digest of the directory"
would otherwise be read as — therefore reports every `cp` repo as updated every single
week on a perfectly current box. That is precisely the signal-free line this section
exists to replace, with more machinery behind it.

This does not reopen the diff-first question below. Diff-first asks whether the sweep can
_decide what to run_ without per-repo install-style knowledge — it cannot. Digesting the
hooks directory reports _what changed after the fact_, which needs no such knowledge: the
directory's contents differ or they do not, regardless of whether the repo got there via
`cp` or `ln -sf`.

`make` is invoked with `-s`. None of the six existing `install-hooks` recipes are
`@`-prefixed, so without it a weekly `-t update` gains ~30–40 lines of `cp`/`ln`/`chmod`
echo.

### `--dry-run`

The `make` invocation goes through the existing `run_cmd` wrapper (`lib/helpers.sh:15`),
which prints `[DRY RUN] make -s -C <dir> install-hooks` and executes nothing when
`DRY_RUN` is set. Discovery itself (directory tests, `rev-parse`, `grep` of the Makefile)
is read-only and runs in both modes, so a dry run still reports the correct repo list and
gap list. The before/after digest is skipped in dry-run mode — nothing can have changed —
and the updated count is reported as `n/a` rather than `0`, which would falsely assert
everything was current.

### Idempotency

The sweep runs `make install-hooks` unconditionally in every discovered repo, with no
drift detection. Each repo's target is already idempotent (`cp` or `ln -sf`), so
re-running is a no-op on an up-to-date box.

Verified 2026-07-28 by running `make -n install-hooks` in all six repos with the target:
every recipe is `cp`/`ln -sf`/`chmod` — nothing builds, tests, network-fetches, or
prompts. One caveat the earlier table missed: `dotfiles`' own target carries a
`ledger-symlink` prerequisite that `mkdir -p`s `~/.local/bin`, symlinks `ledger`, and
`chmod +x`es a file inside the `state-ledger` checkout. That is a side effect outside hook
installation, and this design runs it weekly on every box. It is idempotent and guarded by
`[ ! -L ... ]`, so it is accepted rather than worked around — but it is recorded here
because the design's premise is that per-repo knowledge is not needed, and this is a place
where the safety argument depends on it.

The same check must be re-run once `etch-config` and `terraform_ansible` gain their
targets (being authored concurrently in another session); if either builds, tests, fetches,
or prompts, the unconditional-every-update choice stops being free.

A diff-first variant was considered and rejected: comparing installed hooks against
source requires knowing each repo's install style (`dotfiles` symlinks, `ai-config`
copies, `math` symlinks with relative targets), which is exactly the per-repo knowledge
the discovery approach exists to avoid. An incomplete comparison heuristic would silently
skip a stale hook — the failure this work exists to eliminate.

## Code layout

New file `lib/git_hooks.sh`, sourced from `setup_env.sh` alongside the existing lib
files, following the `lib/git_sync.sh` / `lib/legacy_rsync.sh` precedent. It must carry
the standard sourcing guard:

```bash
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
```

Public function: `install_git_hooks_all_repos()`. Returns 0 when every discovered repo
installed cleanly (gaps do not affect this), 1 when any `make install-hooks` failed.

### Return-code handling at the two call sites

The sweep's non-zero return must not suppress bookkeeping that follows it. Neither call
site uses the repo's usual `|| return 1` shorthand:

- `run_setup_user()` — **log the failure count and return 0.** Do not propagate the rc.
  `setup_env.sh:82` dispatches via `_run_or_exit run_setup_user`, whose body is
  `[[ ${_ec} -eq 0 ]] || exit "${_ec}"` — so under `-t setup`, a non-zero return here
  aborts the entire script before `run_setup_or_developer` and `run_developer_or_ansible`
  ever run. A hooks-hygiene sweep must not gain the power to kill a machine bootstrap over
  a broken Makefile in an unrelated repo. Using `|| return 1` inline would additionally
  skip `_ledger_write_run_entry`, on exactly the runs worth recording.
- `run_update()` — the rc is passed to `_update_record_end "git-hooks"`, and the
  existing end-of-function summary and ledger write proceed unchanged. `run_update`
  reports section failures through the summary; the sweep behaves like every other
  section.

Under `--dry-run` the sweep always returns 0, because `run_cmd` prints instead of
executing and no `make` can fail. Gap warnings are still emitted.

## Testing

New `tests/setup_env/git_hooks.bats`. The `make` mock already exists at
`tests/mocks/make`.

Fixture: a temp `PERSONAL_GITREPOS` tree containing

1. a repo with `.git/` and an `install-hooks` target,
2. a repo with `.git/` and a Makefile but no `install-hooks` target,
3. a linked worktree whose `.git` is a regular file,
4. a plain directory with no `.git` at all,
5. a repo whose `make install-hooks` exits 1,
6. a directory containing an empty `.git/` directory but which is not a valid repo — a
   partial or interrupted clone,
7. a repo whose target exits 0 but installs only `pre-push` — the `state-ledger` shape,
8. a repo with `.git/` and no Makefile, **on** the expected-repos list,
9. a repo with `.git/` and no Makefile, **off** the expected-repos list.

Required assertions:

- **State** — exactly repos 1, 5, and 7 are invoked; 2, 3, 4, 6, 8, 9 are not.
- **Partial-clone guard** — repo 6 passes `[[ -d .git ]]` and must still be rejected by
  the `rev-parse --git-dir` filter. This is the test for the measured
  `HOOKS_DIR`-expands-empty hazard and cannot be covered by fixture 4.
- **Boundary** — an empty `PERSONAL_GITREPOS` returns 0 and reports zero repos; a tree
  with exactly one qualifying repo behaves the same as one with several.
- **Error path** — repo 5 makes `install_git_hooks_all_repos()` return 1, **and** repos
  discovered after it still run. This is the fail-closed-not-fail-fast property and is the
  single most important test in the file.
- **Call-site isolation** — with repo 5 present, `run_setup_user` still returns 0 while
  `run_update` records a FAIL for the `git-hooks` section. This is the dispatcher hazard
  and needs a test at both call sites, not just on the sweep function.
- **Gap path** — repo 2 emits a `log_warn` and does **not** change the return code.
- **Idempotency** — calling the function twice produces the same result as calling it
  once.
- **Reporting** — a repo whose hooks directory is unchanged by its `make` call is counted
  as checked-not-updated; a repo whose hooks change is named in the updated list. Both
  branches required — a digest that never fires reports `0 updated` forever and looks
  identical to a working one.
- **Digest is content-only** — a fixture repo installing via a real `cp`-style recipe,
  run twice with unchanged sources, must report checked-not-updated. This test must run
  against a real recipe, not the `make` mock: a mock that never touches the filesystem
  passes the assertion for the wrong reason, which is exactly the mock-fidelity failure
  `tdd.md` section E describes. The `cp` rewrites mtime, so a metadata digest fails this
  test and a content digest passes it — that is the whole point of the test.
- **`ln -sf` unchanged branch** — for a symlink-style repo, re-running `make` can never
  produce a delta, so that branch must be driven by **mutating the source file** and
  asserting the digest then reports updated. Testing it by re-running `make` asserts
  nothing; it is unfalsifiable by construction.
- **Post-condition** — a fixture repo whose `install-hooks` target exits 0 but installs
  only a subset of `{pre-commit, pre-push, commit-msg}` is counted as a **gap**, not an
  OK. This is the `state-ledger` shape and is the test that separates "the target ran"
  from "the hooks are correct".
- **Expected-repos list** — a repo on the list with no Makefile is reported as a gap; a
  repo off the list with no Makefile is silent. Both branches required, or the list is
  untested in the direction that motivated it.
- **Dry run** — with `DRY_RUN=1`, no `make` invocation is recorded, the reported repo list
  is unchanged, and the updated count is `n/a` rather than `0`.

`tests/setup_env/update_summary.bats` needs its section-count assertions updated for the
new `git-hooks` entry — `CLAUDE.md` warns that hardcoded counts in that file (e.g.
`*"9 OK"*`) are not caught by a mechanical `sed` pass over fixture loops and must be
audited by hand.

Bash coverage is CI-gated at 90%, so the error, gap, and dry-run paths need real coverage,
not just the happy path.

## Corrections to the backlog row's stated prerequisites

The backlog row said this spec should wait for "ai-config PR B + PR C merge." Both claims
were checked and neither holds:

1. **The `HOOKS_DIR` port is not a prerequisite.** Porting
   `HOOKS_DIR := $(shell git rev-parse --git-path hooks)` to `dotfiles`, `etch-cli`,
   `state-ledger`, and `ai-config` matters when `make install-hooks` is invoked _inside a
   linked worktree_, where the literal `.git/hooks` path does not exist. This sweep never
   invokes it inside a worktree, by design. The port remains correct work — `--git-path`
   is the only primitive that honors `core.hooksPath`, and `--git-common-dir` does not —
   but it does not gate this design.

   The backlog row cited `scripts/push-bash-coverage.sh:55` as evidence this repo sets
   `core.hooksPath`. That citation is wrong: line 55 is a transient
   `git -c core.hooksPath=/dev/null` flag scoped to a single push into the coverage
   worktree, and it never affects `make install-hooks`. The claim survives on better
   evidence — `git -C ~/git-repos/personal/dotfiles config --get core.hooksPath` returns
   a real persistent value.

2. **ai-config PR B is not merged.** It is uncommitted work on the
   `feat/hook-installation-integrity` branch in the `ai-config-hook-integrity` worktree.
   No PR is open and no remote branch exists. `ai-config/Makefile:20` still uses the
   literal `.git/hooks` path. Nothing in this design waits on it.

## Out of scope

- Native Windows (`setup_windows.ps1`). WSL2 on the 7900X runs `setup_env.sh` and gets
  the sweep; native Windows only links ai-config config and has no other repo checkouts
  to drift.
- `-t doctor` hook-freshness reporting.
- `~/git-repos/work/`.
- Adding hook infrastructure to `ai-devops` — reported as a gap, fixed in its own repo.
- Correcting `USER.md`'s machine list.
- The per-repo `_HOOKS_DIR_GUARD` Makefile port (see "Why both `-d .git` and
  `rev-parse --git-dir`") — belongs to each repo's own SDLC.
- **Normalizing the four `cp` repos to `ln -sf`** — see the Goal-Fit lens below. This is
  the correct root-cause fix for the _stale_ class and reduces its drift window to zero,
  but it is four repos × their own SDLC and it fixes none of the _never-installed_ class.
  Filed as its own backlog item; the two mechanisms are complementary, not alternatives.
- **Authoring a `scripts/commit-msg` for `state-ledger`** — the sweep can only install
  hooks a repo has sources for, and `state-ledger` has none for `commit-msg`. Its own
  repo's work; the sweep reports it as a gap until then.

### Corrected live tally

Round 2 of the review found the round-1 count wrong. Of the four live hook problems on the
Mac Studio, the sweep uniquely fixes **two**:

| Problem                                            | Sweep | Symlink normalization |
| -------------------------------------------------- | ----- | --------------------- |
| `state-ledger` `pre-push` missing                  | yes   | no                    |
| `brucejacksonconsulting-site` `pre-commit` missing | yes   | no                    |
| `etch-cli` `pre-commit` stale                      | yes   | yes                   |
| `state-ledger` `commit-msg` missing                | no    | no — no source exists |

Plus every future fresh clone and new box, which is the case neither normalization nor a
one-time backfill covers.

## Multi-Lens Review

Reviewed at commit: `542b374` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The sweep routes around the root cause instead of deleting it. Four repos
(`ai-config`, `etch-cli`, `state-ledger`, `brucejacksonconsulting-site`) install hooks
with `cp`, so they drift by construction; `dotfiles` and `math` install with `ln -sf` and
cannot drift at all. Every drift instance the Problem section measures is a `cp` repo.
Normalizing those four Makefiles to `ln -sf` closes the drift window to zero on the box
where the hook was edited — versus the ≤7 days a weekly sweep can deliver — with no new
lib file, no new bats file, no `_UPDATE_SECTION_ORDER` coupling, and no coverage burden.
The Idempotency section names the heterogeneity as an obstacle to route around rather
than as the root cause to remove. What survives after a symlink normalization is only the
never-installed case, which the `run_setup_user` call site alone covers.

Verified against this machine: of the four live hook problems found on the Mac Studio
right now, three are never-installed (`state-ledger` `pre-push` + `commit-msg`,
`brucejacksonconsulting-site` `pre-commit`) and one is stale (`etch-cli` `pre-commit`).
Symlink normalization fixes the stale one and none of the missing ones. Both mechanisms
are therefore addressing real, disjoint failure classes.

Assumption: That `-t update` actually runs weekly-ish on all ~6 boxes — the entire
justification for the `run_update` trigger. Settle with
`stat -c '%y %n' ~/.dotfiles-update.log` on the Linux 7950X, the laptop, and the WSL2
side of the 7900X, or by querying state-ledger `-t update` run entries per hostname over
90 days. Partial check done: last write on the Mac Studio is 2026-07-26 (2 days), so this
box is fine; the other boxes are unverified from here. If any box's median inter-run gap
exceeds ~14 days, the `run_update` trigger is not a drift-closing mechanism there.

Disposition: **Addressed** — both mechanisms, symlink normalization tracked separately.
Symlink normalization is recorded in Out of scope as the root-cause fix for the stale
class and filed as its own backlog item (4 repos × own SDLC). The sweep still ships: it
is the only mechanism that fixes the never-installed class, which is 3 of the 4 live
problems on the Mac Studio.

The assumption's `-t update` cadence check on the other boxes is **not settled** — only
the Mac Studio was verifiable from this session (2 days). If the 7950X's median gap turns
out to exceed ~14 days, the `run_update` trigger under-delivers there and the finding
should be revisited.

### Ergonomics

Finding: Two issues, both in the reporting path. (1) None of the six `install-hooks`
recipes are `@`-prefixed, so a weekly `-t update` gains ~30–40 lines of unsuppressed
`cp`/`ln`/`chmod` echo — invoke with `make -s`. (2) Because the sweep installs
unconditionally, "installed: 6, gaps: 1, failures: 0" reads identically whether all six
were current or all six were 11 days stale — a status line nobody can act on, printed
weekly, gets tuned out. The rejection of diff-first in the Idempotency section answers a
different question: it correctly argues you cannot _decide whether to run_ without
per-repo install-style knowledge, but reporting _what changed after the fact_ needs no
such knowledge — digest the hooks dir before and after each `make` call and report only
repos whose hooks actually changed, giving "6 checked, 2 updated (ai-config, etch-cli)".

Assumption: That at the moment the sweep runs, each discovered repo's main checkout is
already at the latest committed hook source. The spec orders the sweep only "late in
`run_update`", never against the `git-repos` section that does the pull, and
`sync_git_repos` skips the pull on a dirty checkout and never merges a diverged one — so
a mis-ordered or dirty checkout installs the previous cycle's hooks forever while
reporting clean success. Settle by pinning placement after `lib/workflows.sh:482` and
checking `git status --porcelain` + `git rev-list --count HEAD..@{u}` across the six
repos. Checked on the Mac Studio: all six clean, `state-ledger` is 1 commit behind — so
the ordering constraint is load-bearing today, not hypothetical.

Disposition: **Addressed** — both parts. `make -s` and the before/after hooks-dir digest
are now in the Reporting section; the summary reads `N checked, M updated (names)`, with
an explicit note on why post-hoc digesting does not reopen the diff-first argument. Both
reporting branches (changed / unchanged) are required tests. The assumption is settled and
folded into Trigger points as a hard ordering constraint after `lib/workflows.sh:473-482`,
including the dirty/diverged caveat.

### Risk

Finding: The fail-closed property inverts at the `run_setup_user` boundary.
`setup_env.sh:82` dispatches via `_run_or_exit run_setup_user`, and `_run_or_exit` is
`[[ ${_ec} -eq 0 ]] || exit "${_ec}"`. Returning the sweep's accumulated rc from
`run_setup_user` — exactly what the Return-code handling section prescribes — therefore
aborts `-t setup` before `run_setup_or_developer` and `run_developer_or_ansible` ever
run. A hooks-hygiene sweep gains the power to kill a full machine bootstrap over a broken
Makefile in an unrelated repo. `run_update` has no equivalent problem, since the section
rc feeds the summary. Verified: both the dispatch line and the `_run_or_exit` body read
as quoted.

Secondary: the Idempotency section's safety argument ("each repo's target is already `cp`
or `ln -sf`") depends on per-repo knowledge the design claims not to need, and two table
rows were self-labeled unverified. Also: "late in `run_update`, after the package-update
sections" does not pin the sweep after the `git-repos` section at `lib/workflows.sh:473`.

Verified by running `make -n install-hooks` across all six repos: every recipe is
`cp`/`ln -sf`/`chmod`; nothing builds, tests, network-fetches, or prompts. But
`dotfiles`' own target carries a `ledger-symlink` prerequisite that `mkdir -p`s
`~/.local/bin`, symlinks `ledger`, and `chmod +x`es a file inside the `state-ledger`
checkout — a side effect outside hook installation, which this design would run weekly on
every box.

Assumption: That `make install-hooks` in every repo the glob discovers is cheap,
non-interactive, and confined to hook installation. Now verified for the six existing
targets (see above). Remains genuinely open for `etch-config` and `terraform_ansible`,
whose targets are being authored concurrently in another session and have not been read
by anyone here. Re-run
`for r in ~/git-repos/personal/*/; do [ -d "$r.git" ] && make -C "$r" -n install-hooks; done`
once those land; if any target builds, tests, fetches, or prompts, the
unconditional-every-update choice stops being free.

Disposition: **Addressed.** The `run_setup_user` call site now logs the failure count and
returns 0, with the `_run_or_exit` mechanism quoted in Return-code handling and restated in
Fail-closed so the two sections cannot drift apart. Fail-closed is retained at `run_update`
only. Call-site isolation is now a required test at both sites. Both secondary points are
folded in: the `make -n` verification and the `ledger-symlink` side effect are recorded in
Idempotency, and the `git-repos` ordering is pinned in Trigger points. The assumption's
re-check for `etch-config` and `terraform_ansible` remains **open** and is carried in
Idempotency as a condition to re-run once those targets land.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## External Review — Independent Architect

Reviewed at commit `e7d148e`. Three findings; resolved by measurement rather than argument.

1. **"The post-condition applies a uniform mandate to a non-uniform set."** Does not hold,
   but the reading was available from the text, which was a real defect. The assertion is
   on the _installed hooks directory_, not on `scripts/`, so `state-ledger`'s
   `ledger init`-installed `pre-commit` passes rather than firing a false gap. Measured
   across all six repos: three fires, all true gaps, zero false positives. Separately,
   `repo-structure.md` mandates the same three hooks of every personal repo with no
   variation by repo type, so the mandate genuinely is uniform. **Addressed** — both facts
   now stated explicitly in the Gaps section with the measurement table inline.

2. **"Merge the expected-repos list and the hook mandate into one repo→hook-set map."**
   Falls with (1): a uniform mandate makes every row's value identical, so the map would
   add structure to express a constant. The list stays flat. The finding's independent
   half — that a declaration in `dotfiles/config/` about nine other repos is
   `roleModels`-shaped, with nothing forcing agreement — is correct and is now recorded as
   an accepted, bounded cost rather than designed away. **Addressed.**

3. **"The cadence assumption is load-bearing twice and still unmeasured."** Correct, and
   the push to measure it before planning was the right call. Promoted out of the lens
   sections into its own section above and then **settled** for the box that carries the
   evidence: the Linux 7950X shows 59 `_run_all` runs with the most recent on 2026-07-28.
   Both halves — cadence and flag-scoping — hold there. The measurement also turned the
   assumption into the design's strongest evidence: that box ran `-t update` the same day
   its hooks were 11 days stale, which is precisely the gap the sweep closes. **Addressed.**
   `cruncher` and `laptop` remain unmeasured and unreachable; neither carries evidence this
   design rests on.

## Resolved Question — `-t update` cadence on the non-Mac boxes

Three separate lens assumptions across both rounds reduce to one question: **does
`-t update` run often enough, in bare `_run_all` form, on the boxes that are not the Mac
Studio?** Round 1 raised the cadence; round 2 raised flag-scoping (`--brew-only`,
`--pip-only` skip the `_run_all` block entirely, so the sweep never fires under them).

This is load-bearing, because `run_setup_user` alone covers only fresh machines. If the
Linux 7950X's median inter-run gap exceeds ~14 days, or its habit is a scoped update, then
on the very box where the headline 11-day drift was measured this design does not close
it — and that box is the spec's own primary evidence.

One command per box answers both halves, since the `git-repos` section only prints under
`_run_all`:

```bash
ls -l --time-style=+%Y-%m-%d ~/.dotfiles-update.log
grep -c 'git-repos' ~/.dotfiles-update.log
```

**Status: settled for the box that matters.** Measured 2026-07-28:

| Box                         | log last written | `git-repos` occurrences |
| --------------------------- | ---------------- | ----------------------- |
| Mac Studio (`studio`)       | 2026-07-26       | 7                       |
| Linux 7950X (`workstation`) | 2026-07-28       | 59                      |

The 7950X runs bare `_run_all` updates frequently and ran one the same day this spec was
written. Both halves of the assumption hold there: the cadence is well inside any
reasonable window, and the habit is not flag-scoped. `cruncher` (WSL2) and `laptop` were
unreachable from the Mac Studio (`No route to host`) and remain unmeasured; neither carries
evidence this design rests on.

**This is the design's strongest single piece of evidence, not merely a cleared
assumption.** The 7950X ran `-t update` on 2026-07-28 while its `ai-config` hooks were
still the 11-day-stale 2026-07-17 snapshot. There is no contradiction — `-t update` does
not install hooks today. The trigger already fires at the right cadence on the box carrying
the headline drift; it simply does not yet do the thing. That is exactly the gap this sweep
closes, and it is why `run_update` is the correct call site rather than `setup_user` alone.

Had the answer gone the other way, the fix would have been a trigger change rather than a
reporting change — an additional call site, a `--hooks-only` flag matching the existing
`--brew-only` / `--pip-only` pattern, or moving the sweep outside the `_run_all` guard.
Recorded because it remains the correct response if `cruncher` or `laptop` later measure
badly.

## Multi-Lens Review — Round 2

All three round-1 dispositions were **Addressed**, so all three lenses re-ran against the
revised text at commit `2ea0e59`. Two lenses independently found the same two defects,
both of which were then settled empirically rather than by argument.

### Goal-Fit (round 2)

Finding: Gap detection is target-_presence_-based, not hook-_presence_-based, so a repo
whose target covers fewer hooks than `repo-structure.md` mandates reports clean forever.
`state-ledger` is a live instance: `scripts/` holds only `pre-push`, there is no
`commit-msg` source, and the target copies one file — so the sweep would report it updated
while the conventional-commits gate stays absent on every box. This also corrects round
1's own arithmetic: the Goal-Fit disposition counted `state-ledger commit-msg` among the
three never-installed problems justifying the sweep. The sweep cannot fix it. The real
count is 2 of 4, and one of those two (`etch-cli pre-commit`, stale) is fixed by symlink
normalization as well.

Verified: `ls state-ledger/scripts/` → `check_vcs_urls.py ledger.py pre-push`. The target
at `state-ledger/Makefile:13-16` copies `pre-push` only.

Assumption: That the local hooks contain gates with no CI equivalent — i.e. that a stale
hook lets a defect escape rather than merely deferring the same check to the PR gate.
Every measured instance is a stale _hook_, not a shipped _defect_. Settle by diffing each
repo's `scripts/pre-push` + `scripts/commit-msg` check list against its CI job list,
starting with `ai-config`'s `_dod_gate` block and the PR #118 role-model guard. **Open** —
not checked this session.

Disposition: **Addressed.** Gap detection is now a post-condition asserting the mandated
`{pre-commit, pre-push, commit-msg}` set exists and is executable after each `make`, with
"ran cleanly but incomplete" counted as a gap. The corrected 2-of-4 count is recorded in
Out of scope. The CI-equivalence assumption is carried forward unresolved.

### Ergonomics (round 2)

Finding: (1) The digest is unspecified as to content-vs-metadata, and a metadata digest
reports every `cp` repo as updated weekly — reintroducing the exact signal-free line it
was added to fix. (2) The discovery filter drops no-Makefile repos _before_ the gap check,
so `ai-devops` and `etch-config` — the two repos the spec names as gaps — are silently
skipped and can never be reported. The claim "a repo missing hook infrastructure stays
visible" was false as designed.

Verified: two `make install-hooks` runs in `ai-config` gave identical content hashes and
differing `stat` metadata. And no filesystem signal separates the two real gap repos from
the six legitimate no-hook repos — Makefile, `.github/workflows/`, and hook sources in
`scripts/` are all absent in every one of the eight.

Assumption: That the weekly `-t update` on other boxes is a bare `_run_all` invocation and
not a flag-scoped one (`--brew-only`, `--pip-only`). The sweep lives inside the `_run_all`
block, so on a box whose habit is scoped updates the trigger never fires. Settle with
`grep -c 'git-repos' ~/.dotfiles-update.log` plus the dates of those lines per box — the
`git-repos` section only prints under `_run_all`. Checked on the Mac Studio: present in
the most recent run, 7 occurrences total in the log. **Open** for the other boxes.

Disposition: **Addressed.** The digest is now specified as content-only with symlinks
resolved, with the measurement quoted inline and two dedicated tests (one against a real
`cp` recipe rather than the mock; one driving the `ln -sf` branch by mutating the source).
The gap definition is restructured around an expected-repos list scoped to reporting only.
Both `_run_all` assumptions are carried forward unresolved and are the same underlying
question as round 1's cadence assumption.

### Risk (round 2)

Finding: Converged with Goal-Fit — the success criterion is "the target exited 0", not
"this repo's hooks are correct", and a weekly green line on an incomplete repo is worse
than today's silence because it terminates the search. Two lesser points: `run_update`
returns `_update_summary`'s rc, so fail-closed reaches no exit status at either call site;
and the `core.hooksPath` citation overstated a transient `git -c` flag.

Verified: `run_update`'s final statement is `_update_summary`. And
`git config --get core.hooksPath` in `dotfiles` does return a persistent value — so the
claim holds, but `push-bash-coverage.sh:55` was the wrong evidence for it.

Assumption: That the digest can distinguish current from stale at all — settled by the
two-run experiment above, which is why the digest is now specified as content-only.

Disposition: **Addressed.** Post-condition folded into the Gaps section (same fix as
Goal-Fit). The rc-has-no-teeth point is now stated plainly in Fail-closed, with the
decision to leave it: the `[FAIL]` row and the ledger `_failure_stage` entry are the real
signal, and giving the rc teeth would mean changing `run_update` for all 17 existing
sections — its own spec. The `core.hooksPath` citation is corrected in place.
