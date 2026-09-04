# The EXIT trap in `_dotfiles_run_tmpdir_setup`

One line of production code, `lib/workflows.sh:109`, does two harmful things and no useful
one. It swallows SIGINT and SIGTERM so an operator cannot interrupt `setup_env.sh -t update`,
and it replaces bats' EXIT trap so 35 test sites lose their name when they fail. Deleting it
fixes both and makes a 27-site test idiom — written to work around the second effect, and
inert on the path it was written for — deletable.

Deleting it also makes two _destructive_ workflows interruptible for the first time, which is
a real regression and is paid for by Group A2 rather than accepted.

> **Revision note.** This spec was materially wrong in its first committed form (`0fdbd416`)
> and the correction is recorded rather than quietly applied. It claimed one inert `! grep`
> assertion and proposed a lint scanner to catch that class. There are **zero** inert sites;
> the classifier confused _last line_ with _last executed command_. The scanner and the
> assertion fix are both withdrawn. See M8 and the Multi-Lens Review section.

## Problem

`_dotfiles_run_tmpdir_setup` (`lib/workflows.sh:105-109`) creates the per-run scratch
directory and then installs:

```bash
trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
```

Six functions call it: `run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`,
`run_recreate_venv`, `run_recreate_ruby`, `run_update` (`lib/workflows.sh:120, 225, 270, 295,
302, 340`).

The trap once carried `rm -rf "${_DOTFILES_RUN_TMPDIR}"` as well. That half was removed in
dotfiles#250 so `err_*` files survive long enough to diagnose a FAIL — the spec for that work
(`2026-08-29-update-run-truthfulness-design.md`) says explicitly: "The EXIT trap itself stays.
Dropping `rm -rf` does not remove the trap, so the bats-trap-clobbering those three test
comments describe is unchanged by this spec." So the trap's retention was a deliberate
deferral, not a decision that it is correct.

What remains unsets a shell variable in a shell that is exiting. That is worth nothing, and
it costs two things.

**It suppresses signal-driven abort.** A `trap` handler that does not itself `exit` replaces
the default action, so the signal is absorbed and execution continues. `-t update` therefore
runs to completion after a Ctrl-C or a `kill`, and exits **0** — silent success, not merely a
delayed abort.

**It clobbers bats' EXIT trap.** bats installs `trap -- 'bats_teardown_trap as-exit-trap' EXIT`
per test and reports `not ok` through it. Any bare (non-`run`) call to one of the six
functions replaces that trap; when the test then fails under bats' errexit, the test produces
no TAP line at all — no name, no file, no line number.

**The two are independent harms, not one symptom of the other.** The signal defect is a
production defect an operator meets directly. The reporting defect is a diagnosis cost paid on
every future failure of any of the 35 sites, whether or not anyone ever sends a signal. Either
alone justifies the change.

The repo already knows about the second effect and has been paying for it. Twenty-seven test
sites carry a save/restore idiom written to defend against it, and `lib/workflows.sh:196-205`
carries a production comment explaining that `|| _hooks_rc=$?` is written that way _because_
of it. **The idiom does not work**, for the reason M4 gives.

## Measurements

Every measurement states the population it covered. Where a claim is broader than its
command, the qualifier is at the measurement.

### M1 — The trap swallows SIGTERM

`sigterm_real.sh` sources `lib/workflows.sh`, calls `_dotfiles_run_tmpdir_setup`, prints the
installed trap, then `sleep 4`. Sent `SIGTERM` after 1s:

```
TRAP-NOW: trap -- 'unset _DOTFILES_RUN_TMPDIR' SIGTERM
SURVIVED-SIGTERM
rc=0
```

Control, a byte-identical script with the trap line removed:

```
rc=143
```

**Population:** bash 5.3.15 on the Mac Studio and bash 5.2.21 on the Linux workstation — the
latter being the version `ubuntu-latest` ships. Both platforms, both directions, identical.

### M1b — And it swallows SIGINT, which is the case the Problem section is about

M1 covers `kill`. The operator's case is Ctrl-C, which delivers SIGINT to the **process
group**. That needs job control (`set -m`) so the job has its own pgid; a plain background job
inherits `trap -- '' SIGINT` (SIGINT ignored on entry), which is a third actor again and
cannot answer the question. Measured with process-group delivery, a `sleep` standing in for a
long `brew upgrade` and a second statement standing in for the next update section:

```
trap    pgid=48402 rc=0    out: SECTION-2-RAN|RUN-COMPLETED|
notrap  pgid=50121 rc=130  out:
```

The interrupted run does not merely continue — it completes every remaining section and exits
**0**. This is strictly worse than the SIGTERM case and it is the case an operator actually
hits.

**Population:** bash 5.3.15, Mac Studio, process-group delivery under `set -m`. A first
attempt using `pty.fork` plus a per-process `os.kill` was **inconclusive** — the control
survived too, so the harness never delivered — and is recorded here because an inconclusive
signal probe reads exactly like a negative one.

### M2 — bats loses the test, on both bats versions

Minimal fixture: a function that installs an EXIT trap and returns 1, called bare inside a
`@test`, with controls on either side.

```
1..5
ok 1 A control passes
not ok 3 C bare call, no trap, returns 1
# (from function `fn_no_trap' in file trap_repro.bats, line 9, ...)
ok 4 D run wrapper, callee sets EXIT trap
ok 5 E control after
# bats warning: Executed 4 instead of expected 5 tests
rc=1
```

Test B — the trap case — produced no line. Test C, identical but for the trap, failed
correctly with file and line. Test D shows `run` is immune: the trap is installed in its
subshell.

**Population:** bats 1.14.0 (Studio) and bats 1.10.0 (workstation, = `ubuntu-latest`).
Byte-identical output on both, including the warning.

### M3 — CI cannot detect a vanished test

`.github/workflows/ci.yml:48-55` is:

```bash
COUNT=$(grep -r "^@test" tests/ | wc -l | tr -d ' ')
[ "${COUNT}" -lt 840 ] && exit 1
```

That counts **declarations in source**, not executions. A vanished test does not move it.
`bats` itself exits 1 on the plan mismatch, so `make test` does fail and CI does go red — this
is not a false green. What is lost is attribution: the operator gets
`Executed N-1 instead of expected N` with no file and no test name, across a 1641-test suite.

### M4 — The existing save/restore idiom is inert on the failure path

Twenty-seven sites wrap their bare call as:

```bash
local _bats_exit_trap
_bats_exit_trap="$(trap -p EXIT)"
run_update
eval "${_bats_exit_trap}"
```

errexit fires **at** the failing call, so the `eval` never executes. The idiom covers only the
success path — the path that needed no cover.

```
1..4
ok 1 1 control
ok 2 2 save/restore idiom, callee SUCCEEDS
ok 4 4 control after
# bats warning: Executed 3 instead of expected 4 tests
rc=1
```

Test 3 — the idiom with a failing callee — vanished. This is worse than no guard: a reader
sees mitigation and stops looking.

### M5 — Population of affected sites: 35, all in one file

| file                             | call                  | count | guard                              |
| -------------------------------- | --------------------- | ----- | ---------------------------------- |
| `tests/setup_env/workflows.bats` | bare `run_update`     | 27    | save/restore idiom (inert, per M4) |
| `tests/setup_env/workflows.bats` | bare `run_setup_user` | 8     | none                               |

Four further bare calls (`run_doctor` ×1 in `unit.bats`, `run_check_versions` ×3 in
`workflows.bats`) are **not** affected: neither function calls `_dotfiles_run_tmpdir_setup`.

**Two sites were counted and then removed from this population.** A first scan reported
`install_guards.bats:1149` and `:1176` as unguarded bare `run_setup_user`. Both are lines
_inside_ a `run bash -c "…"` string, already subshell-isolated. The regex matched text in a
quoted heredoc. Recorded because the corrected number (35) and the wrong one (37) are equally
plausible on their face, and only reading the surrounding lines distinguishes them.

### M6 — The 27 `run_update` sites cannot become `run`

All 27 read `_DOTFILES_RUN_TMPDIR` after the call; `run` executes in a subshell, so the
variable does not survive. This is why they are bare, and it is the reason the fix has to be
in production code rather than at the call sites. The 8 `run_setup_user` sites read nothing
after the call and could go either way.

### M7 — Not currently firing

`bats tests/setup_env/workflows.bats` on `cd9c0a6d`: 214 planned, 214 executed, zero `not ok`,
no `bats warning` line. Nothing is vanishing today. The hazard is latent — it arms the _next_
failure of any of the 35 sites to be unattributable, which is exactly when attribution is
wanted.

**Read M7 as scope, not as reassurance.** A green suite is the expected reading here and
carries no information about whether the mechanism works. M2 and M4 establish the mechanism;
M7 only establishes that no site has tripped it yet.

### M8 — RETRACTED. There are zero inert `! grep` sites

**The first committed version of this spec claimed one inert assertion at
`tests/setup_env/workflows.bats:1194` and built a lint scanner around the class. Both were
wrong.** The claim was produced by a classifier that took the **last non-blank, non-comment
line** of a `@test` body as the last command. Bash sets an `if` compound's exit status to its
last _executed_ command, so a `! grep` inside an `if` whose `fi` terminates the body
propagates its status to the test.

Reproduced directly, with the fourth case as the discriminator:

```
not ok 1 A bare ! grep as last cmd
not ok 2 B ! grep inside if, if is LAST cmd, file EXISTS
#   `! grep -q "^softwareupdate" f' failed
ok   3 C same, file ABSENT
ok   4 D ! grep inside if, NOT last cmd in body
```

Case B is `:1194` verbatim and it fails. The only escape would be the file being absent, and
`tests/setup_env/workflows.bats:8` is an unconditional `touch "${MOCK_CALLS_FILE}"` in
`setup()` while `:1189` re-exports the identical path — so the branch always runs.

**Corrected figures, over 39 tracked `.bats` files and 1641 `@test` bodies
(`git ls-files '*.bats'`, cross-checking exactly against CI's own
`grep -r "^@test" tests/ | wc -l`): 81 bare `! grep`, 81 effective, 0 inert.**

There is no defect here, so there is nothing to fix and nothing to gate. The proposed scanner
would have had exactly one hit — a false positive on a working assertion — and the
false-positive class is live rather than theoretical: **30 of the 1641 bodies end in a
compound terminator** (`fi` 18, `done` 10, `}` 2). The scanner was to run in `make lint`
(pre-commit) and `make test` (pre-push), so the first person to write a guarded assertion
would have been blocked from both committing and pushing, with the error naming `refute_grep`
as the remedy for something that already worked.

The backlog row that prompted this work read "24 bare `! grep` and 27 bare `run_update` calls
remain in `tests/setup_env/workflows.bats`". The counts are right for that file. Both hazard
readings are wrong: the `! grep` sites are all effective, and the `run_update` sites are
hazardous for an entirely different reason than the row gives.

### M9 — Two callers are delete-then-rebuild, and Group A makes their window interruptible

`run_recreate_venv` (`lib/workflows.sh:295`) and `run_recreate_ruby` (`:302`) both call
`_dotfiles_run_tmpdir_setup`, and both destroy before they rebuild:

- `recreate_ruby` — `lib/developer.sh:406`, `rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"`,
  followed by a from-source compile.
- `recreate_python_venv` — `lib/developer.sh:541`, `pyenv virtualenv-delete -f`, followed by
  a create and a `uv sync` of 269 packages.

The repo already names the window, at `lib/developer.sh:419-424`:

> `install_ruby` soft-fails on rbenv/ruby-install errors (returns 0 with a warning) so that
> initial setup continues. `recreate_ruby` has already deleted the old installation, so a
> silent failure here leaves the machine with no Ruby at all — verify explicitly.

Today the trap makes that window uninterruptible-and-complete. Under Group A alone it becomes
interruptible-and-destructive: an abort after the delete and before the verification at `:422`
leaves no Ruby, or a venv that exists and is empty. Group A2 exists because of this.

**Population:** read from the source, not executed — running a real `recreate_ruby` to
observe the window would destroy this machine's Ruby, which is precisely the finding. The
mechanism was confirmed on a synthetic stand-in (delete a resource, spawn a 3s rebuild,
SIGTERM at 1s): with the trap, `rc=0` and the resource present; without, `rc=143` and every
statement after the interrupted step unreached.

### M10 — Today's interrupted-run record is false, not merely absent

`_update_record_end` writes `FAIL` for any non-zero status (`lib/update_summary.sh:175`), and
`_update_summary` appends to `~/.dotfiles-update.log` and calls `_ledger_write_dotfiles_entry`
(`:598`). Because a Ctrl-C'd run currently continues, it manufactures FAIL rows for sections
the operator killed and pushes them into the state-ledger CMDB.

So the "lost diagnostic record" that Group A appears to cost is a record that is currently
**wrong**. Group D says this rather than framing the change as a pure loss.

## Design

### Group A — delete the trap

`lib/workflows.sh:109`: delete the line. Nothing replaces it.

Three consequences, all intended:

- SIGINT/SIGTERM abort the run.
- No caller of `_dotfiles_run_tmpdir_setup` replaces the caller's EXIT trap, so all 35 bare
  sites report normally when they fail.
- `_DOTFILES_RUN_TMPDIR` persists to process exit. Harmless: the process is exiting, bats runs
  each `@test` in its own process so nothing leaks between tests, and no `-z`/`+x`/`-n` guard
  anywhere reads the variable's unset-ness.

After this, `lib/` has **zero** function-scope EXIT traps. `lib/developer.sh:72` keeps its
EXIT trap and is correct: it sits inside a `( )` subshell with a header comment
(`lib/developer.sh:38-44`) citing `shell.md`'s RETURN-trap entry for why. It is the worked
precedent for the right shape, not an exception. That invariant is what G3 pins.

The tmpdirs themselves are unaffected — dotfiles#250 already removed the `rm -rf`, so they
accumulate today and will accumulate identically after. The durable-run-root work stays
deferred where it is.

Two comments go stale and are updated in the same commit: `lib/workflows.sh:196-205` (which
explains `|| _hooks_rc=$?` as a workaround for this clobber — the code stays, being
independently correct and matching the surrounding `setup_claude_mcp || return 1` style, but
its stated reason is gone) and `tests/setup_env/ledger_integration.bats:350`.

### Group A2 — an explicit abort guard for the two destructive windows

M9's window must not become interruptible without the operator being told what state the
machine is in. Add a guard used only by `recreate_ruby` and `recreate_python_venv`, spanning
from immediately before the delete to immediately after the post-install verification.

Required properties, each of which is a test in Verification:

1. **The handler exits.** This is the whole difference from the trap being deleted. A handler
   that returns re-creates the defect one function down. Exit non-zero.
2. **Assert non-zero, never a literal.** 130 for INT and 143 for TERM are conventional, not
   portable, and this suite runs on macOS and Linux.
3. **It prints what state the machine is in**, naming the deleted artifact and the command
   that recovers it — `setup_env.sh -t recreate-ruby` / `-t recreate-venv`, which are
   idempotent and are the recovery path. The message goes to stderr.
4. **It is removed on every exit path**, normal and early-return alike, so it cannot fire for
   an unrelated later signal. A `trap ... INT TERM` is shell-global, exactly like the one
   Group A deletes; the guard is a scoped window, not a function-lifetime install.
5. **It does not wrap the whole function.** Only the destroy-to-verified span. Before the
   delete there is nothing to warn about, and a plain abort is correct.

A `( )` subshell — the `lib/developer.sh:72` shape — is **not** available here: exiting a
subshell does not exit the parent, and property 1 requires the process to die. The
install/remove pair is therefore explicit, and property 4 is the one a future edit will break,
so it gets its own test rather than a comment.

### Group B — delete the dead idiom

In `tests/setup_env/workflows.bats`, delete the 27 save/restore blocks (`local
_bats_exit_trap`, the `trap -p EXIT` capture, the `eval`) and the comments introducing them.
**The calls stay bare** — M6.

Leave the 8 bare `run_setup_user` sites as they are; they become safe under Group A, and
converting them to `run` would be churn on tests that pass.

**No `! grep` site is touched, in this file or any other** — M8. `tests/setup_env/
install_guards.bats` is not touched either — M5.

### Group C — guards

**G1, mechanism.** `_dotfiles_run_tmpdir_setup` leaves the caller's EXIT, INT and TERM traps
identical. Capture `trap -p` for each of the three before and after, compare.

All three signals, not just EXIT: a future change that installs an INT/TERM handler without
`exit` reintroduces the M1/M1b defect while leaving EXIT clean, and an EXIT-only assertion
would pass over it.

**G2, consequence.** A script that calls `_dotfiles_run_tmpdir_setup` and then blocks still
dies on SIGTERM, exit status non-zero. G2 is the behavioural positive control for G1, which is
a mechanism assertion: G1 alone is satisfiable by a trap installed and immediately restored
around the `mktemp`, which would leave signal handling broken.

**G3, the class invariant.** G1 and G2 close the one instance. A trap added to any _other_
function on the 35 sites' call paths — `_update_record_start`, `install_ruby`, a future helper
— re-arms all 35 at once with both green. Group A's own invariant is the class-level guard, so
pin it: **no function-scope EXIT trap in `lib/`.**

Scope from `git ls-files 'lib/*.sh'`, under
`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` (`git -C` does not
override an exported `GIT_DIR`, and `scripts/pre-push` runs `make test`, so a push from a
worktree would otherwise resolve the scope against the wrong repository). Assert the derived
list is non-empty before iterating. A `trap ... EXIT` inside a `( )` subshell is permitted;
one at function scope is not.

Group A2's guard traps INT and TERM, not EXIT, so it does not collide with this invariant.
That is a property worth stating in the scanner's own message, since the next reader will
otherwise expect a conflict.

**This replaces a withdrawn scanner, and the difference is the point.** The withdrawn one
gated `! grep` position: its corpus was 81 sites with 0 defects, its one hit was a false
positive, and it approximated control flow by line position. This one gates a property Group A
establishes, over a corpus of 2 live traps (`lib/workflows.sh:109`, deleted by this change;
`lib/developer.sh:72`, permitted), with an unambiguous predicate. It has a live positive
before Group A lands and a real steady-state invariant after.

### Group D — docs

- `CLAUDE.md`, the `-t update` row: SIGINT/SIGTERM now abort the run.
- `CLAUDE.md`, the `recreate-venv` and `recreate-ruby` rows: an interrupt inside the rebuild
  window aborts with a message naming the recovery command.
- `docs/adr/0027-update-run-exit-code-from-section-status.md`: cross-reference. ADR-0027
  defines what a non-zero exit from `-t update` means, and this change adds a case — an
  interrupted run exits non-zero with **no summary, no `~/.dotfiles-update.log` entry, and no
  state-ledger entry**, because `_update_summary` and `_ledger_write_dotfiles_entry` are never
  reached.

  State it with M10 attached, or the entry reads as a pure regression: today the same
  interrupt produces a **complete summary containing FAIL rows for sections the operator
  killed**, and writes them to the CMDB. The change trades a false record for no record. A
  partial-but-true record is the better end state and is Deferred.

## Verification

Each case states what makes it fail.

**V1 — G1 goes red with the trap restored.** Restore `lib/workflows.sh:109`, run G1, confirm
failure; delete it again, confirm `ok`. The pre-fix failure manifests as the test _vanishing_
rather than as `not ok` — that is the defect demonstrating itself, and the run's
`bats warning: Executed N-1 instead of expected N` plus non-zero rc is the signal. Both
outcomes are red; do not read the missing `not ok` as a pass.

**V2 — G2 goes red with the trap restored.** Same mutation. Pre-fix `SURVIVED-SIGTERM` rc 0;
post-fix dead, rc non-zero. Both halves asserted — a G2 checking only the post-fix direction
would pass against a trap that never installed.

**V3 — G3 finds `lib/workflows.sh:109` before Group A deletes it, and nothing after.** Run the
scanner on the pre-Group-A tree: exactly 1 hit. After: 0 hits, with the derived `lib/*.sh` list
asserted non-empty. This is the live positive; the scanner is not shipped on a zero.

**V4 — G3 does not flag the permitted subshell trap.** `lib/developer.sh:72` must be absent
from the findings both before and after. Without this, a scanner that simply greps `trap.*EXIT`
passes V3 by flagging both and still "goes to 0" after Group A only if someone also deletes a
correct trap.

**V5 — G3 catches a newly-introduced function-scope trap.** Add one to any `lib/*.sh` function,
confirm it is named, remove it. Distinct from V3: V3 shows the scanner finds the instance that
exists, V5 shows it finds one it has never seen.

**V6 — the abort guard exits, and says what was destroyed.** Drive `recreate_ruby`'s guarded
window with the destructive call and the rebuild both stubbed, send SIGTERM inside the window,
and assert three things: the process exits **non-zero**, stderr names the deleted artifact and
the recovery command, and the statements after the window did not run. A guard that prints and
_continues_ passes a message-only assertion, which is the exact defect Group A removes.

**V7 — the abort guard is removed on the normal path.** Run the same function to completion
with no signal, then assert `trap -p INT` and `trap -p TERM` are empty in the caller. This is
property 4, and it is the one a later edit breaks silently.

**V8 — the abort guard is removed on an early-return path.** Same as V7 with the rebuild
stubbed to fail, so the function returns non-zero before its normal end. Without this, a guard
removed only at the happy-path end passes V7 and leaks on every failure.

**V9 — the 27 idiom deletions move no verdict.** `bats tests/setup_env/workflows.bats` before
and after Group B. Baseline on `cd9c0a6d` is 214 planned, 214 executed, 0 `not ok`, no warning
(M7). Compare the full `ok`/`not ok` **set**, not the count — a count is equal under a swap.

**V10 — full suite, plan equals executed.** `make test`. Assert both that no
`bats warning: Executed` line appears **and** that the plan line is present and equals the
expected total. The absence assertion alone passes over a suite that never ran; the plan line
is what makes it an assertion about a measurement rather than about silence.

**V11 — a bare call that fails now reports by name.** Stage a `run_update` section FAIL, call
it bare in a fixture, assert the outer `bats` output carries `not ok` **with the test's name**.
This is the property the whole change exists to produce, and neither G1 nor G2 asserts it —
G1 is about traps, G2 about signals. Pre-fix this fixture vanishes; post-fix it names itself.

## Deferred

- **A partial summary and ledger entry on interrupt.** M10 says today's record is false and
  Group D says the change makes it absent. A true partial record is better than either, and
  needs a handler that renders and _then_ exits non-zero — a different mechanism from Group
  A2's abort guard, which deliberately does not touch the summary. Do not smuggle it in as
  A2's implementation.
- **Whether an absent ledger entry creates false drift findings.** This repo installs a weekly
  `ledger-drift` cadence agent (`lib/workflows.sh:219`) and `_doctor_check_ledger_drift_cadence`
  (`lib/helpers.sh:392`), whose input is entity freshness. If a machine's freshness derives
  from the entry `_update_summary` writes at `lib/update_summary.sh:598`, an operator who now
  aborts updates stops refreshing it and the Monday agent reports stale-entity findings caused
  by the interrupt rather than by drift. Settle it by reading `ai-config`'s
  `ledger_drift_check.sh` for the field it ages against, then comparing `ledger status` across
  an aborted `-t update`. Unresolved, and it is a _new_ path because Ctrl-C becomes reachable
  for the first time under this change.
- **The 8 bare `run_setup_user` sites.** Safe under Group A; convertible to `run` +
  `[ "$status" -eq 0 ]` if a future change makes any of them read `_DOTFILES_RUN_TMPDIR`.
- **Any `! grep` work at all.** M8 retires the premise. 81 sites, 81 effective. `refute_grep`
  remains the better idiom for a _new_ assertion because it names what it found on failure,
  but that is a style preference with no defect behind it, and no gate should enforce it
  without a measured corpus for all three negation forms (`! grep`, `! [[ ]]`, `! command`).

## Related

- [ADR-0027](../../adr/0027-update-run-exit-code-from-section-status.md) — the exit contract
  this change adds a case to.
- [2026-08-29-update-run-truthfulness-design.md](2026-08-29-update-run-truthfulness-design.md)
  — removed the trap's `rm -rf` half and explicitly deferred the trap itself.
- [2026-08-31-update-run-cd-guards-design.md](2026-08-31-update-run-cd-guards-design.md) —
  where `refute_grep` was added, and where the backlog row that prompted this work was written.
- `~/.claude/standards/shell.md`, "`trap ... RETURN` is NOT function-scoped" — the sibling
  trap-scope defect, the origin of `lib/developer.sh:72`'s subshell shape, and the closest
  precedent for Group A2's requirement that a cleanup mechanism not be worse than what it
  cleans.
- `~/.claude/standards/behavior.md`, "A guard whose output cannot alter what runs after it is
  not a guard" — M4's idiom is that shape: it executes after the decision it was meant to
  affect.
- `~/.claude/standards/behavior.md`, "The artifact carries the field, and its value is
  compatible with both causes" — M8's retraction is that shape: the last _line_ of a test body
  and its last _executed command_ are the same value for most bodies and differ for 30 of them.

## Multi-Lens Review

Reviewed at commit: `0fdbd416` (Step 7 self-review commit, before Step 8 dispatch)

Round 1 found two defects in the spec, one of which retracted a whole section. Both the
Goal-Fit and Ergonomics lenses independently concluded the proposed `! grep` scanner should
not ship, by different routes — Goal-Fit on proportionality (population 1, fixed in the same
PR, steady state 0), Ergonomics on correctness (the population is 0 and the one hit is a false
positive). Every finding below was re-derived here before being accepted.

### Goal-Fit

Finding: Build Group A; split the `! grep` scanner out as a separate concern — its live
population is 1, Group B fixed that 1 in the same PR, its steady state is 0 over 80 sites the
spec itself called "not defects", and it gated one of three negation forms while reading as
coverage of the class. Separately, the spec's premise is stronger than it claimed: it measured
SIGTERM only and explicitly declined SIGINT, which is the case the Problem section is about.
Under process-group delivery an interrupted run completes every remaining section and exits
**0** — silent success, a worse class than the delayed abort that was measured. Verified the
supporting claims independently: `git ls-files '*.bats'` = 39 vs `'tests/**/*.bats'` = 37; two
live traps in `lib/`, with `lib/developer.sh:72` genuinely inside a `( )`; and no `-z`/`+x`
guard anywhere reads `_DOTFILES_RUN_TMPDIR`'s unset-ness, so nothing depends on the trap's
only remaining effect.

Assumption: That an interrupted `-t update` producing no summary, no `~/.dotfiles-update.log`
entry and no state-ledger entry is inert for downstream consumers. Ctrl-C becomes reachable
for the first time under this change, and this repo runs a weekly `ledger-drift` cadence agent
whose input is entity freshness — so if freshness derives from the entry `_update_summary`
writes, an operator who now aborts updates would trigger stale-entity findings caused by the
interrupt rather than by drift. Settles by reading `ai-config`'s `ledger_drift_check.sh` for
the field it ages against, then comparing `ledger status` across an aborted `-t update`.

Disposition: **Addressed.** The scanner is withdrawn entirely rather than split out — the
Ergonomics finding below supersedes the proportionality argument with a correctness one. M1b
added with the process-group SIGINT measurement, re-derived here (`trap` rc 0 and
`SECTION-2-RAN|RUN-COMPLETED`; `notrap` rc 130) after a first pty-based probe of this
session's own was inconclusive in a way that reads like a negative result. The assumption is
recorded in Deferred as an open question rather than resolved, because it is a new path
created by this change and the answer lives in another repo.

### Ergonomics

Finding: M8 is wrong on the mechanism. Bash sets an `if` compound's exit status to its last
executed command, so a body-terminal `if` propagates the `! grep`'s status; `:1194`'s branch
always runs because `workflows.bats:8` unconditionally `touch`es `MOCK_CALLS_FILE`. The real
figure is 81 bare `! grep`, **81 effective, 0 inert** — there is no defect and nothing to
gate. The proposed scanner's sole positive was therefore a false positive, its predicate being
line position standing in for control flow, and the false-positive class is live: 30 of 1641
bodies end in a compound terminator (`fi` 18, `done` 10, `}` 2). It was to run in `make lint`
(pre-commit) and `make test` (pre-push), so the first guarded assertion anyone wrote would have
blocked both a commit and a push. Separately, the "lost diagnostic record" is worth less than
the spec claimed: `_update_record_end` writes FAIL for any non-zero and `_update_summary`
pushes to the state-ledger, so a Ctrl-C'd run today manufactures FAIL rows for sections the
operator killed. That record is not merely lost after the change — today it is false.

Assumption: That an operator interrupting a long `-t update` prefers a clean immediate abort
over a partial record, since deletion alone forecloses the render-then-exit alternative.
Settles empirically by inspecting `~/.dotfiles-update.log` for bursts of consecutive section
FAILs in one run (the interrupt signature) rather than isolated section failures.

Disposition: **Addressed.** M8 rewritten as an explicit retraction carrying the four-case
reproduction and the 30-of-1641 figure; the scanner and the `:1194` edit are both withdrawn;
Group B now states that no `! grep` site is touched. The FAIL-row finding is added as M10 and
Group D now states the trade as false-record-for-no-record rather than as a pure loss. The
assumption is not resolved — the render-then-exit alternative is named in Deferred so deletion
does not silently foreclose it.

### Risk

Finding: Group A is correct for `run_update` and materially riskier for two callers the spec
never examined. `run_recreate_venv` and `run_recreate_ruby` also call
`_dotfiles_run_tmpdir_setup` and are both delete-then-rebuild —
`rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"` at `lib/developer.sh:406` and
`pyenv virtualenv-delete -f` at `:541` — and the repo's own comment at `:419-424` already names
the window ("recreate_ruby has already deleted the old installation, so a silent failure here
leaves the machine with no Ruby at all"). Today the trap makes that window
uninterruptible-and-complete; after Group A it is interruptible-and-destructive, and all seven
verification cases exercised `run_update` only. Two smaller findings: V6's "assert no bats
warning appears" passes on empty output as readily as on a clean run; and G1/G2 close the one
instance rather than the class, since a trap added to any other function on those call paths
re-arms all 35 sites with both guards green — while the spec already observes that `lib/` will
have zero function-scope EXIT traps, which is the class-level invariant and was left unpinned.

Assumption: That SIGINT delivered to a foreground `setup_env.sh` is currently swallowed — the
spec measured SIGTERM only, and this lens's own probe returned `trap -- '' SIGINT`, meaning
the handler was never installed in that actor because the signal was already ignored on entry.
If the run already aborts on Ctrl-C, half the stated problem does not exist. Settles under a
pty or with process-group delivery.

Disposition: **Addressed.** The destructive window is now M9 and is paid for by a new Group A2
— an explicit INT/TERM abort guard scoped to the destroy-to-verified span of `recreate_ruby`
and `recreate_python_venv`, with five stated properties and four verification cases (V6-V8
plus the non-zero-not-literal rule). The operator chose this over accepting the abort, over
deferring the two callers, and over re-measuring first. V10 now asserts the plan line equals
the expected total rather than only the absence of a warning. G3 is repurposed from the
withdrawn `! grep` scanner to exactly the class invariant this lens identified — no
function-scope EXIT trap in `lib/` — with V4 pinning that the permitted subshell trap at
`lib/developer.sh:72` is not flagged. The assumption is **resolved, not deferred**: measured
here with process-group delivery under `set -m`, SIGINT is swallowed and the run exits 0, so
the premise holds and is now M1b.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. There are no comparison
arms, no judge or evaluator component, and the acceptance criteria are concrete commands with
stated failure conditions (V1-V11). The G3 scanner is a mechanical checker with an unambiguous
predicate, not an evaluator exercising judgement.
