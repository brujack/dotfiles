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

**Gap 2 — an unreadable git config scope is indistinguishable from an unset one.**
`_git_hooks_hookspath_offenders` (`lib/git_hooks.sh:309`) reads `core.hooksPath` at
system and global scope with `git config "--${_scope}" --get core.hooksPath
2>/dev/null || continue`. The `|| continue` collapses every non-zero exit into "key
unset, scope clean," so both consumers — the doctor check and the update sweep —
render `[PASS] <scope>: unset` for a scope git could not read at all.

**What this is NOT.** The backlog row, and the first draft of this spec, framed it as
a concealed hazard: a pin hiding behind an unreadable file, silently redirecting
hooks. That is false, and the measurement is below. Git _skips_ a config scope it
cannot read and carries on without applying it, so an unreadable scope cannot carry
an **effective** pin. The detector, the sweep's `make install-hooks`, and the git
process that actually runs the hooks are the same binary, the same uid, and the same
files — "unreadable to the detector" is perfectly correlated with "inert in
practice." The existing `|| continue` is therefore correct _in effect_: no pin is in
force and hooks resolve normally.

**What remains, honestly stated.** What an unreadable scope actually withholds is the
**operator's stated intent**. Someone may have written a pin they believe is active;
the machine is one `chmod 644` away from that pin becoming real, and nothing today
would report the change. That is a fact worth surfacing on a seven-machine fleet and
it is worth exactly what it costs to surface — no more. It is advisory-grade, not
gate-grade, and this spec treats it as such (Decision 2).

### Measured: an unreadable scope cannot carry an effective pin

Probed live on git 2.55 / macOS 2026-07-31, with a config that **does** contain
`hooksPath = /tmp/PINNED`:

| fixture             | `rev-parse --git-path hooks` | `git status` |
| ------------------- | ---------------------------- | ------------ |
| readable (control)  | `/tmp/PINNED` — redirects    | rc 0         |
| `chmod 000`         | `.git/hooks` — **pin inert** | rc 0         |
| directory-as-config | rc 128                       | rc 128       |

The quiet state is harmless. The states that do hurt are loud everywhere: under
directory-as-config and malformed-config, every git call returns 128, so
`_git_hooks_discover`'s `git -C "${_dir}" rev-parse --git-dir || continue` skips
**every** repo and the sweep reports 0 checked instead of 9. Such a machine is
visibly broken, not quietly passing.

### Measured: rc and stderr per scope state

The backlog row proposed "capture rc and branch: rc 1 = clean, rc > 1 = a
distinguishable cannot-determine record." Probed live on the same git:

| scope state                         | rc  | stderr                                               |
| ----------------------------------- | --- | ---------------------------------------------------- |
| key unset                           | 1   | silent                                               |
| config malformed (`[core` unclosed) | 128 | `fatal: bad config line 1 in file ...`               |
| config unreadable (`chmod 000`)     | 1   | `warning: unable to access '...': Permission denied` |
| config path is a directory          | 1   | `warning: unable to access '...': Is a directory`    |

**An unreadable scope exits 1, not 128** — identical to the clean path. The only
signal distinguishing the two is stderr, which the current code discards via
`2>/dev/null`. This is why detecting the residual at all requires stderr, and why
Decision 1 keys on it; it is also why Decision 2 refuses to let that signal gate
anything.

## Decisions

1. **Detection uses rc and stderr together.** rc alone cannot see the residual at all
   — an unreadable scope exits 1, same as clean. Rejected a readability precheck that
   stats the scope's config file directly (duplicates git's own scope-file resolution
   — `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, XDG paths, `$HOME` quirks — creating a
   second source of truth that can drift from git's).
2. **Cannot-determine is advisory, not a gate.** `doctor_warn` (which increments
   `_DOCTOR_WARN` and leaves `_DOCTOR_FAILED` untouched, so `-t doctor` still exits 0) plus sweep rc 2, which `run_update` already maps to `_update_warn` rather than
   a failed section.

   This reverses the first draft, which chose `doctor_fail` on the strength of
   USER.md's "fail closed on unknown — unknown ≠ safe." That principle governs a
   state whose **safety** is unknown. Here safety is known — measured above, hooks
   resolve correctly — and what is unknown is only the operator's intent. Failing
   closed on a machine whose hooks demonstrably work buys nothing and costs a red
   health gate; on a fleet where `-t doctor` is read by a human and by nothing
   automated (`setup_env.sh:69`), a permanently-red line on a box with an
   MDM-owned `/etc/gitconfig` trains the operator to stop reading the summary. An
   advisory line is what an advisory-grade fact earns.

3. **The advisory line carries a remedy, like every sibling line.** Every other FAIL
   in `_doctor_check_hooks_path` renders its fix inline; a diagnostic that names the
   fault and stops is worth less, especially where the action needs `sudo`. The
   `unknown` line states what to run to see the underlying config for oneself.

4. **Trigger regex adds `^scripts/`, not the two filenames.** Rejected naming
   `scripts/(pre-push|commit-msg)` explicitly — a third extensionless script added
   later would be silently uncovered again, which is the exact failure being fixed.
   `git ls-files scripts/` is 19 files, all executable shell; 17 already match via
   `\.sh$`, so this adds exactly the two hooks today.

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

**stdout and stderr must be captured separately** — the obvious one-liner
`_out="$(git config … 2>&1)"` would fold a warning into the pinned _value_. Use a
temp file, or `{ _err="$(git config … 2>&1 1>&3)"; } 3>&1`. This is named here rather
than left to the plan because it is the difference between a correct value and a
corrupted one on the fleet's own health check.

Only the first stderr line is carried. Git emits its access warning twice (measured),
and on all four probed fixtures the first line is the whole diagnostic — but that is
a property of those fixtures, not of git: an `[include] path = <directory>` inside an
otherwise-valid config yields `warning: unable to access …` on line 1 and `fatal: bad
config line 2 …` on line 2. That shape lands in the `rc >1` branch, which discards
stderr entirely, so it does not bite today. Carrying one line is a deliberate
truncation of a diagnostic that may have more, not a claim that it never does.

The function's exit contract is unchanged — it still ALWAYS returns 0, and callers
still count lines rather than reading the exit code as a verdict. The empty-value
pin behavior is unchanged: `rc 0` with an empty value is still reported as `pinned`,
because git honors an empty `core.hooksPath` as a real pin.

**Consumer: `_doctor_check_hooks_path` (`lib/helpers.sh:415`).** The `read -r` at
`helpers.sh:421` widens to three variables. A `pinned` row keeps its existing FAIL
line and remedy verbatim. An `unknown` row emits:

```
doctor_warn "<scope>" "cannot determine — <detail>; inspect with: git config --<scope> --list"
```

`doctor_warn` leaves `_DOCTOR_FAILED` untouched, so this line never changes `-t
doctor`'s exit status. A scope that is neither pinned nor unknown still gets its
independent `doctor_pass`, preserving the existing property that a finding at one
scope never suppresses the other's PASS.

**Consumer: `install_git_hooks_all_repos` (`lib/git_hooks.sh:329`).** An `unknown`
row increments a new counter, appends a line to the summary, and folds into rc 2 via
the existing condition at `git_hooks.sh:522`. `run_update` already maps rc 2 to
`_update_warn` with the section recorded OK (`workflows.sh:558-562`), so an
`unknown` scope surfaces as a warning in the update summary and in
`~/.dotfiles-update.log` — a durable channel — without marking the section failed.

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
stays `{0,1,2}` — `unknown` folds into the existing rc 2. Both call sites already
branch on rc 2 explicitly: `lib/workflows.sh:206` (`install_git_hooks_all_repos ||
_hooks_rc=$?`, then an `elif` on 2) and `:558` (`PIPESTATUS[0]`, then an `if` on 2).
This is deliberately unlike dotfiles#194, where the contract genuinely widened and a
missed call site resulted.

## Testing

**Item 1** — `tests/scripts/pre_push.bats` gains:

- a diff containing only `scripts/pre-push` sets `needs_test=1` (the self-coverage
  case; fails against the current regex)
- a diff containing only `.gitignore` still exits 0 without running the suite
  (regression guard against over-triggering)

**Item 2** — `tests/setup_env/git_hooks.bats` (function level and sweep consumer) and
`tests/setup_env/unit.bats` (doctor consumer, where `_doctor_check_hooks_path`'s
existing cases live) gain cases for each row of the fixture table below:

| state               | fixture                              | asserts                                              |
| ------------------- | ------------------------------------ | ---------------------------------------------------- |
| clean, empty config | `GIT_CONFIG_GLOBAL=/dev/null`        | no output; rc 0                                      |
| clean, real content | this repo's tracked `.gitconfig_mac` | no output; rc 0                                      |
| pinned              | `[core]\n\thooksPath = /tmp/x`       | `pinned<TAB>global<TAB>/tmp/x`                       |
| unknown, rc 1       | config path is a **directory**       | `unknown<TAB>global<TAB>warning: unable to access …` |
| unknown, rc >1      | `[core` unclosed                     | `unknown<TAB>global<TAB>rc=128`                      |

**The real-content clean fixture is the load-bearing one, not the `/dev/null` one.**
An empty config cannot trigger a content-dependent warning, so a `/dev/null` fixture
alone would stay green through exactly the git upgrade that matters — one that starts
warning about a deprecated key or an `[include]` in a populated `~/.gitconfig`. This
repo already tracks the real thing (`~/.gitconfig` is a symlink to
`dotfiles/.gitconfig_mac`), so asserting empty stderr against it costs one fixture
and closes the case the `/dev/null` fixture structurally cannot reach. Add the
`.gitconfig_linux` variant on the same assertion.

Consumer-level assertions: `unknown` produces a doctor **WARN** and leaves
`_DOCTOR_FAILED` unset (an explicit assertion, since the whole point of Decision 2 is
that this line does not move the exit status); `unknown` produces sweep rc 2 and a
summary line; `run_update` renders the section OK with a warning rather than failed;
and — for the attribution rule — a repo with no hooks directory under an `unknown`
scope reports as an ordinary gap, not as a consequence of a pin.

**Why the directory fixture and not `chmod 000`.** A `chmod 000` fixture passes as a
normal user and vacuously passes as root, where the file stays readable and the
branch under test never executes. A directory is unreadable-as-a-file for every uid,
so the test is root-safe with no `EUID` guard and cannot silently stop testing
anything in a container that runs as root.

Every rc, stderr, and hook-resolution value in this spec is recorded output from a
live probe, not a prediction.

`tests/setup_env/git_hooks.bats`'s existing `setup()` already neutralizes
`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`; the new cases set them per-test on top of
that, so a real pin on the developer's machine cannot affect them.

## Risks

**Item 2's rc-1 branch keys on "stderr non-empty," which is looser than an exit
code.** If a future git version emits a benign warning on the otherwise-clean path,
every machine reports a spurious `[WARN]` simultaneously after a routine `brew
upgrade git`. Two things bound this. First, Decision 2: because the line is advisory,
the blast radius is a noisy line, not a red gate or a failed update section — this is
the single largest reason the advisory framing is worth more than its lost strictness.
Second, the real-content clean fixture: a git upgrade that starts warning about a
populated gitconfig fails `make test` on the first machine to run the suite. The
`/dev/null` fixture alone would not have caught it, which is why it is no longer the
only clean case.

**Item 2's residual value is small, and that is now stated rather than hidden.** It
detects an unreadable scope whose pin, if any, is inert — worth surfacing because the
machine is one `chmod` from that changing, not because anything is broken today. If
implementation reveals the 3-field protocol change is more invasive than sketched,
dropping Item 2 entirely and recording the measurement in
`dotfiles-bug-hunt-leads.md` remains a legitimate outcome, not a failure.

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
- Before implementation, run on each of the seven machines (stderr NOT suppressed):

  ```bash
  git --version
  git config --system --get core.hooksPath; echo "system rc=$?"
  git config --global --get core.hooksPath; echo "global rc=$?"
  ```

  Any machine that prints a `warning:` today would carry a standing `[WARN]` line
  from day one. Under Decision 2 that is noise rather than a broken gate, but it is
  worth knowing before shipping rather than discovering per-machine afterwards. This
  machine is already measured: both scopes rc 1, silent.

- An edit to `scripts/pre-push` alone triggers `make test` on push. **Verified by a
  scratch commit touching only that file, pushed to a throwaway branch** — not by the
  push of this change, which also touches `lib/*.sh` and `tests/**` and therefore
  runs the suite under the old regex regardless. The first draft of this criterion
  claimed exactly that, and it could not have failed; see memory
  `does-the-fix-make-its-own-verification-vacuous`.

## Related

- dotfiles#191 — bug-scan that found Gap 1
- dotfiles#194 — added the hooksPath detector; deferred Gap 2
- `ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md` — running dossier
- USER.md — "Fail closed on unknown. Unknown ≠ safe." Deliberately **not** applied to
  Item 2: see Decision 2 for why a known-safe/unknown-intent state is outside that
  principle's scope.

## Multi-Lens Review

Reviewed at commit: `125f878` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Item 2's motivating scenario is benign, and the states it actually detects
are already loud. Measured (and independently reproduced in the main session): git
_skips_ a config scope it cannot read and carries on without applying it — so a
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
Assumption: that git's _clean_ path emits nothing on stderr across every git version
in this fleet, not just macOS git 2.55 where the table was probed. Settle by running
`git --version; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git config
--global --get core.hooksPath 2>&1 1>/dev/null | wc -c` on each non-macOS box;
non-zero anywhere refutes stderr-keying outright.
Disposition: Addressed (user, 2026-07-31) — premise refutation accepted. Item 2 kept but reframed: the Problem section now states the measured inert-pin result and narrows the claim to unknown operator intent, and Decision 2 flips from doctor_fail to doctor_warn. The vacuous Item 1 acceptance bullet is replaced with a scratch-commit verification. The 'drop Item 2 entirely' option was offered and declined; it is recorded in Risks as a legitimate fallback if implementation proves invasive. Assumption not yet settled — the per-machine stderr probe is now a pre-implementation acceptance item.

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
Disposition: Addressed (user, 2026-07-31) — (1) vacuous acceptance bullet replaced with a scratch-commit verification on a throwaway branch; (2) the unknown line now carries an inspect-with remedy, new Decision 3; (3) the permanently-red concern is resolved at the root by Decision 2's flip to doctor_warn, so an unremediable scope costs a noisy line rather than a red gate; (4) counts corrected to 19 files / 17 matching. Assumption folded into the same pre-implementation seven-machine probe.

### Risk

Finding: Same refutation as Goal-Fit, reached independently — the detector, the
sweep's `make install-hooks`, and the git process that runs the hooks are the same
binary, same uid, same files, so "unreadable to the detector" is perfectly correlated
with "inert in practice." Decision 2 rejects `doctor_warn` on an assertion about git's
behavior the spec never probed, and the probe refutes it. The genuine residual is
narrower and advisory-grade: an unreadable scope means the _operator's stated intent_
is unknown, not that hooks are misrouted. Second finding: the Risks section's stated
mitigation has a hole it claims to close — the clean fixture is `GIT_CONFIG_GLOBAL=/dev/null`,
an _empty_ config, which cannot trigger any content-dependent warning, so a future git
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
Assumption: that git's stderr stays empty on the clean path for a _real, populated_
gitconfig across future versions, not just the empty fixture the spec probed. Settle
by running `git config --system --get core.hooksPath 2>&1 >/dev/null | wc -c` and the
`--global` equivalent on all seven machines against their real config files, and
adding that assertion as a fixture rather than against `/dev/null`.
Disposition: Addressed (user, 2026-07-31) — refutation accepted, same reframing as Goal-Fit. The stated-mitigation hole is closed: a real-content clean fixture using this repo's own tracked .gitconfig_mac/.gitconfig_linux is added alongside the /dev/null one, and the spec now says explicitly that the real-content fixture is the load-bearing one. The stdout/stderr separation mechanism is named in the Design section. The 'first line is the whole diagnostic' claim is corrected to a deliberate truncation with the [include] counter-example. Line numbers corrected to workflows.sh:206/:558 and git_hooks.sh:329. Proportionality point partially accepted: Item 2 is kept, but its residual value is now stated plainly in Risks rather than overclaimed in Problem.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Main-session verification of the shared finding

The refutation Goal-Fit and Risk reached independently was re-run directly in the main
session rather than accepted on report, per the skill's note that same-model lens
agreement is not itself confirmation:

| fixture (config contains `hooksPath = /tmp/PINNED`) | `rev-parse --git-path hooks` | `git status` |
| --------------------------------------------------- | ---------------------------- | ------------ |
| readable (control)                                  | `/tmp/PINNED` — redirects    | rc 0         |
| `chmod 000`                                         | `.git/hooks` — pin inert     | rc 0         |
| directory-as-config                                 | rc 128                       | rc 128       |

Confirmed. This spec's Problem section for Gap 2 is false as written.

Also confirmed in the main session: `git ls-files scripts/` = 19 with exactly 2
non-`.sh` files (`ls -1` had hidden `scripts/.osx.sh`); call sites are
`workflows.sh:206`/`:558`; `install_git_hooks_all_repos` starts at `git_hooks.sh:329`;
and both scopes on this machine read rc 1 with silent stderr.
