# Git-Hook Detection Gaps — Design

**Date:** 2026-07-31
**Status:** Approved, pending plan

## Problem

Two independent detection gaps in this repo's git-hook machinery. Both were found
during earlier work and deferred to the backlog; neither is a regression.

**Gap 1 — `scripts/pre-push` does not test itself.** Its trigger regex
(`scripts/pre-push:24`) is `'\.(sh|bats)$|^Makefile$|^tests/'`. Both
`scripts/pre-push` and `scripts/commit-msg` are extensionless, so a push whose only
change is to one of those two hooks matches nothing and skips `make test` entirely.
The local gate is absent for exactly the files that implement the local gate. CI
backstops it, but only after the push has left the machine. Found during dotfiles#191
bug-scan.

**Gap 2 — an unreadable git config scope reads as clean.**
`_git_hooks_hookspath_offenders` (`lib/git_hooks.sh:309`) reads `core.hooksPath` at
system and global scope with `git config "--${_scope}" --get core.hooksPath
2>/dev/null || continue`. The `|| continue` collapses every non-zero exit into "key
unset, scope clean." A scope git could not read at all is therefore reported as
verified-clean by both consumers — the doctor check and the update sweep. Deferred
during dotfiles#194 on the grounds that a corrupt gitconfig makes essentially every
other git call fail loudly at the same moment, which does not cover the
scope-specific case: `/etc/gitconfig` unreadable while `--global` reads fine leaves
every other git call working normally.

### Measured correction to the backlog's premise

The backlog row proposed "capture rc and branch: rc 1 = clean, rc > 1 = a
distinguishable cannot-determine record." Probed live on git 2.55 / macOS
2026-07-31:

| scope state                         | rc  | stderr                                               |
| ----------------------------------- | --- | ---------------------------------------------------- |
| key unset                           | 1   | silent                                               |
| config malformed (`[core` unclosed) | 128 | `fatal: bad config line 1 in file ...`               |
| config unreadable (`chmod 000`)     | 1   | `warning: unable to access '...': Permission denied` |
| config path is a directory          | 1   | `warning: unable to access '...': Is a directory`    |

**An unreadable scope exits 1, not 128** — identical to the clean path. An rc-only
branch would still report the unreadable-`/etc/gitconfig` case clean, i.e. it would
not close the gap the deferral actually named. The only signal distinguishing the two
is stderr, which the current code discards via `2>/dev/null`.

## Decisions

1. **Detection uses rc and stderr together.** Rejected rc-only (does not close the
   stated gap) and a readability precheck that stats the scope's config file directly
   (duplicates git's own scope-file resolution — `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`,
   XDG paths, `$HOME` quirks — creating a second source of truth that can drift from
   git's).
2. **Cannot-determine fails closed.** `doctor_fail` (so `-t doctor` exits non-zero)
   and sweep rc 2. Per USER.md's "fail closed on unknown — unknown ≠ safe." Rejected
   an advisory `doctor_warn`: a scope git could not read is precisely the state that
   must not score as PASS.
3. **Trigger regex adds `^scripts/`, not the two filenames.** Rejected naming
   `scripts/(pre-push|commit-msg)` explicitly — a third extensionless script added
   later would be silently uncovered again, which is the exact failure being fixed.
   All 18 files in `scripts/` are executable shell; 16 already match via `\.sh$`, so
   this adds exactly the two hooks today.

## Design

### Item 1 — pre-push self-coverage

`scripts/pre-push:24` becomes:

```bash
if git diff --name-only "${range}" | grep -qE '\.(sh|bats)$|^Makefile$|^scripts/|^tests/'; then
```

One alternation. No other change to the hook.

### Item 2 — hooksPath cannot-determine

`_git_hooks_hookspath_offenders` changes its output from 2-field
`scope<TAB>value` to 3-field `status<TAB>scope<TAB>detail`, where `status` is
literally `pinned` or `unknown`:

```
rc 0                      ->  pinned <scope> <value>
rc 1, stderr empty        ->  (prints nothing; scope is clean)
rc 1, stderr non-empty    ->  unknown <scope> <first stderr line>
rc >1                     ->  unknown <scope> rc=<n>
```

Only the first stderr line is carried: git emits its access warning twice (measured),
and the first line is the whole diagnostic.

The function's exit contract is unchanged — it still ALWAYS returns 0, and callers
still count lines rather than reading the exit code as a verdict. The empty-value
pin behavior is unchanged: `rc 0` with an empty value is still reported as `pinned`,
because git honors an empty `core.hooksPath` as a real pin.

**Consumer: `_doctor_check_hooks_path` (`lib/helpers.sh:415`).** Parses the new third
field. A `pinned` row keeps its existing FAIL line and remedy verbatim. An `unknown`
row emits `doctor_fail "<scope>" "cannot determine — <detail>"`. A scope that is
neither pinned nor unknown still gets its independent `doctor_pass`, preserving the
existing property that a finding at one scope never suppresses the other's PASS.

**Consumer: `install_git_hooks_all_repos` (`lib/git_hooks.sh:378`).** An `unknown`
row increments a new counter, appends a line to the summary, and forces rc 2 via the
existing condition at `git_hooks.sh:522`.

Two specifics:

- **Counter name is `_hookspath_unknown`.** The bare name `_unknown` already exists in
  this function for digest-error repos. Reusing it would silently merge two unrelated
  concepts into one count and one summary phrase.
- **No gap attribution under `unknown`.** The existing logic at `git_hooks.sh:439`
  re-labels a repo's missing hooks directory as "a consequence of the pin" when
  `_hookspath > 0`. Under `unknown` no pin has been confirmed, so per-repo gaps stay
  ordinary gaps carrying the normal `install-hooks` remedy. Attributing them to an
  unconfirmed pin would print a remedy the operator cannot act on.

**No call-site enumeration needed.** `install_git_hooks_all_repos`'s return contract
stays `{0,1,2}` — `unknown` folds into the existing rc 2. Both call sites
(`lib/workflows.sh:210` and `:562`) already branch on rc 2. This is deliberately
unlike dotfiles#194, where the contract genuinely widened and a missed call site
resulted.

## Testing

**Item 1** — `tests/scripts/pre_push.bats` gains:

- a diff containing only `scripts/pre-push` sets `needs_test=1` (the self-coverage
  case; fails against the current regex)
- a diff containing only `.gitignore` still exits 0 without running the suite
  (regression guard against over-triggering)

**Item 2** — `tests/setup_env/git_hooks.bats` (function level and sweep consumer) and
`tests/setup_env/unit.bats` (doctor consumer, where `_doctor_check_hooks_path`'s
existing cases live) gain cases for each row of the fixture table below:

| state          | fixture                        | asserts                                              |
| -------------- | ------------------------------ | ---------------------------------------------------- |
| clean          | `GIT_CONFIG_GLOBAL=/dev/null`  | no output; rc 0                                      |
| pinned         | `[core]\n\thooksPath = /tmp/x` | `pinned<TAB>global<TAB>/tmp/x`                       |
| unknown, rc 1  | config path is a **directory** | `unknown<TAB>global<TAB>warning: unable to access …` |
| unknown, rc >1 | `[core` unclosed               | `unknown<TAB>global<TAB>rc=128`                      |

Consumer-level assertions: `unknown` produces a doctor FAIL and a non-zero
`_DOCTOR_FAILED`; `unknown` produces sweep rc 2 and a summary line; and — for the
attribution rule — a repo with no hooks directory under an `unknown` scope reports as
an ordinary gap, not as a consequence of a pin.

**Why the directory fixture and not `chmod 000`.** A `chmod 000` fixture passes as a
normal user and vacuously passes as root, where the file stays readable and the
branch under test never executes. A directory is unreadable-as-a-file for every uid,
so the test is root-safe with no `EUID` guard and cannot silently stop testing
anything in a container that runs as root.

All four fixtures were probed live before this spec was written; the rc and stderr
values in the table are recorded output, not predictions.

`tests/setup_env/git_hooks.bats`'s existing `setup()` already neutralizes
`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`; the new cases set them per-test on top of
that, so a real pin on the developer's machine cannot affect them.

## Risks

**Item 2's rc-1 branch keys on "stderr non-empty," which is looser than an exit
code.** If a future git version emits a benign warning on the otherwise-clean path,
every machine's `-t doctor` goes red simultaneously — a fleet-wide false positive
from a routine `brew upgrade git`. The mitigation is the fixture table: it pins
current behavior at the function level, so a git upgrade that changes stderr on the
clean path fails `make test` on the first machine to run it, rather than failing the
doctor gate everywhere. Accepted because the alternative (rc-only detection) does not
close the gap this change exists to close.

**Item 1 has no meaningful failure mode.** Worst case is running the suite on a push
that did not strictly need it. `scripts/` contains no generated or high-churn files.

## Acceptance

- `make test` passes; test count increases.
- `make lint` exits 0.
- Bash coverage stays ≥ 90%. Only Item 2 can move the figure — `lib/git_hooks.sh`
  and `lib/helpers.sh` are both in `scripts/run-bash-coverage.sh`'s `INCLUDE_FILES`.
  `scripts/pre-push` is not instrumented (nothing under `scripts/` is), so Item 1
  cannot affect coverage in either direction. That absence is itself the separate
  "coverage include-list" backlog row; adding `scripts/` here would risk dropping the
  total below the CI floor and is deliberately out of scope.
- `./setup_env.sh -t doctor` on a clean machine still reports
  `[PASS] system: unset` and `[PASS] global: unset`, and exits with its
  pre-change status.
- An edit to `scripts/pre-push` alone triggers `make test` on push — verified by the
  push of this change itself, which touches that file.

## Related

- dotfiles#191 — bug-scan that found Gap 1
- dotfiles#194 — added the hooksPath detector; deferred Gap 2
- `ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md` — running dossier
- USER.md — "Fail closed on unknown. Unknown ≠ safe."
