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
disjointness tests passed (`ok 245`, `ok 259`). That is consistent with GNU coreutils ahead of
uutils on the runner image, or with uutils tools that happen to agree on these inputs. Nothing in
the job prints which. The `powershell` backlog row names this as the open question.

## Design

### 1. C collation on every `sort` and `comm` in the file

Prefix `LC_ALL=C` to every `sort` and `comm` invocation in
`tests/scripts/makefile_lint_scope.bats`, including `_sorted_lines_from_space_list`.

Every one, not only those feeding `comm`: helper output is compared for equality with other
`sort -u` output in the same file (for example `:147` against `:148`, `:791` against `:786`), so
converting only the helper would mix collations on the two sides of an equality. The set is
enumerated at plan time with `grep -nE '(^|[^_a-z])(sort|comm)( |$)'`; at spec time it is 13
`sort` lines and 4 `comm` lines.

Rejected: `export LC_ALL=C` in `setup()`. It would also put the `make print-*` and `git ls-files`
calls under test into C locale, so a locale-dependent defect in the production derivation would
be masked. The fix changes only the test's own comparison tools.

### 2. A regression test that discriminates on uutils boxes

A green CI run cannot gate this fix if the runner has GNU coreutils first. Add one test that:

- skips unless `/usr/bin/sort --version` and `/usr/bin/comm --version` both report `uutils`;
- obtains `SHELL_FILES`/`ZSH_FILES` through the existing `_make_print` with the normal `PATH`;
- then, with `PATH="/usr/bin:${PATH}"`, runs `_sorted_lines_from_space_list` on each and the same
  `comm -12` / `comm -23` pipeline the disjointness tests use;
- asserts `comm` exits 0, its stderr contains no `not in sorted order`, and the overlap equals
  `_KNOWN_SHELL_ZSH_OVERLAP` (a specific non-empty value, so a pipeline producing nothing fails).

Accepted trade-off: on macOS, the Studio and any GNU-first runner this test skips, and a bats skip
counts as a pass (the existing "collation assertion never runs in CI" row). It discriminates on
`claude` and `workstation`, which is where the defect occurs.

### 3. CI coreutils probe

Add a `Tool versions` step to the `test` job before `Run tests`, mirroring `test-macos`'s step of
the same name. It prints `command -v sort comm`, `sort --version | head -1` and
`comm --version | head -1`. It never fails the job on content.

### 4. Backlog

- Close the `makefile_lint_scope.bats` uutils row on merge.
- Close the `sort -u` lossy row as not reproducible under uutils 0.10.0, with the measurement above.
- Add a P3 row: `pyenv.d/rehash/dotfiles-register-all-executables.bash` exists for the 0.8.0
  `sort -u` defect; re-measure `pyenv versions --executables` under 0.10.0 and retire it if clean.
- After CI runs, record the runner's `sort --version` on the `powershell` row.

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
- **R3.** A new test in `tests/scripts/makefile_lint_scope.bats` skips unless both `/usr/bin/sort --version` and `/usr/bin/comm --version` contain `uutils`, and otherwise runs `_sorted_lines_from_space_list` and the `comm -12`/`comm -23` pipeline with `/usr/bin` first on `PATH`.
- **R4.** The R3 test asserts `comm` exit 0, no `not in sorted order` on stderr, and an overlap equal to `_KNOWN_SHELL_ZSH_OVERLAP`.
- **R5.** `.github/workflows/ci.yml`'s `test` job has a `Tool versions` step before `Run tests` that prints `command -v sort comm`, `sort --version | head -1` and `comm --version | head -1`.
- **R6.** The `makefile_lint_scope.bats` uutils Backlog row and the `sort -u` lossy row are removed from their open tables, and a P3 row for retiring the pyenv rehash hook is added.
- **V1.** On `claude`, `PATH="/usr/bin:${PATH}" bats tests/scripts/makefile_lint_scope.bats` shows 3 `not ok` before the fix and 0 after.
- **V2.** Deleting `LC_ALL=C` from `_sorted_lines_from_space_list` turns the R3 test red on `claude`.
- **V3.** The CI `test` job log for the PR shows the `Tool versions` output, and its `sort --version` line is recorded on the `powershell` Backlog row.
- **N1.** No change to any file under `lib/`.
- **N2.** No change to `pyenv.d/`.
- **N3.** The `Tool versions` step does not fail the job on any version string.
