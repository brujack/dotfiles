# The EXIT trap in `_dotfiles_run_tmpdir_setup`

One line of production code, `lib/workflows.sh:109`, does two harmful things and no useful
one. It swallows SIGINT and SIGTERM so an operator cannot interrupt `setup_env.sh -t update`,
and it replaces bats' EXIT trap so 35 test sites lose their name when they fail. Deleting it
fixes both and makes a 27-site test idiom — written to work around the second effect, and
inert on the path it was written for — deletable.

Deleting it also makes two _destructive_ workflows interruptible for the first time. That was
believed to be a regression and is not: measurement under the correct actor shows the
toolchain is lost with or without the trap. It costs a documentation line, not a mechanism.

> **Revision note.** This spec was materially wrong in its first committed form (`0fdbd416`)
> and the correction is recorded rather than quietly applied. It claimed one inert `! grep`
> assertion and proposed a lint scanner to catch that class. There are **zero** inert sites;
> the classifier confused _last line_ with _last executed command_. The scanner and the
> assertion fix are both withdrawn. See M8 and the Multi-Lens Review section.
>
> **Round 2 removed a second section.** The revision above added a Group A2 abort guard for
> the two delete-then-rebuild workflows, on a measurement (M9) that used single-process
> SIGTERM — the very actor error M1b had corrected four sections earlier. Under
> process-group delivery the toolchain is destroyed with or without the trap, so the guard
> bought one stderr line rather than a machine state, while clobbering bats' own SIGINT
> handler at 35 call sites. Group A2 is withdrawn. See M9 and the round-2 review.

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

### M9 — Two callers are delete-then-rebuild, and the trap does NOT protect them

`run_recreate_venv` (`lib/workflows.sh:295`) and `run_recreate_ruby` (`:302`) both call
`_dotfiles_run_tmpdir_setup`, and both destroy before they rebuild:

- `recreate_ruby` — `lib/developer.sh:406` `rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"` on
  macOS, `:415` `rbenv uninstall -f` on Linux, then a from-source compile.
- `recreate_python_venv` — `lib/developer.sh:541` `pyenv virtualenv-delete -f`, then a create
  and a `uv sync` of 269 packages.

The repo names the window at `lib/developer.sh:419-424`: *"recreate_ruby has already deleted
the old installation, so a silent failure here leaves the machine with no Ruby at all — verify
explicitly."*

**An earlier revision of this section claimed the trap made that window
uninterruptible-and-complete, and that Group A therefore introduced a destructive regression
needing its own guard. That claim was false, and it was false for the reason M1b exists.** It
was measured with `SIGTERM` delivered to the shell alone — the M1 harness — so the rebuild
child never received the signal and completed for reasons unrelated to the trap. Re-measured
under process-group delivery, which is what an operator's Ctrl-C does, against a shape
mirroring `recreate_ruby` (trap, delete, child rebuild, then the real `:422`/`:426`
verification):

```
trap    rc=1    artifact_present=NO   log=[STEP1-DELETE|STEP2-REBUILD-RETURNED|STEP3-VERIFY-ERROR-PRINTED|]
notrap  rc=130  artifact_present=NO   log=[STEP1-DELETE|]
```

**`artifact_present=NO` in both arms.** The trap never protected the toolchain. Its only
effect is that execution reaches the verification branch and prints the error the repo already
wrote for this case; without it the shell dies at the interrupted step. The delta is one
stderr line.

So there is no destructive regression to pay for, and the abort guard this section previously
justified is withdrawn. What remains is a documentation obligation, discharged in Group D: an
interrupted recreate leaves the toolchain deleted, and the same command recovers it.

**Population:** bash 5.3.15, Mac Studio, process-group delivery under `set -m`, against a
stand-in rather than a real `ruby-install` or `uv sync` — running those for real would destroy
this machine's toolchain, which is the finding itself. The stand-in is a plain `sleep`, so this
measurement assumes those tools do not install their own SIGINT handling; if either did, it
would survive the interrupt and the earlier claim would be partially right. That is recorded
in Deferred rather than asserted away, because it does not change the decision — a guard whose
value is one message is not worth its mechanism either way.


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

**G3, the class invariant.** G1 and G2 close the one instance. A trap added to any *other*
function on the 35 sites' call paths — `_update_record_start`, `install_ruby`, a future helper
— re-arms all 35 at once with both green. Group A's own invariant is the class-level guard, so
pin it: **no unreviewed `trap ... EXIT` in `lib/`.**

**It is an allowlist ratchet, deliberately, not a scope-deciding scanner.** Two review rounds
independently rejected a position-based predicate, and the same objection applies here: after
Group A the only textual difference between `lib/developer.sh:72`'s permitted trap and a
function-scope one is indentation, and deciding subshell containment from text needs a bash
parser this repo does not have. Approximating it by position is exactly what the withdrawn
`! grep` scanner died of.

So the check does not decide scope at all. It enumerates every `trap` naming `EXIT` in
`git ls-files 'lib/*.sh'` and requires the set to equal a recorded allowlist, each entry
carrying a one-line reason. A new trap fails until a human adds it with a justification —
which is the same shape this repo already uses for `shellcheck disable=` directives, and it
cannot be fooled by formatting because it never tries to infer structure.

Scope derivation uses `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`
(`git -C` does not override an exported `GIT_DIR`, and `scripts/pre-push` runs `make test`, so
a push from a worktree would otherwise resolve against the wrong repository), and asserts the
derived file list is non-empty before iterating.

**Contrast with the scanner this replaces.** That one gated `! grep` position: corpus 81
sites, 0 defects, its one hit a false positive, predicate approximating control flow. This one
gates a property Group A establishes, over a corpus of 2 live traps — `lib/workflows.sh:109`,
deleted by this change, and `lib/developer.sh:72`, allowlisted — with no inference at all.


### Group D — docs

- `CLAUDE.md`, the `-t update` row: SIGINT/SIGTERM now abort the run.
- `CLAUDE.md`, the `recreate-venv` and `recreate-ruby` rows: an interrupt during the rebuild
  leaves the toolchain **deleted**, and re-running the same command recovers it. State it
  plainly rather than as a warning against interrupting — per M9 the toolchain is lost on
  interrupt today as well, and the only thing that changes is that the shell now stops instead
  of continuing to a verification error. For `recreate-venv`, note that recovery must repeat
  any `--venv-name` the original invocation carried; a bare re-run rebuilds `ansible` instead
  (`lib/developer.sh:547` gates the `uv sync` on that name).
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

Each case states what makes it fail. Eight cases, renumbered after Group A2's withdrawal took
three of them with it.

**V1 — G1 goes red with the trap restored.** Restore `lib/workflows.sh:109`, run G1, confirm
failure; delete it again, confirm `ok`. The pre-fix failure manifests as the test *vanishing*
rather than as `not ok` — that is the defect demonstrating itself, and the run's
`bats warning: Executed N-1 instead of expected N` plus non-zero rc is the signal. Both
outcomes are red; do not read the missing `not ok` as a pass.

**V2 — G2 goes red with the trap restored.** Same mutation. Pre-fix `SURVIVED-SIGTERM` rc 0;
post-fix dead, rc non-zero — asserted as non-zero, never as the literal 143, since signal
numbers are not portable and this suite runs on macOS and Linux. Both halves asserted: a G2
checking only the post-fix direction would pass against a trap that never installed.

**V3 — G3 fails on an un-allowlisted trap.** With `lib/workflows.sh:109` restored and absent
from the allowlist, G3 reports exactly that line. This is the live positive; the check is not
shipped on a zero.

**V4 — G3 passes on the allowlisted trap alone.** After Group A, the only `EXIT` trap in
`lib/` is `lib/developer.sh:72`, which is on the allowlist with its reason, and G3 is clean —
with the derived `lib/*.sh` list asserted non-empty, so "clean" cannot mean "scanned nothing".

**V5 — G3 catches a newly-introduced trap wherever it sits.** Add a `trap ... EXIT` to a
`lib/*.sh` function, confirm it is named; move the same line inside a `( )` subshell, confirm
it is **still** named. The second half is the point: G3 does not decide scope, so a subshell
trap is a finding until someone allowlists it. That is the intended behaviour and V5 pins it,
so a later "improvement" that starts inferring containment fails this case.

**V6 — the 27 idiom deletions move no verdict.** `bats tests/setup_env/workflows.bats` before
and after Group B. Baseline on `cd9c0a6d` is 214 planned, 214 executed, 0 `not ok`, no warning
(M7). Compare the full `ok`/`not ok` **set**, not the count — a count is equal under a swap.

**V7 — full suite, plan equals executed.** `make test`. Assert both that no
`bats warning: Executed` line appears **and** that the plan line is present and equals the
expected total. The absence assertion alone passes over a suite that never ran; the plan line
is what makes it an assertion about a measurement rather than about silence.

**V8 — a bare call that fails now reports by name.** Stage a `run_update` section FAIL, call
it bare in a fixture, assert the outer `bats` output carries `not ok` **with the test's name**.
This is the property the whole change exists to produce, and neither G1 nor G2 asserts it —
G1 is about traps, G2 about signals. Pre-fix this fixture vanishes; post-fix it names itself.


## Deferred

- **A partial summary and ledger entry on interrupt.** M10 says today's record is false and
  Group D says the change makes it absent. A true partial record is better than either, and
  needs a handler that renders and *then* exits non-zero. Group A2 was withdrawn without
  building it, so this stays open rather than foreclosed.
- **The interrupt UX for the two recreate workflows**, if it is wanted at all. M9 establishes
  the toolchain is lost either way, so the only question is whether the operator should be
  *told* at the moment of interrupt rather than reading it in `CLAUDE.md`. Three problems must
  be solved together before any mechanism is worth it, and each was found by review of the
  withdrawn Group A2: a `trap ... INT TERM` in a lib function clobbers its caller's handler
  (`trap -` clears, it does not restore, and bats installs `bats_interrupt_trap` in every
  test); bash defers a pending trap until the foreground child returns, so under
  single-process delivery the message fires *after* a successful rebuild and would be false;
  and `recreate_python_venv` has no post-install verification, so the window has no defined
  end. A `( )` subshell wrapper solves the first structurally — measured: the caller's handler
  survives intact — but not the other two.
- **`recreate_python_venv` has no post-install verification.** `recreate_ruby` verifies at
  `lib/developer.sh:422-429` precisely because `install_ruby` soft-fails; the venv path has no
  equivalent, so a partial rebuild reports success. Independent of this spec and probably the
  more valuable of the two follow-ups.
- **Whether a real `ruby-install` / `uv sync` child survives SIGINT to the process group.** M9
  used a `sleep` stand-in. If either installs its own signal handling the child would survive,
  and the pre-correction claim would be partially right. It does not change this design — a
  guard worth one message is not worth its mechanism either way — but it changes the Group D
  wording, since "the toolchain is left deleted" would then be conditional. Settle with a
  throwaway `ruby-install ruby X --install-dir /tmp/probe` under `set -m`, interrupted at the
  group.
- **The 8 bare `run_setup_user` sites.** Safe under Group A; convertible to `run` +
  `[ "$status" -eq 0 ]` if a future change makes any of them read `_DOTFILES_RUN_TMPDIR`.
- **Any `! grep` work at all.** M8 retires the premise. 81 sites, 81 effective. `refute_grep`
  remains the better idiom for a *new* assertion because it names what it found on failure,
  but that is a style preference with no defect behind it, and no gate should enforce it
  without a measured corpus for all three negation forms (`! grep`, `! [[ ]]`, `! command`).

**Resolved and closed, recorded here because it was Deferred in an earlier revision:** whether
an absent ledger entry creates false drift findings. It does not, and the reason is worse than
the concern. `_ledger_write_run_entry` passes the **per-run UUID** as `entity_id`
(`lib/update_summary.sh:437`), so every recorded run creates a *new* entity and none is ever
refreshed — measured, 7 `dotfiles` entities, all distinct UUIDs, two already reported STALE at
35d and 47d. An aborted run therefore refreshes nothing because nothing is refreshed. The
separate defect this exposes — `ledger drift` can never clear a `dotfiles` entity, so the
weekly cadence agent reports drift forever — is filed in this repo's backlog rather than
carried here.


## Related

- [ADR-0027](../../adr/0027-update-run-exit-code-from-section-status.md) — the exit contract
  this change adds a case to.
- [2026-08-29-update-run-truthfulness-design.md](2026-08-29-update-run-truthfulness-design.md)
  — removed the trap's `rm -rf` half and explicitly deferred the trap itself.
- [2026-08-31-update-run-cd-guards-design.md](2026-08-31-update-run-cd-guards-design.md) —
  where `refute_grep` was added, and where the backlog row that prompted this work was written.
- `~/.claude/standards/shell.md`, "`trap ... RETURN` is NOT function-scoped" — the sibling
  trap-scope defect and the origin of `lib/developer.sh:72`'s subshell shape. Its framing, that
  a cleanup trap's failure mode can be worse than the condition it cleans, is what the deleted
  trap does to signal handling and is also what retired the withdrawn Group A2.
- `~/.claude/standards/behavior.md`, "A guard whose output cannot alter what runs after it is
  not a guard" — M4's idiom is that shape: it executes after the decision it was meant to
  affect.
- `~/.claude/standards/behavior.md`, "The artifact carries the field, and its value is
  compatible with both causes" — M8's retraction is that shape: the last _line_ of a test body
  and its last _executed command_ are the same value for most bodies and differ for 30 of them.

## Multi-Lens Review

**Verification-case numbers inside the two review sections refer to the numbering as it stood
when that round ran, not to the current Verification section.** Round 1 reviewed a spec with
V1-V7; its dispositions were written against the revision's V1-V11; Group A2's withdrawal then
took three cases out and the current set is V1-V8. The review sections are kept as written
rather than renumbered, since a disposition that silently referred to a different case than the
lens did would be worse than a stale number.

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

## Multi-Lens Review — Round 2

Reviewed at commit: `10c41b13` (the round-1 revision)

All three lenses independently condemned Group A2 — the mechanism round 1's corrections had
added. Every finding below was re-derived here before being accepted.

### Goal-Fit

Finding: Group A2 rests on a measurement taken with the wrong actor, and the state it protects
is already lost today. M9 used single-process SIGTERM — the M1 harness — one section after M1b
established that single-process delivery cannot answer this question, so the rebuild child
never received the signal and completed for reasons unrelated to the trap. Under process-group
delivery the artifact is absent in both arms, so A2's entire delta over Group A alone is one
stderr line, not a machine state. Against that it costs install/remove pairs in two functions,
property 4 (which the spec itself calls the one a future edit will break) and three
verification cases. Separately, the revision deletes one shell-global INT/TERM trap and adds
two, while G3 — added in the same round as the class invariant to stop exactly this — is
scoped to EXIT and explicitly waives them. Confirmed M8's retraction is now correct
(four-case fixture reproduced), and confirmed G3's corpus, the 39/81/1641 figures, and that no
guard anywhere reads `_DOTFILES_RUN_TMPDIR`'s unset-ness.

Assumption: That SIGINT to the process group actually kills the real rebuild child —
`ruby-install`, `rbenv install`, `uv sync` — as the `sleep` stand-in did. If any installs its
own signal handling, the child survives and M9's original claim would be partially right.

Disposition: **Addressed.** Group A2 withdrawn entirely; M9 rewritten with the process-group
measurement, re-derived here (`artifact_present=NO` in both arms) rather than accepted on
report. The operator chose deletion over rebuilding the guard in a safer shape. The assumption
is recorded in Deferred: it does not change the decision, since a mechanism worth one message
is not worth its cost either way, but it does qualify Group D's wording.

### Ergonomics

Finding: Property 3's recovery command was a frozen literal and wrong for
`recreate_python_venv`, whose venv name is an operator-supplied `--venv-name`. An operator who
aborted `-t recreate-venv --venv-name foo` and obeyed the message would leave `foo` deleted
and trigger a full 269-package `uv sync` against `ansible`, since `lib/developer.sh:547` gates
on that name — the slowest possible wrong action at the moment of maximum stress. Property 4
was a 10-site edit obligation across two functions, and `recreate_ruby` destroys on two
mutually exclusive platform branches with a `return 1` between them, so it could not satisfy
property 5 with one install point. V7 and V8 both passed if the guard was never installed at
all, since "empty" is satisfied identically by *correctly removed* and *never installed* — the
spec applied exactly this reasoning to V10 and did not carry it one paragraph up. And G3's
only textual discriminator between the permitted subshell trap and a function-scope one is
indentation, which is line position standing in for control flow: the predicate class the
withdrawn `! grep` scanner died of, in a check gating pre-commit and pre-push.

Assumption: That `pyenv virtualenv-delete -f` succeeds against a virtualenv whose creation was
itself interrupted, so "re-run the same command" genuinely recovers. If it errors,
`lib/developer.sh:541`'s `2>/dev/null || true` swallows it and the create at `:544` then fails
"already exists", looping the operator.

Disposition: **Addressed.** A2's withdrawal removes properties 3, 4 and 5 and cases V6-V8
outright. The `--venv-name` finding survives A2 and is now a Group D documentation
requirement, since the recovery instruction is still being written down. G3 is rebuilt as an
**allowlist ratchet** that does not decide scope at all — it enumerates every `EXIT` trap in
`lib/*.sh` and requires the set to match a recorded allowlist with reasons — so the
indentation objection no longer applies, and V5 now pins that a subshell trap is *still* a
finding, so a later "improvement" toward inference fails. The `virtualenv-delete` assumption
is recorded in Deferred alongside the missing post-install verification, which is the same
gap seen from the other side.

### Risk

Finding: Group A2 reintroduces the exact defect Group A deletes. `trap - INT TERM` **removes**
rather than restores, and bats installs a live `bats_interrupt_trap` SIGINT handler in every
test — so post-Group-A a bare call at any of the 35 sites would have silently destroyed it, a
lib function clobbering its caller's trap, which is this spec's Problem statement one signal
over. Worse, V7 and V8 asserted `trap -p INT` is empty in the caller, which is true only of
the destroying implementation: a correct save-and-restore guard goes red against them, so the
verification case forbade the fix. The spec's rejection of the `( )` subshell shape was also
wrong on its stated grounds — containment is structural, the caller's handler survives, and it
makes property 4 unnecessary rather than untestable. Finally A2 fires late: bash defers a
pending trap until the foreground child returns, so under single-process delivery `uv sync`
completes and the guard then prints that the venv is deleted — false about a machine just
rebuilt. And `recreate_python_venv` has no post-install verification, so the guarded span had
no defined endpoint.

Assumption: That the guard's handler runs when the operator interrupts rather than after a
multi-minute foreground child completes — the design's whole value being to report machine
state accurately.

Disposition: **Addressed.** All four findings are moot for this spec because Group A2 is
withdrawn, and all four are recorded in Deferred as the constraints any future interrupt-UX
mechanism must satisfy together, so the next attempt does not re-derive them. The three
load-bearing mechanisms were re-measured here rather than accepted: bats installs
`trap -- 'bats_interrupt_trap' SIGINT` per test; `trap - INT TERM` leaves `INT=[]` where the
caller had a handler; and a `( )` subshell aborts its window while leaving
`AFTER=[trap -- 'echo CALLER-INT' SIGINT]` intact. V7/V8 are gone with A2 rather than repaired.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. No comparison arms, no
judge component, and the acceptance criteria are concrete commands with stated failure
conditions.

### Stopping here

Both of the skill's stop signals agree, which is the condition for ending review rather than
either alone.

**Artifact location.** Round 2's findings were design findings — a premise measured with the
wrong actor, a mechanism reintroducing the defect it was added to prevent, a predicate that
cannot decide what it claims. That would argue for another round. But the disposition for
every one of them is *deletion*, and what remains — Groups A, B, C, D — is text that has now
survived two rounds unchanged in substance.

**Direction of the corrections.** Round 1 removed a scanner and an assertion edit and added
Group A2. Round 2 removed Group A2, its five properties, three verification cases, and
replaced an inference-based predicate with an enumeration. Across both rounds the design has
only ever lost surface; nothing was added to replace anything. The spec is roughly half the
mechanism it proposed at `0fdbd416`.

**The honest residue.** The remaining uncertainty is concentrated in things a first `bats` run
answers in seconds — whether G3's allowlist enumeration matches, whether V6's ok/not-ok set is
unmoved — which is the skill's signal that prose review has reached its floor and the next
round should be Phase 2's first red test.
