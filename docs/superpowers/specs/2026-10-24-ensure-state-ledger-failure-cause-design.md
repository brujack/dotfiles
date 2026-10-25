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
`git pull` or `git clone` fails (both run with `check=True`, so they raise); `pre-commit`
ran but left no hook; or no URL and no checkout exist. Read from
`~/.local/share/state-ledger/scripts/ledger.py` `cmd_init` on 2026-10-24. Init re-pulls,
so a pull failure is also the likeliest cause of an init failure, which is why the pull
and clone discards are in scope too (operator decision 2026-10-24).

## Design

### Capture stderr, keep stdout discarded

For each command, replace `>/dev/null 2>&1` with a capture of stderr into a local
variable, still sending stdout to `/dev/null`:

```bash
_err=$(GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_dir}" pull --ff-only 2>&1 >/dev/null) \
  || _ledger_warn_with_cause "state-ledger pull failed — continuing without ledger sync" "${_err}"
```

The redirection order matters: `2>&1` first points stderr at the capture, then
`>/dev/null` sends stdout away. No temp file is involved, so nothing needs cleaning up. `_err` is declared with `local _err` on its own line
beforehand, because `local _err=$(…)` returns `local`'s status rather than the command's.
The clone branch keeps its `return 0`. Command order and the conditions that choose
pull or clone are unchanged.

### `_ledger_warn_with_cause <msg> <stderr>`

A new helper in `lib/workflows.sh`, placed directly above `ensure_state_ledger`:

1. `log_warn "<msg>"`, with the message unchanged, so existing tests and greps that
   match on it still match.
2. Then one `log_warn "  <line>"` for each of the **last 3 non-empty** lines of
   `<stderr>`. Three lines hold a Python traceback's final frame and exception line, or
   git's `fatal:` line plus its explanation.
3. If `<stderr>` has no non-empty line, it prints `log_warn "  (no stderr output)"`, so
   silence reads as a fact rather than as missing output.
4. Each printed line has any `://<userinfo>@` replaced with `://***@`. The clone URL is
   ssh today, but `ledger.py init` honours `LEDGER_REPO_URL`, which may be an https URL
   that carries a token.

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

1. **init:** a stub `ledger.py` that prints 5 stderr lines (`e1`..`e5`) and exits 1.
   The output contains `ledger init failed`, `e3`, `e4` and `e5`, and neither `e1`
   nor `e2`.
2. **pull:** `MOCK_GIT_EXIT=1` with `MOCK_GIT_STDERR="fatal: pull-cause"`, and the
   directory present. The output contains `state-ledger pull failed` and
   `fatal: pull-cause`.
3. **clone:** `MOCK_GIT_CLONE_EXIT=1` with `MOCK_GIT_STDERR="fatal: clone-cause"`, and
   the directory absent. The output contains `state-ledger clone failed` and
   `fatal: clone-cause`, and the function returns 0.
4. **empty stderr:** a stub `ledger.py` that exits 1 and prints nothing. The output
   contains `(no stderr output)`.
5. **redaction:** a stub `ledger.py` that prints
   `fatal: https://u:SECRET@example.invalid/x` and exits 1. The output contains
   `://***@example.invalid` and does not contain `SECRET`.
6. **quiet success:** pull and init both succeed, and both write a line to stderr
   (`MOCK_GIT_STDERR` set, plus a stub that prints to stderr and exits 0). The output
   contains no `[WARN]`.

The existing tests "warns and returns 0 when clone fails" and "warns and returns 0 when
pull fails" keep passing unchanged, because the message text is unchanged.

## Requirements

- **R1.** `lib/workflows.sh` defines `_ledger_warn_with_cause`, which calls `log_warn` with its first argument and then, for each of the last 3 non-empty lines of its second argument, calls `log_warn` with that line prefixed by two spaces.
- **R2.** `_ledger_warn_with_cause` prints `  (no stderr output)` through `log_warn` when its second argument has no non-empty line.
- **R3.** `_ledger_warn_with_cause` replaces every `://<userinfo>@` in a printed line with `://***@`.
- **R4.** `ensure_state_ledger`'s `git pull`, `git clone` and `ledger.py init` calls each capture their stderr (stdout still discarded) and pass it to `_ledger_warn_with_cause` with the step's existing warning text when the command fails.
- **R5.** `ensure_state_ledger` returns 0 on every path, and the clone-failure branch still returns before the init step.
- **R6.** `tests/mocks/git` prints `MOCK_GIT_STDERR`, when set, to stderr on the `clone` path and the final catch-all path only.
- **R7.** `tests/setup_env/install_guards.bats` contains the six tests listed under Testing.
- **R8.** The Backlog row "`ensure_state_ledger` hides why `ledger init` failed" is removed from the open P2 table.
- **V1.** Tests 1, 2 and 3 fail on `origin/master` before the R4 change and pass after it.
- **N1.** No change to the three warning message texts.
- **N2.** No warning is printed when a step's command exits 0, whatever it wrote to stderr.
- **N3.** No change to `scripts/ledger.py` or any other file in the state-ledger repo.
