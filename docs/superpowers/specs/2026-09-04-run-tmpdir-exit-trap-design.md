# The EXIT trap in `_dotfiles_run_tmpdir_setup`

One line of production code, `lib/workflows.sh:109`, does two harmful things and no useful
one. It swallows SIGINT and SIGTERM so an operator cannot interrupt `setup_env.sh -t update`,
and it replaces bats' EXIT trap so 35 test sites lose their name when they fail. Deleting it
fixes both and makes a 27-site test idiom — written to work around the second effect, and
inert on the path it was written for — deletable.

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
runs to completion after a Ctrl-C or a `kill`, and exits 0.

**It clobbers bats' EXIT trap.** bats installs `trap -- 'bats_teardown_trap as-exit-trap' EXIT`
per test and reports `not ok` through it. Any bare (non-`run`) call to one of the six
functions replaces that trap; when the test then fails under bats' errexit, the test produces
no TAP line at all — no name, no file, no line number.

The repo already knows about the second effect and has been paying for it. Twenty-seven test
sites carry a save/restore idiom written to defend against it, and `lib/workflows.sh:196-205`
carries a production comment explaining that `|| _hooks_rc=$?` is written that way _because_
of it. **The idiom does not work**, for the reason M4 gives.

## Measurements

Every measurement below states the population it covered. Where a claim is broader than its
command, the qualifier is at the measurement.

### M1 — The trap swallows SIGTERM, measured against the real function

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
Not measured under an interactive terminal's SIGINT delivery; the mechanism is the same trap
and the same absence of `exit`, but the claim stated here is SIGTERM.

Note bash's deferral semantics: the trap runs after the current foreground command completes.
During a real `-t update` the operator's Ctrl-C is therefore absorbed at the end of whatever
`brew upgrade` or `uv sync` was running, and the run continues into the next section.

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
carries no information about whether the mechanism works, for the reason `behavior.md` gives
about zeros: the interesting result is the one nobody interrogates. M2 and M4 are the
measurements that establish the mechanism; M7 only establishes that no site has tripped it yet.

### M8 — The `! grep` population is 1, not 24

A bare `!` is exempt from errexit unconditionally; it fails a bats test only when it is the
last command in the body, where its status becomes the test's status.

**Denominator: 39 tracked `.bats` files, 1641 `@test` bodies**, derived from
`git ls-files '*.bats'` under the four-variable `env -u` strip. The 1641 cross-checks against
CI's own `grep -r "^@test" tests/ | wc -l`, which reports the same figure.

```
bare `! grep`: 81
  last command in its @test (effective today): 80
  INERT: 1   -> tests/setup_env/workflows.bats:1194
```

The single inert site is inside `if [[ -f "${MOCK_CALLS_FILE}" ]]` in "run_update skips
softwareupdate on Linux", so the negation is discarded and the assertion cannot fail. The
other 80 work. They are fragile — appending one line to any of those tests silently disarms
it — but they are not defects.

The backlog row that prompted this work said "24 bare `! grep` … remain in
`tests/setup_env/workflows.bats`". The count is right for that file and the hazard reading is
wrong: 23 of those 24 are effective. `refute_grep` already exists in
`tests/helpers/common.bash` as the documented remedy.

## Design

### Group A — delete the trap

`lib/workflows.sh:109`: delete the line. Nothing replaces it.

Three consequences, all intended:

- SIGINT/SIGTERM abort the run, as they do for every other script in this repo.
- No caller of `_dotfiles_run_tmpdir_setup` replaces the caller's EXIT trap, so all 35 bare
  sites report normally when they fail.
- `_DOTFILES_RUN_TMPDIR` persists to process exit. Harmless: the process is exiting, and bats
  runs each `@test` in its own process so nothing leaks between tests.

After this, `lib/` has **zero** function-scope EXIT traps. `lib/developer.sh:72` keeps its
EXIT trap and is correct: it sits inside a `( )` subshell with a header comment
(`lib/developer.sh:38-44`) citing `shell.md`'s RETURN-trap entry for why. It is the worked
precedent for the right shape, not an exception to this change.

The tmpdirs themselves are unaffected — dotfiles#250 already removed the `rm -rf`, so they
accumulate today and will accumulate identically after. The durable-run-root work that would
address that stays deferred where it is.

Two comments go stale and are updated in the same commit:

- `lib/workflows.sh:196-205` explains `|| _hooks_rc=$?` as a workaround for this clobber. The
  code stays — it is independently correct and matches the surrounding
  `setup_claude_mcp || return 1` style — but its stated reason is gone.
- `tests/setup_env/ledger_integration.bats:350` carries the same explanation.

### Group B — delete the dead idiom and fix the one inert assertion

In `tests/setup_env/workflows.bats`:

- Delete the 27 save/restore blocks (`local _bats_exit_trap`, the `trap -p EXIT` capture, the
  `eval`) and the comments introducing them. **The calls stay bare** — M6.
- Leave the 8 bare `run_setup_user` sites as they are. They become safe under Group A, and
  converting them to `run` would be churn on tests that pass.
- `:1194`: replace the bare `! grep -q "^softwareupdate" "${MOCK_CALLS_FILE}"` with
  `refute_grep '^softwareupdate' "${MOCK_CALLS_FILE}"`, keeping the enclosing
  `if [[ -f ... ]]`. `refute_grep` returns non-zero on a match regardless of position, and
  names what it found.

`tests/setup_env/install_guards.bats` is not touched — M5.

### Group C — guards

**G1, mechanism.** `_dotfiles_run_tmpdir_setup` leaves the caller's EXIT, INT and TERM traps
identical. Capture `trap -p` for each of the three before and after, compare.

All three signals, not just EXIT: a future change that installs an INT/TERM handler without
`exit` reintroduces the M1 defect while leaving EXIT clean, and an EXIT-only assertion would
pass over it.

**G2, consequence.** A script that calls `_dotfiles_run_tmpdir_setup` and then blocks still
dies on SIGTERM. Assert the exit status is **non-zero**, never the literal `143` — signal
numbers are not portable, and this suite runs on macOS and Linux.

G2 exists because G1 alone is a mechanism assertion. Someone could satisfy G1 with a trap
installed and immediately restored around the `mktemp`, which would leave signal handling
broken. G2 is the behavioural positive control.

**G3, the `! grep` lint scanner.** A new case under `tests/scripts/`. For every tracked
`.bats` file, parse `@test` bodies and fail on any bare `! grep` that is not the last
non-blank, non-comment command in its body, naming `file:line` and pointing at `refute_grep`.

Three properties this must have, each taken from a precedent in this repo:

- **Domain derived, not listed.** `git ls-files '*.bats'` under
  `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`, matching
  `makefile_lint_scope.bats`. The `env -u` is not decoration: `git -C` does not override an
  exported `GIT_DIR`, and `scripts/pre-push` runs `make test`, so a push from a worktree
  resolves the scope against the wrong repository.

  **Use `'*.bats'`, not a `tests/`-anchored pathspec, and this was measured rather than
  assumed.** `git ls-files 'tests/**/*.bats'` returns **37** and silently omits
  `tests/makefile_scope.bats` and `tests/test_package_capture.bats` — git's `**` does not
  match the zero-directory case here. `git ls-files 'tests/*.bats'` happens to return all 39
  because git pathspec `*` crosses `/`, but it still encodes a directory assumption that a
  future `.bats` file outside `tests/` would falsify. `git ls-files '*.bats'` is 39 today and
  cannot drift. This is the same omission shape `tdd.md` describes for coverage denominators:
  the two missing files would be absent from findings and from the scanned set alike, so the
  scanner would report clean either way.

- **Assert the derived list is non-empty** before iterating. An empty list makes the scan
  vacuously clean, which is indistinguishable from a pass.
- **A live positive on first run.** The corpus is 81 sites with exactly one hit (M8), so the
  scanner has something to find before `:1194` is fixed. This is the mutation control the
  scanner would otherwise lack — a checker whose only evidence is a zero has not been shown
  to be able to produce a one.

Scope is deliberately the `! grep` form only. `! [[ ... ]]` and `! command` share the
mechanism and are out of scope here; widening the scanner is a Deferred item rather than an
unmeasured extension.

### Group D — docs

- `CLAUDE.md`, the `-t update` row: state that SIGINT/SIGTERM now abort the run.
- `docs/adr/0027-update-run-exit-code-from-section-status.md`: cross-reference. ADR-0027
  defines what a non-zero exit from `-t update` means, and this change adds a case — an
  interrupted run exits non-zero, with **no summary rendered, no `~/.dotfiles-update.log`
  entry, and no state-ledger entry**, because `_update_summary` and
  `_ledger_write_dotfiles_entry` are never reached. Today the same interrupt produces a
  complete summary and exit 0. That is a user-visible contract change and belongs in the ADR
  that owns the contract, not only in a spec.

## Verification

Each case states what makes it fail.

**V1 — G1 goes red with the trap restored.** Restore `lib/workflows.sh:109`, run G1, confirm
failure; delete it again, confirm `ok`. Note the pre-fix failure manifests as the test
_vanishing_ rather than as `not ok` — that is the defect demonstrating itself, and the run's
`bats warning: Executed N-1 instead of expected N` plus a non-zero rc is the signal to read.
Both outcomes are red; do not read the missing `not ok` as a pass.

**V2 — G2 goes red with the trap restored.** Same mutation. Pre-fix: `SURVIVED-SIGTERM`, rc 0.
Post-fix: process dies, rc non-zero. Both halves asserted — a G2 that only checked the
post-fix direction would pass against a trap that never installed.

**V3 — G3 finds `:1194` before Group B fixes it, and nothing after.** Run the scanner on the
pre-Group-B tree: exactly 1 hit, at `tests/setup_env/workflows.bats:1194`. After the fix: 0
hits, with the derived file list still non-empty (assert the count, not just the absence of
findings).

**V4 — G3 catches a newly-introduced instance.** Add a bare `! grep` above the last line of
any test, confirm the scanner names it, remove it. This is distinct from V3: V3 shows the
scanner finds the one that exists, V4 shows it finds one it has never seen.

**V5 — the 27 idiom deletions move no verdict.** `bats tests/setup_env/workflows.bats` before
and after Group B. Baseline on `cd9c0a6d` is 214 planned, 214 executed, 0 `not ok`, no
warning (M7). Compare the full `ok`/`not ok` set, not the count — a count is equal under a
swap.

**V6 — full suite, plan equals executed.** `make test`. Assert no `bats warning: Executed`
line appears anywhere in the output. This is the case that would have caught the whole class
had it existed, and it costs one grep.

**V7 — a bare call that fails now reports by name.** Stage a `run_update` section FAIL,
call it bare in a fixture, and assert the outer `bats` output carries `not ok` **with the
test's name**. This is the property the entire change exists to produce, and neither G1 nor
G2 asserts it — G1 is about traps and G2 is about signals. Pre-fix this fixture vanishes;
post-fix it names itself.

## Deferred

- **Widening G3 to `! [[ ... ]]` and `! command`.** Same mechanism, unmeasured population.
  Measure the corpus first; a scanner whose hit count is unknown before it ships is one that
  either fires on dozens of working assertions or on none.
- **Converting the 80 fragile `! grep` sites to `refute_grep`.** They work. G3 detects the
  failure mode mechanically, which is the cheaper half of what the conversion would buy.
- **The 8 bare `run_setup_user` sites.** Safe under Group A; converting them to `run` +
  `[ "$status" -eq 0 ]` is available if a future change makes any of them read
  `_DOTFILES_RUN_TMPDIR`.
- **A summary/ledger entry on interrupt.** Group D documents that an interrupted run now
  produces neither. Making it produce a partial one is a separate design — it needs a signal
  handler that renders and _then_ exits non-zero, which is a different mechanism from the
  trap being deleted here and should not be smuggled in as its replacement.

## Related

- [ADR-0027](../../adr/0027-update-run-exit-code-from-section-status.md) — the exit contract
  this change adds a case to.
- [2026-08-29-update-run-truthfulness-design.md](2026-08-29-update-run-truthfulness-design.md)
  — removed the trap's `rm -rf` half and explicitly deferred the trap itself.
- [2026-08-31-update-run-cd-guards-design.md](2026-08-31-update-run-cd-guards-design.md) —
  where `refute_grep` was added, and where the backlog row that prompted this work was written.
- `~/.claude/standards/shell.md`, "`trap ... RETURN` is NOT function-scoped" — the sibling
  trap-scope defect, and the origin of `lib/developer.sh:72`'s subshell shape.
- `~/.claude/standards/behavior.md`, "A guard whose output cannot alter what runs after it is
  not a guard" — M4's idiom is that shape: it executes after the decision it was meant to
  affect.
