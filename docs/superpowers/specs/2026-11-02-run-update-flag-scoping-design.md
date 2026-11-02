# run_update flag scoping in bats tests

- **Date:** 2026-11-02
- **Approved:** 2026-11-02
- **Backlog row:** "bats process-spawn cost (part 2 of the setup floor)". Part 2a
  (`docs/superpowers/specs/2026-11-01-load-mocks-setup-trim-design.md`, dotfiles#416) trimmed
  per-test setup. This is part 2b: spawn counts in test bodies. The operator chose option A of
  three: scope the tests, no production change. B (production fork trims) and C (pin `python3`
  off the pyenv shim) are Backlog rows.

## Problem

Most `run_update` tests assert on one section but run all of them. With no `UPDATE_*` flag set,
`_any_update_flag` (`lib/helpers.sh`) fails, `run_update` sets `_run_all=1`, and every section
in `lib/workflows.sh` runs against the mocks.

Measured on `claude`, 2026-11-01, in a `git archive` copy with a timing file built from
`tests/setup_env/workflows.bats`'s `setup()` (bats 1.13, `/usr/bin/time`, CPU above an empty
test with the same `setup()`):

| Test body                              | CPU above empty |
| -------------------------------------- | --------------- |
| flagless `run_update`, macOS vars      | ~1.45 s         |
| `UPDATE_BREW=1 run_update`, macOS vars | ~0.35 s         |

In the full run, the `claude` section took ~820 ms and `gems` ~435 ms, over 55% between them
(xtrace attribution by command). `python3` was called 8 times per full run, 564 ms.

**Population.** These numbers come from one machine, `claude`, and one harness: `workflows.bats`'
`setup()` with macOS variables. The claim covers every flagless `run_update` test on every
runner. Two differences matter:

- `python3` on `claude` resolves through the pyenv shim, 66 ms per call against 15 ms for
  `/usr/bin/python3`. CI runners have no shim. So the CI saving per scoped test is smaller
  than ~1.1 s, by up to the 564 ms `python3` share.
- A Linux-variable full run skips mac sections and runs apt, snap and flatpak. Its cost
  differs from the macOS row. It was profiled (`t_full_linux`) but not tabled here.

**Candidates.** An awk scan of every tracked `.bats` file counts test bodies that call
`run_update` and set no `UPDATE_*` flag. A body ends at the next `@test` line. The scan found
127 flagless tests in 10 files, 25 of them with an absence assertion (`! grep`, `!=`):

| File                                      | `run_update` tests | flagless | with absence |
| ----------------------------------------- | ------------------ | -------- | ------------ |
| `tests/setup_env/workflows.bats`          | 109                | 67       | 9            |
| `tests/setup_env/update_apt.bats`         | 29                 | 29       | 10           |
| `tests/setup_env/update_noop_skip.bats`   | 10                 | 7        | 0            |
| `tests/setup_env/flatpak.bats`            | 8                  | 7        | 2            |
| `tests/setup_env/cargo_tools_update.bats` | 8                  | 6        | 3            |
| `tests/setup_env/unit.bats`               | 10                 | 4        | 0            |
| `tests/setup_env/update_claude.bats`      | 13                 | 3        | 1            |
| `tests/setup_env/linux_shared.bats`       | 2                  | 2        | 0            |
| `tests/setup_env/update_pyenv_shims.bats` | 11                 | 1        | 0            |
| `tests/setup_env/ledger_integration.bats` | 1                  | 1        | 0            |

The scan is a heuristic, and it misses in both directions:

- It undercounts scoped tests when a flag is exported in `setup()` or in a helper.
- It overcounts when a body names `run_update` without running it.

The plan re-derives the list per file before any edit.

**Correction (round 2).** The undercount is large. `update_apt.bats` (29) and `flatpak.bats`
(7) call `setup_run_update_linux` (`tests/helpers/common.bash`), which exports
`UPDATE_PKGS=1` and unsets the other five flags. Those 36 tests are already scoped: adding
`export UPDATE_PKGS=1` to `update_apt.bats`' `setup()` left its CPU unchanged. A re-scan that
counts helper and `setup()` exports leaves about 80 flagless tests, about 62 of them in
`workflows.bats`. The 10 absence asserts in `update_apt.bats` drop out with them. The table
above is kept as the original scan, and the plan's re-count is the authority.

**Implicit coverage.** No test asserts that a flagless run reaches every section. That fact is
pinned today only as a side effect of these ~80 tests, so scoping them removes it unless a test
replaces it. `update_summary.bats`'s "returns 0 when every section is OK" is a unit test of
`_update_summary` on seeded status files. It does not run `run_update`.

## Flag to section map

From `run_update` in `lib/workflows.sh`:

| Flag            | Sections it runs                                                          |
| --------------- | ------------------------------------------------------------------------- |
| `UPDATE_BREW`   | brew (and softwareupdate on macOS), plugin-node, pyenv-shims, cargo-tools |
| `UPDATE_CLAUDE` | claude, plugin-node, terraform-skill, npm                                 |
| `UPDATE_PKGS`   | apt, snap, flatpak                                                        |
| `UPDATE_MAS`    | mas                                                                       |
| `UPDATE_PIP`    | pip, pyenv-shims                                                          |
| `UPDATE_GEMS`   | gems                                                                      |
| none (run-all)  | ai-config, git-repos, legacy-rsync, git-hooks, aws, rust, cheat.sh        |

`_UPDATE_SECTION_ORDER` (`lib/update_summary.sh`) also names pip-check, oh-my-zsh,
zsh-autosuggestions, tpm, tfenv and brew-drift. `run_update` itself does not open these with
`_update_record_start`. They are recorded elsewhere, through `_update_ok`, `_update_skip` and
similar. The plan maps each one to its gate before classifying a test that asserts on it. Until
it is mapped, such a test is class 2.

## Design

Scope: `tests/**/*.bats` only. No production file changes.

### Classification

Each flagless `run_update` test is in exactly one class.

1. **Scope it.** Every assertion concerns sections reachable through one flag, or through two
   flags whose union covers them. The test sets those flags before `run run_update` and drops
   them from any `unset` list. No other line of the body changes.
2. **Keep it full.** The test asserts any of:
   - a run-all-only section, or an unmapped one (see above);
   - the overall exit status, where a full run's status covers sections outside the scoped set
     and the test name or comment says that is the point;
   - section order, or the summary as a whole;
   - anything its name calls "full", "default" or "no flags".

   A `[ "$status" -eq 0 ]` beside a section-specific grep is not class 2 on its own. Most
   tests carry one as a guard, and a scoped run still checks it for the sections it runs.

   **Pip state.** The pip block changes shell state in-process: it exports `PYENV_ROOT`,
   prepends `$PYENV_ROOT/bin:$PYENV_ROOT/shims` to `PATH`, and runs `eval "$(pyenv init -)"`
   and `pyenv shell ansible`. In a full run, that state carries into pyenv-shims, cargo-tools
   and gems. A scoped run without `UPDATE_PIP` skips it, so those sections may resolve
   commands differently. A scoped test asserting on any of these three sections therefore
   always sets `UPDATE_PIP` as well. It costs about 80 ms per run (`UPDATE_GEMS=1` 1.48 s
   CPU, with `UPDATE_PIP=1` added 1.87 s, full run 7.26 s).

   A test with both flags cannot tell a correct gate from one keyed to `UPDATE_PIP` or nested
   inside the pip block. Single-flag tests catch those regressions today:
   `unit.bats` "run_update --gems-only ...", `cargo_tools_update.bats` at lines 44 and 54, and
   `update_pyenv_shims.bats` at line 308. They are not candidates (they already set one flag),
   and they stay single-flag.

3. **Absence asserts.** A test with `! grep X`, `!=` or a similar absence check is scoped only
   when every producer of `X` lies in a section the chosen flags run. Otherwise the scoped run
   cannot produce `X`, so the absence passes vacuously, and the test stays full. The plan names
   the producer for each scoped absence assert.

   A producer is every section that can write `X`, not only the section the test is about.
   Shared helpers and mocks (`brew`, `sudo`, the apt family) write `MOCK_CALLS_FILE` from
   several sections. The plan finds producers by grepping `X` across `lib/` and `tests/mocks/`,
   then maps each hit, and each caller of a hit helper or mock, to the sections that reach it.

Example (class 1): a test that sets macOS variables, unsets the five flags its `unset` line
names (existing lines omit `UPDATE_PKGS`), runs `run_update`, and asserts
`grep -q "brew update" "${MOCK_CALLS_FILE}"`. It becomes `export UPDATE_BREW=1` with
`UPDATE_BREW` removed from its `unset` line.

### Coverage pin

Add one test per platform to `tests/setup_env/workflows.bats`. Each sets the platform
variables, unsets all six `UPDATE_*` flags and runs `run_update`. Then, for every name in
`_UPDATE_SECTION_ORDER` read at run time, it asserts two things:

- a summary row exists for the name. Rows are padded (`[OK]   %-20s`), so the match is the
  extended regex `\[(OK|FAIL|SKIP|WARN)\][[:space:]]+<name>([[:space:]]|$)`, not a bracket
  character class;
- that row's result is not `flag not set`.

The second check is the load-bearing one. Every flag-gated block in `run_update` has an
`else _update_skip "<section>" "flag not set"` branch (19 sites in `lib/workflows.sh`). If a
gate loses its `${_run_all} -eq 1 ||` arm, a flagless run still writes a row, as
`[SKIP] <name> flag not set`. Only the second check sees that. In a flagless run no section
can legitimately report `flag not set`, so the check needs no exemption list. Measured by the
review lenses: today a flagless run on either platform records all 28 sections, each OK or an
environment SKIP.

Both checks loop over `_UPDATE_SECTION_ORDER`, so an empty or unsourced array would pass with
nothing checked. The pin therefore also asserts that the array is non-empty and that the
number of names it checked equals `${#_UPDATE_SECTION_ORDER[@]}`, less any exemptions.

A section that does not record on a platform is listed in that test as an exemption, with a
reason comment, after measuring that it really does not record. The expected set is never a
hand-typed list of included names. A new section added to the array is then covered by default.

### Rollout

One PR, from one plan:

- `workflows.bats` is its own task, the largest.
- The remaining files are one task, about 18 tests after the round-2 correction.
- The coverage pin is its own TDD task. Its red-first checks are V4's and V5's controls: a deleted
  section block, and a gate with its `_run_all` arm removed.

Every task needs a judgement call on classification, so no task is Haiku-eligible. All tasks
run on Sonnet. `tests/bats-weights.tsv` is not reseeded. Shard balance drifts a little, and a
reseed needs the macOS measurement its own procedure prescribes.

### Predicted saving

At ~1.1 s CPU per scoped test on `claude`, scoping most of the ~80 saves on the order of
85 s CPU per local suite run, about 3% of the 2680 s total in `tests/bats-weights.tsv`. On CI, without the shim, it saves less (see Population). This
is a prediction. V6 measures it, and the PR reports it against this figure.

## Not chosen

- **B, production fork trims.** Replace `$(cat status)` with `$(<status)` in
  `_update_record_*` (about 6.2k `cat` forks per suite run) and drop the `python3`
  realpath/uuid calls. This is a production change with its own review surface. Backlog row.
- **C, pin `python3` in `load_mocks`.** The saving is local only, and the change also closes a
  leak: the tests execute the real ansible venv's `python3`. Backlog row.
- **Mock shebang (`#!/usr/bin/env bash` to a fixed path).** The `env` `PATH` walk makes 76% of
  `execve` calls, but they fail with ENOENT and cost little: ~0.5 ms of ~6.8 ms per mock call,
  ~3%. macOS cannot hardcode the bash path. Closed, with this measurement, in the Backlog's
  closed table.

## Requirements

- **R1.** `[PR1]` Every flagless `run run_update` test in the files the plan re-counts ends in
  one of two states. It is scoped, setting the `UPDATE_*` flags that cover every section it
  asserts on. Or it is listed in the plan's keep-full table with its class 2 or class 3 reason.
- **R2.** `[PR1]` A scoped test's diff only adds `export UPDATE_<X>=1` lines, or
  `UPDATE_<X>=1` prefixes, before `run run_update`, and removes `UPDATE_<X>` from its `unset`
  list.
- **R3.** `[PR1]` A test with an absence assertion is scoped only when the plan names every
  producer of the absent string, and each producer lies in a section the set flags run. A
  producer is every section that reaches a hit for the string in `lib/` or `tests/mocks/`,
  directly or through a shared helper or mock.
- **R4.** `[PR1]` A test asserting on ai-config, git-repos, legacy-rsync, git-hooks, aws, rust or
  cheat.sh stays flagless.
- **R5.** `[PR1]` `tests/setup_env/workflows.bats` gains one macOS and one Ubuntu test. Each
  runs a flagless `run_update`. For every name in `_UPDATE_SECTION_ORDER` read at run time, it
  asserts a summary row with status OK, FAIL, SKIP or WARN, matched as
  `\[(OK|FAIL|SKIP|WARN)\][[:space:]]+<name>([[:space:]]|$)`, and asserts that row's result
  is not `flag not set`. It also asserts that `_UPDATE_SECTION_ORDER` is non-empty and that the
  number of names checked equals its length less exemptions. Any exempt name is listed in the
  test with a reason comment.
- **R6.** `[PR1]` A scoped test asserting on pyenv-shims, cargo-tools or gems also sets
  `UPDATE_PIP`. The single-flag tests `unit.bats` "run_update --gems-only ...",
  `cargo_tools_update.bats` lines 44 and 54, and `update_pyenv_shims.bats` line 308 keep exactly
  one `UPDATE_*` flag.
- **V1.** `bats --count` gives the same total for each touched file before and after. `make test`
  passes at the PR head, and every `test-shard` and `test-macos-shard` leg passes.
- **V2.** The candidate-count scan runs before and after. The PR body records the per-file
  flagless count both times, and the plan's keep-full table accounts for every flagless test
  left after.
- **V3.** Pick one scoped test per flag used: `UPDATE_BREW`, `UPDATE_CLAUDE`, `UPDATE_PKGS`,
  `UPDATE_PIP`, `UPDATE_GEMS`, and `UPDATE_MAS` where a scoped test uses it. In a
  `git archive` copy, break that section's recording or its asserted command. The test goes red.
  The PR body records each mutation and the test it turned red. A test that stays green moves
  to keep-full. The copy is then deleted.
- **V4.** In a `git archive` copy, delete one section's whole gated block from `run_update`
  (for example the `gems` block). Each coverage pin that expects that section goes red. Removing
  only `_update_record_start` is not a valid control: `_update_record_end` writes a status file
  on its own, so the pin would stay green.
- **V5.** In a `git archive` copy, remove only `${_run_all} -eq 1 ||` from one gate (for
  example the gems gate), leaving its `else _update_skip` branch. Each coverage pin that
  expects that section goes red. Repeat for the pyenv-shims gate, which no test catches today.
- **V6.** On `claude`, run one before/after pair of the touched files at `bats --jobs 8`, timed
  with `/usr/bin/time -a -o` and `uptime` recorded per run. The PR body reports wall, user and
  sys for each run, and the CPU saving against the predicted ~85 s. There is no pass threshold.
- **N1.** No file changes outside `tests/**/*.bats` and `docs/`.
- **N2.** No new `run_update` flag or selector.
- **N3.** No lint, ratchet or guard on the count of flagless `run_update` tests.
- **N4.** No assertion line in an existing `@test` body is removed or changed.
- **N5.** `tests/bats-weights.tsv` does not change.

## Multi-Lens Review

Reviewed at commit: `90e66bff` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The coverage pin does not replace what scoping removes. Every flag-gated block in
`run_update` has an `else _update_skip "<section>" "flag not set"` branch (19 sites in
`lib/workflows.sh`), and the pin accepts SKIP. So dropping `${_run_all} -eq 1 ||` from one
gate leaves `[SKIP] <name> flag not set` in a flagless run and the pin green, while the scoped
test sets the flag and stays green too. V4 deletes the whole block, `else` included, so it
tests a control the pin catches and never the realistic regression. Fix: in the flagless pin,
reject a result of `flag not set`; add a V5 control that removes only the `_run_all` arm.
The row pattern `[OK|FAIL|SKIP|WARN]` is a character class as a regex; use
`(OK|FAIL|SKIP|WARN)`. Otherwise goal-fit holds: no simpler path gets most of the value.
Assumption: that keep-full survivors cover each of the six flag-gated families by accident.
Settled by removing the `_run_all` arm from each gate in turn in an archive copy at the PR
head; each must turn at least one test red. Predicted: at least one family goes all-green.
Disposition: Addressed (operator, 2026-11-02) — the flagless pin now rejects a `flag not set`
result, rows match `\[(OK|FAIL|SKIP|WARN)\][[:space:]]+<name>`, and V5 adds the
`_run_all`-arm control. The per-family survivor sweep is subsumed: V5 runs it on the pin.

### Ergonomics

Finding: Same pin defect, reproduced: with the gems gate mutated, a flagless macOS run showed
`gems=SKIP`, all 28 rows present, pin green. Given the fix, friction is low: flagless runs on
macOS and Ubuntu each record all 28 sections (OK or an environment SKIP), so the exemption
list starts empty on both platforms and a new section is pinned by default. Summary rows are
padded (`[OK]   %-20s`), so the match needs `\]\s+<name>\b`. Existing `unset` lines name 5
flags, not 6 (`UPDATE_PKGS` is absent). Asked: should the pass condition be "row exists and
result is not `flag not set`", or "no SKIP unless the name is in a measured exemption list"
(about 13 exemptions per platform)?
Assumption: that each absence assert's string has an enumerable producer set. Shared helpers
and mocks (`brew`, `sudo`, apt) write `MOCK_CALLS_FILE` from several sections, so a producer
may span flags. Settled by grepping each of the 25 absent strings across `lib/` and
`tests/mocks/` and mapping every hit to its sections.
Disposition: Addressed (operator, 2026-11-02) — pass condition is "row exists and result is
not `flag not set`", with no exemption list; the example names five flags; class 3 and R3
define a producer to include shared helpers and mocks.

### Risk

Finding: Same pin defect, reproduced with a spec-conformant pin (`[SKIP] gems flag not set`,
nothing missing, `ok`). Under that mutation only "run_update calls gem update with no flags"
went red today, and the same mutation on the pyenv-shims gate was caught by nothing in
`workflows.bats` or `update_pyenv_shims.bats`, so the implicit coverage is already thinner
than the spec says. The 6 run-all-only sections have no `else` skip and the pin as written
does catch them. `_run_all` is read only inside `run_update`; no summary or ledger code
branches on flag state.
Assumption: that setting a flag changes only which sections run. The pip block exports
`PYENV_ROOT`, prepends `$PYENV_ROOT/bin:$PYENV_ROOT/shims` to `PATH`, runs
`eval "$(pyenv init -)"` and `pyenv shell ansible`, in-process; in a full run that state
persists into pyenv-shims, cargo-tools and gems. A scoped run without `UPDATE_PIP` skips it,
so those sections may resolve commands differently. Settled per scoped test asserting on a
section after pip: run full and scoped in an archive copy, filter `MOCK_CALLS_FILE` to the
section's commands, and diff.
Disposition: Addressed (operator, 2026-11-02) — the pin fix covers the finding, and V5
names the pyenv-shims gate. The pip-state assumption became a class 2 rule, R6 and V7.

### Round 2

Reviewed at commit: `1ba9c268` (round-1 dispositions applied). All three lenses re-ran.

#### Goal-Fit (round 2, `1ba9c268`)

Finding: The candidate population is wrong. `update_apt.bats` (29) and `flatpak.bats` (7) call
`setup_run_update_linux` (`tests/helpers/common.bash`), which exports `UPDATE_PKGS=1` and unsets
the other five flags, so those 36 tests are already scoped. Timing in an archive copy with
`export UPDATE_PKGS=1` added to `update_apt.bats`' `setup()` showed no change (13.27/13.44 s user
before, 13.47/13.46 s after). A re-scan that counts helper and `setup()` exports leaves about 80
flagless tests, 62 of them in `workflows.bats`. The saving is about 85 s CPU on `claude`, about
3% of the suite's 2680 s weight total, and less on CI. Still worth doing if kept small. Simpler
path: drop V7 and the pip-comparison table and always set `UPDATE_PIP` (see Ergonomics). Reads-it
test: V3 discards its result, so record each mutation and its red test in the PR body, and move
a test that stays green to keep-full. V6's five pairs are heavy for a number that gates nothing;
one pair would do. The pin passes when `_UPDATE_SECTION_ORDER` is empty; assert its length.
Apparatus: the pin could read `status_<name>`/`result_<name>` directly instead of a regex.
Assumption: that the ~62 `workflows.bats` tests are truly flagless, with no setup-level scoping.
Settled by timing `workflows.bats` as-is against a copy with `export UPDATE_BREW=1` in `setup()`;
CPU should fall by about 60 s.
Disposition: Addressed (operator, 2026-11-02) — Problem carries a round-2 correction (~80
flagless, ~62 in `workflows.bats`), the prediction is ~85 s, the second task is ~18 tests, V7
is deleted, V3 records to the PR body, V6 is one pair, and the pin asserts its count. The
assumption is left to the plan's re-count, which runs before any edit.

#### Ergonomics (round 2, `1ba9c268`)

Finding: V7 costs more than the rule it replaces and mostly measures nothing. Of 8 candidate
tests (6 `cargo_tools_update.bats`, 1 `unit.bats`, 1 `workflows.bats`), the 6 cargo tests stub
`install_cargo_tools` as a shell function that writes nothing to `MOCK_CALLS_FILE`, so V7's diff
is empty both ways. Adding `UPDATE_PIP` costs about 80 ms per run (`UPDATE_GEMS=1` 1.48 s,
plus `UPDATE_PIP` 1.87 s, full 7.26 s). Fix: make R6 unconditional and delete V7. R3 is
tractable (17 absence lines, mostly single-producer). Trap: `[ "$(cat status_x)" != "OK" ]`
passes when the file is missing. The pin regex matched every name exactly once, 28 rows on each
platform, 0 `flag not set`. A detail line `[WARN]  git-repos: ...` nearly collides and only the
boundary saves it. Apparatus: escape `$` in a double-quoted pattern, escape the `.` in
`cheat.sh`, and a whole-output `! grep -q 'flag not set'` is simpler than per-row. Pin passes
on an empty array; assert the `N sections:` count equals `${#_UPDATE_SECTION_ORDER[@]}` and
is above 0.
Assumption: none genuinely uncertain; the macOS row count is the closest, settled by the first
`test-macos-shard` run.
Disposition: Addressed (operator, 2026-11-02) — R6 always sets `UPDATE_PIP`; V7 and the
table are deleted; the pin asserts a non-empty array and a checked count. Regex escaping, the
missing-status-file trap and reading status files directly go to the plan's pin task.

#### Risk (round 2, `1ba9c268`)

Finding: No blocking design issue. Verified that the 19 `flag not set` sites are all `else`
arms of `_run_all ||` gates, and no section body reads a flag, so no flagless run writes
`flag not set` on either platform. Round-1 history is wrong in one place: the `git-repos` block
does have an `else` that skips tfenv, oh-my-zsh, tpm, cheat.sh and zsh-autosuggestions with
`flag not set`; the pin catches it either way. A wrong-flag gate (`UPDATE_GEMS` changed to
`UPDATE_PIP`) leaves the pin green but turns `unit.bats` "run_update --gems-only" and 2
`workflows.bats` gem tests red. A section moved inside another's gate is caught by
`cargo_tools_update.bats:44`/`:54` and `update_pyenv_shims.bats:308`. Minor design finding: a
test scoped under R6 with two flags cannot tell a correct gate from one keyed to `UPDATE_PIP`,
so the spec relies, unstated, on those single-flag tests staying single-flag; say so in R6.
Apparatus: the pin passes on an empty array; the `.` in `cheat.sh` is unescaped. V7 is the
costliest new part; always setting `UPDATE_PIP` is cheaper (judgement, not defect).
Assumption: that two-flag scoped tests will not be the only coverage of the cargo-tools and
gems gates after the PR. Settled at the PR head by keying the cargo-tools gate to `UPDATE_PIP`
and nesting gems inside the pip gate; each must turn a single-flag test red.
Disposition: Addressed (operator, 2026-11-02) — R6 names the four single-flag tests that
stay single-flag. The round-1 history is left as written; this finding records its error.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
