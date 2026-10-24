# makefile_lint_scope.bats: C collation for sort and comm, and a CI coreutils probe

- **Date:** 2026-10-24
- **Backlog rows:** "`makefile_lint_scope.bats` disjointness tests fail under uutils `sort`/`comm`" (P2 — test gaps); "`sort -u` over names is lossy on Ubuntu 26.04" (P2 — bugs and security)

## Problem

`tests/scripts/makefile_lint_scope.bats` sorts with the ambient `sort` and compares with the
ambient `comm`. Ubuntu 26.04 ships uutils coreutils as `/usr/bin/sort` and `/usr/bin/comm`.
Under `en_US.UTF-8`, uutils `comm` rejects uutils `sort` output, so the two disjointness tests
go red for any actor whose `PATH` does not put the linuxbrew GNU coreutils gnubin first.

Measured 2026-10-24 on `claude` (uutils 0.10.0 for both `sort` and `comm`, `LC_COLLATE=en_US.UTF-8`),
over the real `SHELL_FILES`/`ZSH_FILES` from this repo's Makefile:

```
make print-SHELL_FILES | tr ' ' '\n' | /usr/bin/sort -u > s
make print-ZSH_FILES   | tr ' ' '\n' | /usr/bin/sort -u > z
/usr/bin/comm -12 s z
comm: file 2 is not in sorted order
comm: file 1 is not in sorted order
config/profiles.sh
comm: input is not in sorted order
rc=1
```

The interactive session on `claude` resolves `sort`/`comm` to linuxbrew GNU 9.12, which is why
`make test` there is green. Population: one machine (`claude`), the real file lists; the backlog
row's 2026-10-02 measurement was the same file on `workstation` (2 `not ok` without gnubin, 0 with).

### The second row's premise did not reproduce

The "`sort -u` over names is lossy" row rests on uutils **0.8.0** dropping one of `pytest`/`py.test`
under `sort -u`. Measured 2026-10-24 with uutils **0.10.0** and `LC_COLLATE=en_US.UTF-8`:
`printf 'pytest\npy.test\n' | /usr/bin/sort -u | wc -l` gives `2` on both `claude` and
`workstation`, and `a-b`/`a.b`/`ab` keeps all three. Population: two machines, both on 0.10.0,
two hand-picked inputs. No box in the fleet now produces the loss, so the two `lib/` sites the row
names (`lib/update_summary.sh:361`, `lib/workflows.sh:1093`) are left unchanged and the row is
closed as not reproducible with this measurement attached (operator decision 2026-10-24).

### What CI runs is unknown

The CI `test` job ran on `Image: ubuntu-26.04` for dotfiles#369 (run 40050513754) and both
disjointness tests passed (`ok 245`, `ok 259`). Three explanations fit, and nothing in the job
prints which holds (the run's log carries no `LANG`/`LC_*` line):

- GNU coreutils ahead of uutils on the runner's `PATH`;
- uutils first, but the job runs under `C`/`C.UTF-8`/`POSIX` collation. Measured 2026-10-24 on
  `claude`: the same uutils pipeline over the real lists gives 0 `not in sorted order` lines under
  `LC_ALL=C.UTF-8` and 3 under `LC_ALL=en_US.UTF-8`. GitHub's Ubuntu runners usually set
  `LANG=C.UTF-8`, a prior, not a measurement;
- uutils tools that happen to agree on these inputs.

Locale, not binary order, is what decides whether the defect shows. The `powershell` backlog row
names the runner's coreutils as the open question.

Measured 2026-10-24 on `claude`, same lists: under `en_US.UTF-8`, uutils `comm` accepts
C-sorted input (rc 0), so uutils `comm` compares bytes and the `sort` prefix carries the fix. The
`comm` prefix still matters for GNU `comm`, which honours locale.

## Design

### 1. C collation on every `sort` and `comm` in the file

Prefix `LC_ALL=C` to every `sort` and `comm` invocation in
`tests/scripts/makefile_lint_scope.bats`, including `_sorted_lines_from_space_list`.

Every one, not only those feeding `comm`: helper output is compared for equality with other
`sort -u` output in the same file (for example `:147` against `:148`, `:791` against `:786`), so
converting only the helper would mix collations on the two sides of an equality. The set is
enumerated at plan time with `grep -nE '(^|[^_a-z])(sort|comm)( |$)'`; at spec time it is 14
lines: 10 `sort` invocations and 4 `comm` invocations.

Rejected: `export LC_ALL=C` in `setup()`. It would also put the `make print-*` and `git ls-files`
calls under test into C locale, so a locale-dependent defect in the production derivation would
be masked. The fix changes only the test's own comparison tools.

### 2. A regression test that discriminates on uutils boxes

A green CI run cannot gate this fix if the runner has GNU coreutils first. Add one test that:

- skips unless `/usr/bin/sort --version` and `/usr/bin/comm --version` both report `uutils`;
- skips unless `locale -a` lists `en_US.utf8` (case-insensitive, either `utf8` or `UTF-8`);
- obtains `SHELL_FILES`/`ZSH_FILES` through the existing `_make_print` with the normal `PATH`;
- then, with `PATH="/usr/bin:${PATH}"` and a test-scoped `LC_ALL=en_US.UTF-8`, runs
  `_sorted_lines_from_space_list` on each and the same `comm -12` / `comm -23` pipeline the
  disjointness tests use. The locale is pinned because under `C.UTF-8` the unfixed pipeline also
  passes; the per-command `LC_ALL=C` prefixes inside the helper and on `comm` override it, so the
  fixed code still runs in C collation;
- writes the sorted lists to files under `BATS_TEST_TMPDIR` and runs `comm -12` on those files
  directly, capturing its exit status and its stderr in a file, not through `$(...)` inside a
  process substitution. A failing uutils `comm` still prints the correct overlap
  (`config/profiles.sh` alongside rc 1), so the overlap check alone passes on the broken tree;
- asserts `comm` exits 0, its stderr contains no `not in sorted order`, and the overlap equals
  `_KNOWN_SHELL_ZSH_OVERLAP` (a specific non-empty value, so a pipeline producing nothing fails).

Accepted trade-off: on macOS, the Studio, any GNU-first runner and any box without the
`en_US.UTF-8` locale this test skips, and a bats skip counts as a pass (the existing "collation
assertion never runs in CI" row). It discriminates on `claude` and `workstation`, which is where
the defect occurs.

### 3. CI coreutils probe

Add a `Tool versions` step to the `test` job before `Run tests`, mirroring `test-macos`'s step of
the same name. It prints `locale`, `locale -a`, `command -v sort comm || true`,
`sort --version | head -1` and `comm --version | head -1`. It never fails the job on content:
`command -v` exits 1 when either tool is missing, which would fail the step under the runner's
default `bash -e`, hence `|| true`. `locale` is what separates the first two explanations above;
the versions alone cannot. `locale -a` shows whether the section 2 test can run on the runner at
all, since it skips without `en_US.utf8`.

### 4. Backlog

- Close the `makefile_lint_scope.bats` uutils row on merge.
- Close the `sort -u` lossy row as not reproducible under uutils 0.10.0, with the measurement above.
- Add a P3 row: `pyenv.d/rehash/dotfiles-register-all-executables.bash` exists for the 0.8.0
  `sort -u` defect; re-measure `pyenv versions --executables` under 0.10.0 and retire it if clean.
- After CI runs, record the runner's `sort --version` and `locale` on the `powershell` row.

## Verification

- RED before the fix, on `claude`: `PATH="/usr/bin:${PATH}" bats tests/scripts/makefile_lint_scope.bats`
  shows the two disjointness tests `not ok` and the new test `not ok`. Predicted, from the
  measurement above.
- GREEN after: the same command shows 0 `not ok`; `make test` exits 0.
- Mutation: delete `LC_ALL=C` from `_sorted_lines_from_space_list`; the new test goes red on `claude`.
- CI `test` job log shows the `Tool versions` output.

## Requirements

- **R1.** Every `sort` and `comm` invocation in `tests/scripts/makefile_lint_scope.bats` is prefixed with `LC_ALL=C`.
- **R2.** No `setup()` or file-level code in `tests/scripts/makefile_lint_scope.bats` exports or sets `LC_ALL`, `LC_COLLATE` or `LANG`.
- **R3.** A new test in `tests/scripts/makefile_lint_scope.bats` skips unless both `/usr/bin/sort --version` and `/usr/bin/comm --version` contain `uutils` and `locale -a` lists `en_US.utf8`, and otherwise runs `_sorted_lines_from_space_list` and the `comm -12`/`comm -23` pipeline with `/usr/bin` first on `PATH` under a test-scoped `LC_ALL=en_US.UTF-8`.
- **R4.** The R3 test runs `comm -12` on files, captures its exit status and stderr directly (not via `$(...)` inside a process substitution), and asserts exit 0, no `not in sorted order` on stderr, and an overlap equal to `_KNOWN_SHELL_ZSH_OVERLAP`.
- **R5.** `.github/workflows/ci.yml`'s `test` job has a `Tool versions` step before `Run tests` that prints `locale`, `locale -a`, `command -v sort comm || true`, `sort --version | head -1` and `comm --version | head -1`.
- **R6.** The `makefile_lint_scope.bats` uutils Backlog row and the `sort -u` lossy row are removed from their open tables, and a P3 row for retiring the pyenv rehash hook is added.
- **V1.** On `claude`, `PATH="/usr/bin:${PATH}" bats tests/scripts/makefile_lint_scope.bats` shows 3 `not ok` before the fix and 0 after.
- **V2.** Deleting `LC_ALL=C` from `_sorted_lines_from_space_list` turns the R3 test red on `claude`.
- **V3.** The CI `test` job log for the PR shows the `Tool versions` output, and its `sort --version` and `locale` lines are recorded on the `powershell` Backlog row.
- **N1.** No change to any file under `lib/`.
- **N2.** No change to `pyenv.d/`.
- **N3.** The `Tool versions` step does not fail the job on any version string.

## Multi-Lens Review

Reviewed at commit: `e042053f` (Step 7 self-review commit, before Step 8 dispatch)

### Round 1

All three lenses independently reached the same finding; it is recorded once per lens.

#### Goal-Fit

Finding: Section 1 fixes the problem, but the spec omits locale as an explanation for green CI. If the runner is uutils under `C.UTF-8`, the R3 test runs on CI and passes with or without the fix, and the R5 probe answers nothing because it prints no locale. Fix: print `locale` in R5; pin a test-scoped `en_US.UTF-8` in R3, skipping if absent.
Assumption: CI is green because the runner's locale is `C.UTF-8`, not because GNU coreutils come first. Settled by one CI run printing `locale` and `sort --version`.
Disposition: Addressed (operator, 2026-10-24) — locale named as the third explanation; R3 pins `LC_ALL=en_US.UTF-8` and skips without it; R5 prints `locale`.

#### Ergonomics

Finding: Same locale gap. Day-to-day cost otherwise low; the only manual chore is copying the V3 values onto the `powershell` row.
Assumption: same as Goal-Fit.
Disposition: Addressed (operator, 2026-10-24) — as Goal-Fit.

#### Risk

Finding: Same locale gap, plus an implementation trap: a failing uutils `comm` still prints the correct overlap, so the overlap assertion alone passes on the broken tree; the test must capture `comm`'s rc and stderr directly. Spec-time count is 10 `sort` + 4 `comm`, not 13 + 4.
Assumption: same as Goal-Fit.
Disposition: Addressed (operator, 2026-10-24) — R4 now runs `comm` on files and captures rc and stderr directly; count corrected.

### Round 2

Reviewed at commit: `cd753b23` (all three lenses, re-run after the round-1 revision changed design substance)

#### Goal-Fit

Finding: No issues. Measured on a scratch clone: before the fix, `PATH="/usr/bin:${PATH}" bats tests/scripts/makefile_lint_scope.bats` gives `not ok 3` and `not ok 17` of 32; with `LC_ALL=C` on all 14 lines, 0 of 32 under `LC_ALL=en_US.UTF-8`. `locale` exits 0 under a missing locale.
Assumption: no uncertain assumption found — the CI runner's coreutils and locale decide only whether R3 skips there, and both outcomes are covered.
Disposition: N/A — clean, no action needed

#### Ergonomics

Finding: R5 does not print `locale -a`, so one CI run cannot show whether the R3 test can ever run there; and `command -v sort comm` exits 1 if either tool is missing, failing the step under `bash -e` against N3.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-10-24) — R5 prints `locale -a` and appends `|| true` to `command -v`. Wording-level; re-run scoped to the ergonomics lens on section 3 and R5.

#### Risk

Finding: No issues. Locale pin verified (mutation still red), empty input fails, `CLEAN_PATH` keeps the `/usr/bin`-first `PATH` out of `make`/`git`, no `tests/mocks/` shadowing, `workstation` has uutils 0.10.0 and `en_US.utf8`.
Assumption: no uncertain assumption found.
Disposition: N/A — clean, no action needed

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
