# ensure_state_ledger names why a step failed

- **Date:** 2026-10-24
- **Backlog row:** "`ensure_state_ledger` hides why `ledger init` failed" (P2 — bugs and security)

## Problem

`ensure_state_ledger` (`lib/workflows.sh`) runs at the start of every workflow, from
`_dotfiles_run_tmpdir_setup`. It runs three external commands, and each one discards
its stderr:

- `git -C "${_dir}" pull --ff-only >/dev/null 2>&1 || log_warn "state-ledger pull failed — continuing without ledger sync"`
- `git clone "${_url}" "${_dir}" >/dev/null 2>&1 || { log_warn "state-ledger clone failed — continuing without ledger"; return 0; }`
- `"${_dir}/scripts/ledger.py" init >/dev/null 2>&1 || log_warn "ledger init failed — continuing"`

So each warning says that a step failed but never why. Measured on `claude` on 2026-09-12:
`ledger init` failed with `FileNotFoundError: 'pre-commit'` at `ledger.py:397`, and the
cause stayed invisible until someone ran the command by hand. Verified 2026-10-24 by
reading `lib/workflows.sh` on `origin/master` `dc1dc8b5`: all three discards are still
there.

state-ledger has since fixed its half. `cmd_init` now degrades when `pre-commit` is
missing: it prints a stderr WARNING and returns 0. Init still returns 1 in four cases:
`git pull` or `git clone` fails (both run with `check=True` and nothing catches the
`CalledProcessError`); `pre-commit` ran but left no hook; or no URL and no checkout
exist. Read from `~/.local/share/state-ledger/scripts/ledger.py` `cmd_init` on
2026-10-24. Init re-pulls, so a pull failure is also the likeliest cause of an init
failure, which is why the pull and clone discards are in scope too (operator decision
2026-10-24).

### Where the cause sits in real stderr

Two shapes, both measured on `claude` on 2026-10-24 with git 2.54 and Python 3.14.8:

- **git transport failure** (pull or clone, ssh auth refused, simulated with a
  `GIT_SSH_COMMAND` that prints `Permission denied (publickey).` and exits 255):
  `Cloning into '…'...` / `git@github.com: Permission denied (publickey).` /
  `fatal: Could not read from remote repository.` / _(blank)_ /
  `Please make sure you have the correct access rights` / `and the repository exists.`
  The cause is non-empty line 2 of 5. An offline box's `Could not resolve hostname`
  sits in the same position.
- **init's own pull failing**
  (`subprocess.run(["git","-C","/nonexistent-x","pull","--ff-only"], check=True)`):
  `fatal: cannot change to '/nonexistent-x': No such file or directory` is the first
  line, followed by the traceback. The last 3 non-empty lines are two lines of
  `raise CalledProcessError(...)` and the `CalledProcessError … exit status 128` line,
  none of which names the cause.

So the cause is near the top in both shapes, and a tail window drops it in both. The one
known failure whose message is the last line is `ERROR: pre-commit hook not installed —
ledger init failed`, which ledger.py prints after pre-commit's own output.

## Design

### Capture stderr, keep stdout discarded

For each command, replace `>/dev/null 2>&1` with a capture of stderr into a local
variable, still sending stdout to `/dev/null`:

```bash
_err=$(GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_dir}" pull --ff-only 2>&1 >/dev/null) \
  || _ledger_warn_with_cause "state-ledger pull failed — continuing without ledger sync" "${_err}"
```

The redirection order matters: `2>&1` first points stderr at the capture, then
`>/dev/null` sends stdout away. No temp file is involved, so nothing needs cleaning up.
`_err` is declared with `local _err` on its own line beforehand, because
`local _err=$(…)` returns `local`'s status rather than the command's. The clone branch
keeps its `return 0`. Command order and the conditions that choose pull or clone are
unchanged.

### Skip init after this run's pull failed

`ledger.py init` re-pulls with `check=True` before writing the machine-id or the
`ledger` symlink. If this run's pull just failed, init's pull is expected to fail the
same way, and it then aborts before doing either of those things. Running it only adds
a second warning whose cause line is the same git failure already shown under the pull
warning. So when the pull step fails, `ensure_state_ledger` skips the init step and
prints nothing more for it. The next run retries both. A clone failure already returns
before init, unchanged.

### `_ledger_warn_with_cause <msg> <stderr>`

A new helper in `lib/workflows.sh`, placed directly above `ensure_state_ledger`:

1. `log_warn "<msg>"`, with the message unchanged, so existing tests and greps that
   match on it still match.
2. Then one `log_warn "  <line>"` for each **selected** line of `<stderr>`, in their
   original order. Selection: drop empty and whitespace-only lines, then keep the
   first 3 remaining lines and the last remaining line. If there are 4 or fewer lines,
   every one is kept once. This puts the cause in the output for both measured shapes
   and keeps ledger.py's final `ERROR:` line, with no list of error keywords to
   maintain.
3. If `<stderr>` has no non-empty line, it prints `log_warn "  (no stderr output)"`, so
   silence reads as a fact rather than as missing output.
4. Each printed line has every match of the extended regex `://[^/@[:space:]]*@`
   replaced with `://***@`. That covers `https://user:token@host`, which can reach
   stderr because `ledger.py init` honours `LEDGER_REPO_URL`. The character class
   stops at the first `/`, `@` or space, so an `@` later in the line (an email, an ssh
   `git@host`) is never swallowed.

### Unchanged

- `ensure_state_ledger` still returns 0 on every path, and its caller still runs it as
  `ensure_state_ledger || true`.
- If init returns 0 after printing its "`pre-commit` not on PATH" WARNING, nothing is
  printed. That WARNING fires on every machine that never commits to state-ledger, and
  the update WARN lane is already saturated (measured on the Mac Studio only, in the
  dotfiles bug-hunt knowledge: 84% of its `[WARN]` lines are `brew-drift`).
- The warning wording for all three steps.

## Testing

The tests go in `tests/setup_env/install_guards.bats`, beside the existing
`ensure_state_ledger` tests, and are written RED first. `tests/mocks/git` gains a
`MOCK_GIT_STDERR` knob: when it is set, the mock prints its value to stderr on the
`clone` path and on the final catch-all path, but never on the `rev-parse --git-dir`
or `config --get` paths, so `_git_is_valid_repo` and the hooks tests are unaffected.
Fixtures 1 and 2 below reproduce the two measured shapes verbatim, not synthetic lines.

1. **pull, transport shape:** `MOCK_GIT_EXIT=1`, directory present, and
   `MOCK_GIT_STDERR` set to the 6-line ssh capture above (blank line included). The
   output contains `state-ledger pull failed`, `Permission denied (publickey)` and
   `and the repository exists.`, and does not contain `ledger init failed`, which
   pins the skip.
2. **init, traceback shape:** pull succeeds, and a stub `ledger.py` prints the measured
   traceback (`fatal: cannot change to …` first, the `CalledProcessError` line last)
   and exits 1. The output contains `ledger init failed`, `fatal: cannot change to`
   and `CalledProcessError`.
3. **clone:** `MOCK_GIT_CLONE_EXIT=1` with `MOCK_GIT_STDERR="fatal: clone-cause"`, and
   the directory absent. The output contains `state-ledger clone failed` and
   `fatal: clone-cause`, and the function returns 0.
4. **selection bounds:** a stub `ledger.py` prints 6 lines `e1`..`e6` and exits 1. The
   output contains `e1`, `e2`, `e3` and `e6`, and neither `e4` nor `e5`.
5. **empty stderr:** a stub `ledger.py` that exits 1 and prints nothing. The output
   contains `(no stderr output)`.
6. **redaction:** a stub `ledger.py` prints
   `fatal: https://u:SECRET@example.invalid/x by git@github.com` and exits 1. The
   output contains `://***@example.invalid` and `git@github.com`, and does not contain
   `SECRET`.
7. **quiet success:** pull and init both succeed and both write a line to stderr
   (`MOCK_GIT_STDERR` set, and a stub that prints to stderr, appends a marker to
   `MOCK_CALLS_FILE` and exits 0). The output contains no `[WARN]`, and the marker is
   present, so the test cannot pass with init never having run.

The existing tests "warns and returns 0 when clone fails" and "warns and returns 0 when
pull fails" keep passing unchanged, because the message text is unchanged.

## Requirements

- **R1.** `lib/workflows.sh` defines `_ledger_warn_with_cause`, which calls `log_warn` with its first argument and then, for the first 3 and the last non-empty lines of its second argument (each line once, in original order), calls `log_warn` with that line prefixed by two spaces.
- **R2.** `_ledger_warn_with_cause` prints `  (no stderr output)` through `log_warn` when its second argument has no non-empty line.
- **R3.** `_ledger_warn_with_cause` replaces every match of `://[^/@[:space:]]*@` in a printed line with `://***@`.
- **R4.** `ensure_state_ledger`'s `git pull`, `git clone` and `ledger.py init` calls each capture their stderr (stdout still discarded) and pass it to `_ledger_warn_with_cause` with the step's existing warning text when the command fails.
- **R5.** `ensure_state_ledger` skips the `ledger.py init` step when its `git pull` step failed in the same call.
- **R6.** `ensure_state_ledger` returns 0 on every path, and the clone-failure branch still returns before the init step.
- **R7.** `tests/mocks/git` prints `MOCK_GIT_STDERR`, when set, to stderr on the `clone` path and the final catch-all path only.
- **R8.** `tests/setup_env/install_guards.bats` contains the seven tests listed under Testing.
- **R9.** The Backlog row "`ensure_state_ledger` hides why `ledger init` failed" is removed from the open P2 table.
- **V1.** Tests 1, 2 and 3 fail on `origin/master` before the R4 change and pass after it.
- **N1.** No change to the three warning message texts.
- **N2.** No warning is printed when a step's command exits 0, whatever it wrote to stderr.
- **N3.** No change to `scripts/ledger.py` or any other file in the state-ledger repo.

## Multi-Lens Review

Reviewed at commit: `83cb063b`

### Round 1

#### Goal-Fit

Finding: "last 3 non-empty lines" shows Python's traceback tail when init's own `check=True` pull fails; git's `fatal:` is printed first and falls outside the window (measured, Python 3.14.8). The pull and clone captures carry the real value. Reads-it: consumer is the operator reading terminal stderr at the top of a run; it removes the by-hand rerun the 2026-09-12 incident needed. Not raised: init's own git runs without BatchMode (state-ledger concern, excluded by N3, worth a Backlog row there).
Assumption: whether init's pull can fail while dotfiles' own pull succeeds (init's git has no BatchMode).
Disposition: Addressed (operator, 2026-10-24) — selection is now first 3 + last non-empty line; test 2 uses the measured traceback.

#### Ergonomics

Finding: the tail rule also drops the cause for a git transport failure: `Permission denied (publickey)` precedes `fatal:` and git's two boilerplate lines follow it (measured). When the pull fails, init's re-pull fails too, so each run prints 8 `[WARN]` lines with a cause-stripped duplicate. Test 1's synthetic fixture cannot catch either.
Assumption: that first-`fatal:`-style selection also covers the pre-commit-ran-no-hook path, where ledger.py's `ERROR:` line comes last.
Disposition: Addressed (operator, 2026-10-24) — first 3 + last line keeps both the early cause and the final `ERROR:`; init is skipped after a failed pull; tests 1 and 2 use the measured shapes.

#### Risk

Finding: same tail-window loss on init's traceback (medium, bounded by call order). Minor: the quiet-success test passes if the init stub never ran; the redaction pattern was unspecified and a greedy glob would over-redact. Checked clean: redirection order, `local _err`, prompt and tty behaviour, no ControlPersist, no `MOCK_GIT_STDERR` leak, scope proportionate.
Assumption: that init's pull essentially never fails unless the BatchMode pull just before it also failed; refute by any `ledger init failed` without a preceding `state-ledger pull failed`.
Disposition: Addressed (operator, 2026-10-24) — test 7 asserts the init marker; redaction pinned to `://[^/@[:space:]]*@`; if init fails after a good pull, test 2's shape shows the cause.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
