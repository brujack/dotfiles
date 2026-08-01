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

## Multi-Lens Review

Reviewed at commit: `125f878` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Item 2's motivating scenario is benign, and the states it actually detects
are already loud. Measured (and independently reproduced in the main session): git
*skips* a config scope it cannot read and carries on without applying it — so a
`chmod 000` config containing `hooksPath = /tmp/PINNED` yields `rev-parse --git-path
hooks` = `.git/hooks` (pin inert) and `git status` rc 0. The two states where a bad
config genuinely hurts (directory-as-config, malformed config) return rc 128 from
every git call, so `_git_hooks_discover` skips all 9 repos and the sweep visibly
reports 0 checked. Of three states: one harmless, one caught by rc alone, and only
directory-as-gitconfig requires the stderr-keying. Decision 1 rejects rc-only because
it "does not close the stated gap" — but the stated gap, measured, is the inert one.
Simpler paths: close Gap 2 as measured-benign and ship Item 1 alone, or rc-only
fail-closed on rc > 1 (~3 lines, no protocol change, no fleet-wide false-positive
risk). Also: the Item 1 acceptance bullet is vacuous — the push of this change
touches five files that already match the old regex, so the suite runs either way.
Reads-it test: Item 2 passes both questions (doctor verdict genuinely changes;
`_update_warn` gives it a durable channel). It fails on proportionality, not plumbing.
Assumption: that git's *clean* path emits nothing on stderr across every git version
in this fleet, not just macOS git 2.55 where the table was probed. Settle by running
`git --version; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git config
--global --get core.hooksPath 2>&1 1>/dev/null | wc -c` on each non-macOS box;
non-zero anywhere refutes stderr-keying outright.
Disposition:

### Ergonomics

Finding: (1) The Item 1 acceptance criterion cannot fail — 5 of 6 files this change
touches already match the current regex, so the operator ticks the box having
confirmed nothing. Replace with a scratch commit touching only `scripts/pre-push` on
a throwaway branch. (2) The `unknown` doctor line is the only FAIL in this check with
no remedy; every sibling FAIL renders its fix inline, and the plausible action here
needs `sudo` — exactly where a half-remedy costs most. (3) The Risks section models a
future-git false positive but not a present-machine unfixable one: a machine whose
system scope is legitimately unreadable stays permanently red, and since doctor's
exit is human-read only (`setup_env.sh:69`, consumed by nothing automated), the cost
is an operator who learns to stop reading the summary. (4) Factual: `git ls-files
scripts/` is 19, not 18; 17 match via `.sh$`, not 16. Exactly two files newly
covered, so the conclusion holds.
Assumption: that on all seven machines an unreadable-scope result is a state the
operator can actually remediate. Most plausibly false on the three work Macs, where
`/etc/gitconfig` may be MDM-owned and rewritten. Settle by running `git config
--system --get core.hooksPath; echo "rc=$?"` (stderr NOT suppressed) and the
`--global` equivalent on each of the seven before implementing; any machine printing
a `warning:` today is one this design turns permanently red.
Disposition:

### Risk

Finding: Same refutation as Goal-Fit, reached independently — the detector, the
sweep's `make install-hooks`, and the git process that runs the hooks are the same
binary, same uid, same files, so "unreadable to the detector" is perfectly correlated
with "inert in practice." Decision 2 rejects `doctor_warn` on an assertion about git's
behavior the spec never probed, and the probe refutes it. The genuine residual is
narrower and advisory-grade: an unreadable scope means the *operator's stated intent*
is unknown, not that hooks are misrouted. Second finding: the Risks section's stated
mitigation has a hole it claims to close — the clean fixture is `GIT_CONFIG_GLOBAL=/dev/null`,
an *empty* config, which cannot trigger any content-dependent warning, so a future git
that warns about content in a real `~/.gitconfig` leaves `make test` green on all seven
machines while all seven doctors go red. Fix: add a fixture using this repo's own
tracked `.gitconfig_mac`/`.gitconfig_linux`. Third: Item 1's acceptance bullet is
vacuous (concurs). Proportionality: Item 1 and Item 2 have opposite risk/benefit
profiles and should not share a merge decision. Minor: "the first line is the whole
diagnostic" is over-generalized (an `[include] path = <directory>` yields a
`warning:` line 1 and a `fatal:` line 2); the stdout/stderr separation mechanism is
unspecified and the obvious `2>&1` one-liner would fold warnings into the pinned
value; line-number drift — call sites are `workflows.sh:206`/`:558` (spec says
210/562) and `install_git_hooks_all_repos` starts at `git_hooks.sh:329` (spec says
378, the hooksPath loop terminator).
Assumption: that git's stderr stays empty on the clean path for a *real, populated*
gitconfig across future versions, not just the empty fixture the spec probed. Settle
by running `git config --system --get core.hooksPath 2>&1 >/dev/null | wc -c` and the
`--global` equivalent on all seven machines against their real config files, and
adding that assertion as a fixture rather than against `/dev/null`.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Main-session verification of the shared finding

The refutation Goal-Fit and Risk reached independently was re-run directly in the main
session rather than accepted on report, per the skill's note that same-model lens
agreement is not itself confirmation:

| fixture (config contains `hooksPath = /tmp/PINNED`) | `rev-parse --git-path hooks` | `git status` |
| --------------------------------------------------- | ---------------------------- | ------------ |
| readable (control)                                   | `/tmp/PINNED` — redirects    | rc 0         |
| `chmod 000`                                          | `.git/hooks` — pin inert     | rc 0         |
| directory-as-config                                  | rc 128                       | rc 128       |

Confirmed. This spec's Problem section for Gap 2 is false as written.

Also confirmed in the main session: `git ls-files scripts/` = 19 with exactly 2
non-`.sh` files (`ls -1` had hidden `scripts/.osx.sh`); call sites are
`workflows.sh:206`/`:558`; `install_git_hooks_all_repos` starts at `git_hooks.sh:329`;
and both scopes on this machine read rc 1 with silent stderr.
