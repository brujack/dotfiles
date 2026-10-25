# ensure_state_ledger names why a step failed

- **Date:** 2026-10-24
- **Backlog row:** "`ensure_state_ledger` hides why `ledger init` failed" (P2 — bugs and security)
- **Approved:** 2026-10-24

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
  The cause is non-empty line 2 of 5. A `git pull --ff-only` failing the same way prints
  the same lines without `Cloning into`, so 4 non-empty lines with the cause first. An
  offline box's `Could not resolve hostname` sits in the same position.
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

### Unchanged

- `ledger.py init` still runs after a failed pull. Its own pull has no `BatchMode`, so
  on a box where our `BatchMode=yes` pull fails (a passphrase key with no agent, an
  unknown host key) init's pull can still prompt and succeed, and that path is how such
  a box gets its machine-id and `ledger` symlink. When both pulls fail, the init warning
  repeats the cause, which the selection above keeps.
- Lines are printed as captured. No URL redaction: git strips userinfo from its own
  messages, and the one Python line that could carry a URL comes from `cmd_init`'s
  clone branch, which this caller never reaches (dotfiles runs init only when
  `scripts/ledger.py` already exists in the checkout, so init takes its pull branch).
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
   `MOCK_GIT_STDERR` set to the measured 5-line pull capture (blank line included,
   no `Cloning into`). The output contains `state-ledger pull failed`,
   `Permission denied (publickey)` and `fatal: Could not read from remote repository.`
2. **init, traceback shape:** pull succeeds, and a stub `ledger.py` prints to stderr the measured
   traceback (`fatal: cannot change to …` first, the `CalledProcessError` line last)
   and exits 1. The output contains `ledger init failed`, `fatal: cannot change to`
   and `CalledProcessError`.
3. **clone:** `MOCK_GIT_CLONE_EXIT=1` with `MOCK_GIT_STDERR="fatal: clone-cause"`, and
   the directory absent. The output contains `state-ledger clone failed` and
   `fatal: clone-cause`, and the function returns 0.
4. **selection bounds:** a stub `ledger.py` prints to stderr 6 lines `e1`..`e6` and exits 1. The
   output contains `e1`, `e2`, `e3` and `e6`, and neither `e4` nor `e5`.
5. **empty stderr:** a stub `ledger.py` that exits 1 and prints nothing to either stream. The output
   contains `(no stderr output)`.
6. **quiet success:** pull and init both succeed and both write a line to stderr
   (`MOCK_GIT_STDERR` set, and a stub that prints to stderr, appends a marker to
   `MOCK_CALLS_FILE` and exits 0). The output contains no `[WARN]`, and the marker is
   present, so the test cannot pass with init never having run.

The existing tests "warns and returns 0 when clone fails" and "warns and returns 0 when
pull fails" keep passing unchanged, because the message text is unchanged.

## Requirements

- **R1.** `lib/workflows.sh` defines `_ledger_warn_with_cause`, which calls `log_warn` with its first argument and then, for the first 3 and the last non-empty lines of its second argument (each line once, in original order), calls `log_warn` with that line prefixed by two spaces.
- **R2.** `_ledger_warn_with_cause` prints `  (no stderr output)` through `log_warn` when its second argument has no non-empty line.
- **R3.** `ensure_state_ledger`'s `git pull`, `git clone` and `ledger.py init` calls each capture their stderr (stdout still discarded) and pass it to `_ledger_warn_with_cause` with the step's existing warning text when the command fails.
- **R4.** `ensure_state_ledger` returns 0 on every path, and the clone-failure branch still returns before the init step.
- **R5.** `tests/mocks/git` prints `MOCK_GIT_STDERR`, when set, to stderr on the `clone` path and the final catch-all path only.
- **R6.** `tests/setup_env/install_guards.bats` contains the six tests listed under Testing.
- **R7.** The Backlog row "`ensure_state_ledger` hides why `ledger init` failed" is removed from the open P2 table.
- **V1.** Tests 1, 2 and 3 fail on `origin/master` before the R3 change and pass after it.
- **N1.** No change to the three warning message texts.
- **N2.** No warning is printed when a step's command exits 0, whatever it wrote to stderr.
- **N3.** No change to `scripts/ledger.py` or any other file in the state-ledger repo.
- **N4.** On every path that reaches the init step, `ensure_state_ledger` runs `ledger.py init` whenever the script is executable, whether or not the pull step failed.

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

### Round 2

Reviewed at commit: `55bfdbe4` (all three lenses, round-1 section framed as history)

R numbers in this round use the `55bfdbe4` text, where R3 was redaction and R5 the init-skip; both were removed and the rest renumbered.

#### Goal-Fit

Finding: test 1 cannot fail on the init-skip (R5): its fixture has no `scripts/ledger.py`, and init runs only behind `[[ -x … ]]`, so the absent-warning assertion passes with or without the skip. Redaction (R3) protects a path this caller cannot reach: git strips userinfo itself (measured, git 2.53), and init's clone branch is unreachable because dotfiles runs init only when `ledger.py` exists. Stubs must write to stderr. Selection checked against unmeasured shapes (divergent `--ff-only`, non-git exception): cause kept.
Assumption: that init's pull fails whenever dotfiles' BatchMode pull fails; a passphrase key with no agent, or an unknown host key, refutes it.
Disposition: Addressed (operator, 2026-10-24) — R5 and R3 dropped (N4 added); stubs write to stderr.

#### Ergonomics

Finding: same vacuous R5 assertion. Test 1 used the clone capture on a pull path and pinned the fragment `and the repository exists.`. Cosmetic: a trailing `\r` on ssh's resolve error is printed. Volume acceptable: about 5 `[WARN]` lines only on a failing box.
Assumption: same BatchMode-divergence doubt; R5 would remove the path that gives such a box its machine-id and `ledger` symlink.
Disposition: Addressed (operator, 2026-10-24) — R5 dropped; test 1 uses the measured pull capture and asserts the cause line.

#### Risk

Finding: same vacuous R5 assertion. Checked clean: cmd_init order (skip lost nothing when both pulls fail), selection bounds 1/4/5 lines, trailing blank and CR-only lines, GNU and BSD `sed -E` redaction, `MOCK_GIT_STDERR` scope, `%` safety in `log_warn`.
Assumption: same BatchMode-divergence doubt, unmeasured on the fleet.
Disposition: Addressed (operator, 2026-10-24) — R5 dropped, so the assumption no longer carries the design.

### Round 3

Reviewed at commit: `f343ac09` (scoped: Risk lens on the round-2 changes only)

#### Risk

Finding: low. N4's "whenever the script is executable" contradicts R4 on one edge path: a self-heal whose `rm -rf` fails leaves an executable `ledger.py`, the clone then fails on the non-empty directory, and R4 returns before init. Tests 1-6 each can fail (test 4 also fails if every line is printed). Verified: git 2.53 strips userinfo from credentialed https URLs on clone and pull; init's clone branch is unreachable from this caller in production.
Assumption: no uncertain assumption carries the design; the weakest is that no captured line can carry a credentialed URL, refuted only by a git error path that echoes the raw remote URL.
Disposition: Addressed (operator, 2026-10-24) — N4 scoped to paths that reach the init step.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Amendments

- finding R2 (2026-10-24, reviewer B): DIFFERS — The filter `[[ "${_line}" =~ ^[[:space:]]*$ ]] && continue` treats whitespace-only lines as empty, so stderr made only of whitespace lines prints ` (no stderr output)`, whereas the requirement prints it only when there is no non-empty line (a whitespace-only line is non-empty); the empty-stderr case itself is met at line 34.
- R2 -> `_ledger_warn_with_cause` prints `  (no stderr output)` through `log_warn` when its second argument has no line that contains a non-whitespace character. — the Design section drops empty and whitespace-only lines; "non-empty" in the R text was meant as non-blank, and the code is right.
- R1 -> `lib/workflows.sh` defines `_ledger_warn_with_cause`, which calls `log_warn` with its first argument and then, for the first 3 and the last lines of its second argument that contain a non-whitespace character (each line once, in original order), calls `log_warn` with that line prefixed by two spaces. — same wording fix as R2: the Design drops whitespace-only lines, so "non-empty" means non-blank.

## Spec alignment (2026-10-24)

- spec: docs/superpowers/specs/2026-10-24-ensure-state-ledger-failure-cause-design.md
- anchor: 92f2369a9eb2ab00bf427fdce1d577b5d98b7222
- in scope: R1, R2, R3, R4, R5, R6, R7
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R2 | B | DIFFERS | The filter `[[ "${_line}" =~ ^[[:space:]]*$ ]] && continue` treats whitespace-only lines as empty, so stderr made only of whitespace lines prints ` (no stderr output)`, whereas the requirement prints it only when there is no non-empty line (a whitespace-only line is non-empty); the empty-stderr case itself is met at line 34. | - R2 -> `_ledger_warn_with_cause` prints ` (no stderr output)` through `log_warn` when its second argument has no line that contains a non-whitespace character. — the Design section drops empty and whitespace-only lines; "non-empty" in the R text was meant as non-blank, and the code is right. |

### Reviewed

- none

### Verifications

- V1: Orchestrator, 2026-10-24 (plan time): the six tests on a git archive of origin/master gave not ok 1-5 and ok 6; with only the MOCK_GIT_STDERR knob added, tests 1-5 still failed; with the plan code applied, all 114 install_guards tests passed. On the branch: 1..6 all ok, make test 3345/3345.
