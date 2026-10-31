# makefile_lint_scope partition scanner: prefilter before the per-line loop

- **Date:** 2026-10-30
- **Context:** found by the per-file timing taken for the `test-macos` shard spec
  (`docs/superpowers/specs/2026-10-30-test-macos-shard-design.md`). Ships before that spec.

## Problem

The test "every stdout-capturing make -C invocation in-domain is guarded or measuring, both sets
nonempty" in `tests/scripts/makefile_lint_scope.bats` reads every line of every tracked
`tests/*.bats` and `tests/*.bash` file through a bash `while read` loop. For each line it calls
`_is_make_c_candidate`, which runs a bash regex and case-folds the text. Bats traces every command
it runs, so the loop's per-line cost is large.

| Measurement                           | Population                                   | Result                                                                   |
| ------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------ |
| `bats --timing` on the file           | `claude`, this tree                          | this test 66.9 s; every other test in the file under 0.4 s               |
| Serial per-file timing                | Studio, `faa2f993`, `env -i`                 | the file took 60 s (1.82 s/test, the highest of any file with 10+ tests) |
| Lines scanned                         | `git ls-files 'tests/*.bats' 'tests/*.bash'` | 52,162                                                                   |
| Lines matching `_MAKE_C_FORM_RE`      | same, after `_join_continuations`            | 377                                                                      |
| Candidates, unfiltered vs prefiltered | same, bash outside bats (probe script)       | 55 and 55, identical; 3.08 s and 0.36 s                                  |

On dotfiles#408, `test-macos` stalled twice at `ok 246`. On CI that is the last test of
`tests/scripts/list_shell_files.bats`, so this file was the first one unfinished both times.
Whether this test caused the stalls is not established. It is the single most expensive test in
the suite, whatever the cause.

## Design

`_is_make_c_candidate` rejects any line that does not match `_MAKE_C_FORM_RE`, and that is its
first check. Filtering the loop's input on the same regex therefore cannot change the candidate
set. It only removes iterations that would have been rejected anyway.

1. Pipe `_join_continuations "${_f}"` through `grep -E` before the `while read` loop.
2. The loop reads `<lineno>:<content>` lines, and `_MAKE_C_FORM_RE` begins with
   `(^|[[:space:]])`, where `^` means the start of the content. The prefilter pattern therefore
   replaces that leading group with `(^[0-9]+:|[[:space:]])`. It is derived from
   `_MAKE_C_FORM_RE` in the file (one place builds it from the constant), not retyped. Otherwise
   a line whose content begins with `-C` would be dropped.
3. A `grep` that matches nothing exits 1. That must not abort the test or read as an error. A
   genuine `grep` failure (exit 2) must fail the test.
4. Nothing else changes: `_is_make_c_candidate`, the comment, `@test` and grep-led exclusions, and
   the guarded/measuring classification are untouched.

## Testing

TDD in `tests/scripts/makefile_lint_scope.bats`:

- **Differential over the real tree:** the candidate list produced with the prefilter equals the
  list produced by the unfiltered loop. The list is non-empty (55 today, asserted as more than
  zero, not as 55).
- **Anchor fixture:** a fixture file whose line's content begins with `make -C` at column 0 is
  found by the prefiltered path. If the prefilter used a bare `^`, it would be dropped.
- **Mutation controls**, each applied alone, must turn at least one test red:
  1. Replace the prefilter regex with one that matches nothing.
  2. Replace the `(^[0-9]+:|…)` group with a bare `^`.
- **Timing:** `bats --timing` before and after, recorded in the PR body, not asserted.

## Requirements

- **R1.** `[PR1]` The make -C partition test filters each file's `_join_continuations` output with a `grep -E` pattern derived from `_MAKE_C_FORM_RE` before the per-line loop, with the content-start anchor mapped to the `<lineno>:` prefix.
- **R2.** `[PR1]` A test asserts the prefiltered and unfiltered candidate lists over the real tree are identical and non-empty.
- **R3.** `[PR1]` A fixture whose line's content starts with `make -C` at column 0 is found by the prefiltered path.
- **R4.** `[PR1]` A prefilter `grep` exit of 1 (no match in a file) does not fail the test; any other non-zero exit does.
- **V1.** Mutation controls: a never-matching prefilter and a bare-`^` anchor each turn at least one test red.
- **V2.** `bats --timing tests/scripts/makefile_lint_scope.bats` on `claude` shows the partition test under 5 s, recorded in the PR body.
- **N1.** No change to `_is_make_c_candidate`, the exclusion rules, or the guarded/measuring classification.
- **N2.** No change to any other test in the file or the suite.
