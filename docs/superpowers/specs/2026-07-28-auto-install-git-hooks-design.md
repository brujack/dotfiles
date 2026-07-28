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
  [[ -f "${_dir}Makefile" ]] || continue
  grep -q '^install-hooks:' "${_dir}Makefile" || continue
  run_cmd make -C "${_dir}" install-hooks
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

### Trigger points

Called from two places:

1. `run_setup_user()` — after `setup_claude_plugins`, before `_ledger_write_run_entry`.
   Covers a new machine and any explicit config re-run.
2. `run_update()` — late in the function, after the package-update sections. `-t update`
   runs weekly on every box and is therefore the trigger that actually closes drift
   windows; `setup_user` alone would have left the measured 11-day gap open.

`-t doctor` is not modified.

### Fail-closed, not fail-fast

Every discovered repo is attempted. Failures accumulate in a counter and the function
returns 1 only after the loop completes. A single broken Makefile therefore marks the run
as failed without aborting the remaining repos, and — because the sweep sits late in
`run_update` — without costing the package updates that already ran.

A repo with a Makefile but no `^install-hooks:` target is a **gap**, not a failure: it
emits `log_warn` and is counted separately. It does not affect the return code. Gaps are
reported rather than silently skipped so that a repo missing hook infrastructure stays
visible.

### Reporting

The sweep is wrapped in `_update_record_start "git-hooks"` /
`_update_record_end "git-hooks" <rc>` inside `run_update`, and `"git-hooks"` is added to
the `readonly _UPDATE_SECTION_ORDER` array in `lib/update_summary.sh`.

Both edits are mandatory and coupled — `CLAUDE.md` records that adding a
`_update_record_start/end` pair without the matching `_UPDATE_SECTION_ORDER` entry means
the section is tracked internally but never printed.

The summary line reports installed count, gap count, and failure count.

### `--dry-run`

The `make` invocation goes through the existing `run_cmd` wrapper (`lib/helpers.sh:15`),
which prints `[DRY RUN] make -C <dir> install-hooks` and executes nothing when `DRY_RUN`
is set. Discovery itself (directory tests, `grep` of the Makefile) is read-only and runs
in both modes, so a dry run still reports the correct repo list and gap list.

### Idempotency

The sweep runs `make install-hooks` unconditionally in every discovered repo, with no
drift detection. Each repo's target is already idempotent (`cp` or `ln -sf`), so
re-running is a no-op on an up-to-date box.

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

- `run_setup_user()` — capture the sweep's rc, run `_ledger_write_run_entry` as it does
  today, then return the captured rc. Using `|| return 1` inline would skip the ledger
  write on exactly the runs worth recording.
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
5. a repo whose `make install-hooks` exits 1.

Required assertions:

- **State** — exactly repos 1 and 5 are invoked; 2, 3, 4 are not.
- **Boundary** — an empty `PERSONAL_GITREPOS` returns 0 and reports zero repos; a tree
  with exactly one qualifying repo behaves the same as one with several.
- **Error path** — repo 5 makes the function return 1, **and** repos discovered after it
  still run. This is the fail-closed-not-fail-fast property and is the single most
  important test in the file.
- **Gap path** — repo 2 emits a `log_warn` and does **not** change the return code.
- **Idempotency** — calling the function twice produces the same result as calling it
  once.
- **Dry run** — with `DRY_RUN=1`, no `make` invocation is recorded and the reported repo
  list is unchanged.

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
   is the only primitive that honors `core.hooksPath`, which this repo itself sets at
   `scripts/push-bash-coverage.sh:55`, and `--git-common-dir` does not — but it does not
   gate this design.
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

Disposition:

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

Disposition:

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

Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
