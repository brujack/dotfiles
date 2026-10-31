# makefile_lint_scope partition scanner: prefilter before the per-line loop

- **Date:** 2026-10-30
- **Approved:** 2026-10-31
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

1. A new helper, `_make_c_prefilter_re`, prints the prefilter pattern. It derives it from
   `_MAKE_C_FORM_RE` by replacing the leading `(^|` with `(^[0-9]+:|`: the loop reads
   `<lineno>:<content>` lines, so the content-start anchor must sit after the line-number
   prefix. If the replacement leaves the string unchanged (the constant no longer starts with
   `(^|`), the helper prints `_make_c_prefilter_re: _MAKE_C_FORM_RE no longer starts with (^|`
   to stderr and returns 1. The pattern is never retyped.
2. A second helper, `_make_c_prefiltered_lines <file>`, captures `_join_continuations` into a
   variable, then runs `PATH="${CLEAN_PATH}" LC_ALL=C grep -a -E "<pattern>"` over it, and
   captures grep's own exit status on the next line (no pipe, no process substitution, which
   would hide it). Status 0 prints the matching lines; status 1 prints nothing and returns 0;
   any other status, or a failure of `_join_continuations` or of the derivation, prints the
   file and status to stderr and returns 1. `LC_ALL=C` and `-a` keep a non-UTF-8 byte from
   turning a line into a `Binary file matches` summary or a status 2.
3. The partition test calls `_make_c_prefiltered_lines` once per file, failing the test on a
   non-zero return, and feeds its output to the existing `while read` loop through a
   here-string.
4. Nothing else changes: `_is_make_c_candidate`, the comment, `@test` and grep-led exclusions,
   the per-segment reclassification, and the guarded/measuring counts are untouched.

## Testing

TDD in `tests/scripts/makefile_lint_scope.bats`. The real-tree differential in the first draft
is dropped: run under bats, the unfiltered loop it compares against costs the same 62 s this
spec removes (measured in a probe on `claude`: unfiltered 62,318 ms, prefiltered 1,236 ms, 55
candidates each). Equivalence is proven on a fixture instead, where the unfiltered loop is
cheap.

- **Edge fixture.** One fixture file under `BATS_TEST_TMPDIR`, one line per case:
  1. content starting at column 0 with `-C "$d" make print-X` (the anchor case);
  2. content starting at column 0 with `--directory "$d" make print-X`;
  3. `make -C"$d"`, `make -C'$d'` and `make -C$d`, one per line;
  4. `make --directory "$d"`;
  5. a tab before `-C`;
  6. `make -Cfoo` (no separator; must not be a candidate);
  7. `make \` with `-C "$d" print-X` on the next line (a continuation join);
  8. a line with no `-C` at all.

  A line that starts with `make -C` does not test the anchor: the space before `-C` matches the
  `[[:space:]]` arm whatever the anchor is. Only content that starts with `-C` or
  `--directory` does.
- **Differential on the fixture.** The set of line numbers for which `_is_make_c_candidate`
  holds on the unfiltered `_join_continuations` output equals the set obtained from
  `_make_c_prefiltered_lines`. Both also equal a hand-typed expected set (every case except 6
  and 8; case 7 reported at the line of `make \`). On a mismatch the test prints both sets and
  their difference.
- **Status handling.** `_make_c_prefiltered_lines` on the fixture's no-match line alone (a file
  holding only case 8) returns 0 with empty output. With the derivation replaced by one that
  yields an invalid pattern, it returns 1 and names the file.
- **Derivation guard.** Called with a `_MAKE_C_FORM_RE` that lacks the leading `(^|`,
  `_make_c_prefilter_re` returns 1 with the message above.
- **Real tree.** The existing `${#_candidates[@]} -gt 0`, `_guarded -gt 0` and
  `_measuring -gt 0` assertions stay, so a prefilter that drops everything still fails.
- **Mutation controls**, each applied alone, must turn at least one test red:
  1. a prefilter pattern that matches nothing;
  2. the `(^[0-9]+:|` replacement changed to a bare `(^|`;
  3. grep's status 2 treated like status 1.
- **Timing.** `bats --timing` before and after, in the PR body.

## Multi-Lens Review

Round 1 against `a3c7b5e4` (goal-fit, ergonomics, risk). Dispositions accepted by the operator 2026-10-31.

| # | Lens | Finding | Disposition |
| - | ---- | ------- | ----------- |
| 1 | all three | R2's real-tree differential runs the unfiltered loop under bats and restores the 62 s cost (probe: 62,318 ms vs 1,236 ms, 55 candidates each). | Accepted. Replaced with an edge-fixture differential (R2, R3); real-tree non-empty assertions kept. |
| 2 | risk | R4 was unimplementable as designed: `done < <(... \| grep)` hides grep's exit status. | Accepted. grep runs over a captured variable and its status is read on the next line (Design 2). |
| 3 | risk | Unpinned grep: locale and binary-file handling can change the match set or exit 2. | Accepted. `PATH="${CLEAN_PATH}" LC_ALL=C grep -a -E` (R1). |
| 4 | ergonomics | A derivation whose substitution silently misses yields a pattern equal to the constant, and the anchor bug returns unseen. | Accepted. R5. |
| 5 | ergonomics | A differential failure that prints only "not equal" is unreadable. | Accepted. Difference printed (R2). |
| 6 | goal-fit | V2 should bound the file's total time, not only the one test. | Accepted. V2 bounds both. |
| 7 | orchestrator | The first draft's anchor fixture (`make -C` at column 0) cannot catch a bare-`^` anchor: the space before `-C` matches `[[:space:]]`. | Accepted. Fixture cases 1 and 2 start with `-C` / `--directory`. |
| 8 | goal-fit | BSD `grep` on macOS vs bash `=~` agreement is assumed, not shown. | Accepted. V3. |

Checked and not raised: regex-dialect differences between ERE and bash `=~` for this pattern (risk lens found none); the per-segment loop, which runs only on candidate lines and is unchanged.

## Requirements

- **R1.** `[PR1]` The make -C partition test filters each file's `_join_continuations` output with a `grep -a -E` pattern, run under `LC_ALL=C` and `PATH="${CLEAN_PATH}"`, derived from `_MAKE_C_FORM_RE` by replacing its leading `(^|` with `(^[0-9]+:|`.
- **R2.** `[PR1]` A test asserts that, on the edge fixture, the candidate line numbers from the unfiltered loop, from the prefiltered path and from a hand-typed expected set are identical, and prints the difference when they are not.
- **R3.** `[PR1]` The edge fixture includes content starting at column 0 with `-C` and with `--directory`, the `-C"`, `-C'` and `-C$` forms, a tab before `-C`, a continuation join, and `make -Cfoo`, which is not a candidate.
- **R4.** `[PR1]` A prefilter `grep` exit of 1 yields no lines and does not fail the test; any other non-zero grep exit, a `_join_continuations` failure or a derivation failure fails the test and names the file.
- **R5.** `[PR1]` If replacing the leading `(^|` leaves `_MAKE_C_FORM_RE` unchanged, the derivation prints an error naming `_MAKE_C_FORM_RE` and returns 1.
- **V1.** Mutation controls: a never-matching prefilter, a bare `(^|` anchor, and grep status 2 treated as 1 each turn at least one test red.
- **V2.** `bats --timing tests/scripts/makefile_lint_scope.bats` on `claude` shows the partition test under 5 s and the whole file under 15 s (73 s before), recorded in the PR body.
- **V3.** The edge-fixture tests pass on the Studio under the bare `env -i` reproduction, so BSD `grep` is shown to agree with bash `=~` on every fixture case.
- **N1.** No change to `_is_make_c_candidate`, the exclusion rules, the per-segment reclassification, or the guarded/measuring classification.
- **N2.** No change to any other test in the file or the suite.

## Amendments

- R1 -> The make -C partition test filters each file's `_join_continuations` output with a `grep -a -E` pattern, run under `PATH="${CLEAN_PATH}"` in the caller's locale, derived from `_MAKE_C_FORM_RE` by replacing its leading `(^|` with `(^[0-9]+:|`. — `LC_ALL=C` narrows grep's `[[:space:]]` to ASCII while bash `=~` follows the test's locale, so a line with a non-ASCII space (U+2003) was a bash candidate that grep dropped; same locale on both sides keeps the prefilter a superset, and `-a` alone covers binary input (Task 1 code review).

## Spec alignment (2026-10-31)

- spec: docs/superpowers/specs/2026-10-30-lint-scope-scanner-prefilter-design.md
- anchor: c5f03121b8b7c43d23af7330cb6a78756bd1ea0d
- in scope: R1, R2, R3, R4, R5
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |

### Reviewed

- none

### Verifications

- V1: Mutation controls run in Phase 2 and re-run by the orchestrator: a prefilter that drops everything (early return 0) -> partition test red; a prefilter that matches everything ('.') -> edge-fixture drop asserts red; bare (^| anchor (emit un-derived regex) -> edge-fixture test red, prefiltered missing lines 1 2; grep status 2 treated as 1 (*) ;;) -> invalid-pattern test red.
- V2: claude, bats --timing: partition test 65339 ms -> 2247 ms; whole file 73 s -> 9 s (41 ok). Recorded in PR body.
- V3: Studio, git archive of a57550ca under env -i HOME=tmp PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin: all 8 'make -C prefilter' tests ok, including the U+2003 test (ran, not skipped). Partition test not judged there: tarball has no .git.
