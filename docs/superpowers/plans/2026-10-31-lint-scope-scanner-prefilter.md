# Lint-scope scanner prefilter Implementation Plan

spec: docs/superpowers/specs/2026-10-30-lint-scope-scanner-prefilter-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the make -C partition test in `tests/scripts/makefile_lint_scope.bats` from ~67 s to under 5 s by grep-prefiltering each file before the per-line bash loop, without changing the candidate set.

**Architecture:** Two new file-scope helpers in the bats file. `_make_c_prefilter_re` derives the grep pattern from `_MAKE_C_FORM_RE`. `_make_c_prefiltered_lines` runs `_join_continuations` and `grep` and triages grep's exit status. Equivalence is proven on a tracked edge fixture (`tests/fixtures/make_c_prefilter_edges.txt`). It is a `.txt` file, so it sits outside the scanner's own `tests/*.bats tests/*.bash` domain and cannot become a real-tree candidate. The partition test then reads the helper's output through a here-string.

**Tech Stack:** bash 5, bats-core, GNU/BSD `grep -E`, awk.

## Global Constraints

- No change to `_is_make_c_candidate`, the exclusion rules, the per-segment reclassification, or the guarded/measuring classification (N1).
- No change to any other existing test in the file or the suite (N2).
- grep runs as `PATH="${CLEAN_PATH}" LC_ALL=C grep -a -E` (R1).
- The pattern is derived from `_MAKE_C_FORM_RE`, never retyped (R1, R5).

## Verification

- Whole change: `bats --timing tests/scripts/makefile_lint_scope.bats` on `claude`. Every test is `ok`, the partition test runs under 5 s, and the file under 15 s. Baseline before the change: 66,871 ms for the test and 73 s for the file. The partition test's stderr line still reports `candidates=` above 0, with `neither=0`.
- `make test` exits 0. The orchestrator runs it once after Task 2. Task gates are scoped: each task edits one bats file and one fixture that no other test reads. The bats gate covers the file, and `make lint` covers shellcheck.
- V3: after Task 2, run the bats file on the Studio from a `git archive` of the branch, under the bare `env -i` form in `CLAUDE.md`. Every edge-fixture test must be `ok`.
- The rc 2 and derivation-failure paths are exercised through seams: an optional pattern argument on each helper.

---

### Task 1: Prefilter helpers and edge-fixture tests

```yaml-task
id: 1
description: Add _make_c_prefilter_re and _make_c_prefiltered_lines with an edge fixture and tests for equivalence, status triage and derivation guard
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5]
acceptance:
  - cmd: bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/scripts/makefile_lint_scope.bats, tests/fixtures/make_c_prefilter_edges.txt]
depends_on: []
```

**Files:** Create `tests/fixtures/make_c_prefilter_edges.txt` with exactly these 11 lines. Line 7 has a literal TAB between `make` and `-C`.

```
-C "$d" make print-X
--directory "$d" make print-X
make -C"$d" print-X
make -C'$d' print-X
make -C$d print-X
make --directory "$d" print-X
make	-C "$d" print-X
make -Cfoo print-X
make \
  -C "$d" print-X
echo no flag here
```

Expected candidate line numbers: `1 2 3 4 5 6 7 9`. Line 8 (`-Cfoo`) and line 11 are not candidates. Line 10 is joined into line 9.

Add the helpers directly after `_is_make_c_candidate`:

```bash
# The grep prefilter for the make -C partition test: _MAKE_C_FORM_RE with its
# content-start anchor moved past the "<lineno>:" prefix _join_continuations
# adds. $1 overrides the source regex (test seam only).
_make_c_prefilter_re() {
  local _form_re="${1:-${_MAKE_C_FORM_RE}}" _re
  _re="${_form_re/#'(^|'/'(^[0-9]+:|'}"
  if [[ "${_re}" == "${_form_re}" ]]; then
    printf '_make_c_prefilter_re: _MAKE_C_FORM_RE no longer starts with (^|\n' >&2
    return 1
  fi
  printf '%s\n' "${_re}"
}

# The "<lineno>:<content>" lines of $1 that can hold a make -C candidate.
# grep's status is read directly: 1 is "no match", any other failure fails.
# $2 overrides the pattern (test seam only).
_make_c_prefiltered_lines() {
  local _file="$1" _re _joined _out _rc
  _re="${2:-$(_make_c_prefilter_re)}" || return 1
  _joined="$(_join_continuations "${_file}")" || {
    printf '_make_c_prefiltered_lines: _join_continuations failed on %s\n' "${_file}" >&2
    return 1
  }
  _out="$(PATH="${CLEAN_PATH}" LC_ALL=C grep -a -E "${_re}" <<< "${_joined}")"
  _rc=$?
  case "${_rc}" in
    0) printf '%s\n' "${_out}" ;;
    1) ;;
    *)
      printf '_make_c_prefiltered_lines: grep exited %s on %s\n' "${_rc}" "${_file}" >&2
      return 1
      ;;
  esac
}
```

Check that `_re="${2:-$(…)}" || return 1` really propagates a derivation failure. If it does not, split it into an `if [[ -n "${2:-}" ]]` branch.

**Tests (RED first, one at a time). Each is a new `@test` after the partition test:**

1. "make -C prefilter: edge fixture candidates agree unfiltered, prefiltered and expected". Collect line numbers where `_is_make_c_candidate` holds over `_join_continuations` of the fixture (unfiltered), and over `_make_c_prefiltered_lines` output read through a here-string (prefiltered; skip an empty `_ln`). Compare both to `"1 2 3 4 5 6 7 9"`. On a mismatch, print `expected:`, `unfiltered:`, `prefiltered:` and, per arm, `missing:`/`extra:` words to stderr, then fail.
2. "make -C prefilter: a file with no candidate yields no lines and status 0". Write `echo no flag here` to `${BATS_TEST_TMPDIR}/none.txt`, then `run _make_c_prefiltered_lines` on it (plain `run`: stderr merges into `$output`, so an unexpected message also fails the test). Expect status 0 and empty output. Do not add `bats_require_minimum_version` or `--separate-stderr`; tests 3–5 also read the merged `$output`.
3. "make -C prefilter: an invalid pattern fails and names the file". Run with `$2='('`, expect status 1, and expect `$output` to contain `grep exited 2` and the file path.
4. "make -C prefilter: a missing file fails and names it". Point at a nonexistent path and expect status 1, with `$output` naming `_join_continuations failed` and the path.
5. "make -C prefilter: derivation refuses a regex without the (^| anchor". Run `_make_c_prefilter_re '([[:space:]])-C'`, expect status 1, and expect `$output` to contain `_MAKE_C_FORM_RE no longer starts with (^|`.

**Mutation controls.** Apply each alone, show its `git diff`, and run the file. Report which test goes red, then revert:

- (a) the replacement `'(^[0-9]+:|'` changed to `'(^|'`. Test 1 must fail, because lines 1 and 2 drop.
- (b) the `*)` arm made to behave like `1)` (no message, `return 0`). Test 3 must fail.
- (c) the `if [[ "${_re}" == "${_form_re}" ]]` guard removed. Test 5 must fail.

A diff that changes nothing is a failed control.

- [ ] Fixture + test 1 RED (helpers absent), then helpers, GREEN
- [ ] Tests 2–5, each RED against a deliberately broken branch, then GREEN
- [ ] Mutations (a)–(c) recorded
- [ ] `bats tests/scripts/makefile_lint_scope.bats` and `make lint` green; commit (`caveman:caveman-commit`)

**Interfaces:** Produces `_make_c_prefiltered_lines <file> [pattern]`. It returns 0 and prints `<lineno>:<content>` lines (none on no match). It returns 1 with a stderr message on failure. Task 2 consumes it.

### Task 2: Wire the prefilter into the partition test

```yaml-task
id: 2
description: Feed the make -C partition test's per-line loop from _make_c_prefiltered_lines instead of the unfiltered join
role: executor
model: sonnet
tdd: required
requirements: [R1]
acceptance:
  - cmd: bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/scripts/makefile_lint_scope.bats]
depends_on: [1]
```

**Change** in the "every stdout-capturing make -C invocation in-domain…" test: declare `local _lines` next to `local _f _lineno _content`. In the `for _f` loop, before the `while`, add `_lines="$(_make_c_prefiltered_lines "${_f}")" || return 1`. Replace `done < <(_join_continuations "${_f}")` with `done <<< "${_lines}"`. Leave everything else in the test untouched (N1). That includes the existing `[ -z "${_lineno}" ] && continue`, which absorbs the here-string's empty line.

**RED/GREEN:** this is a speed change with an unchanged verdict. RED is the timing: record `bats --timing` for the partition test before the edit (about 67 s). GREEN means the test is still `ok` and takes under 5 s. Its stderr line `domain_files=… candidates=… guarded=… measuring=… neither=0` must show the same `candidates`, `guarded` and `measuring` counts before and after. Capture both with `bats --filter 'every stdout-capturing' --print-output-on-failure`, or by temporarily adding `false` at the end, and report both lines.

**Mutation control (d):** make `_make_c_prefiltered_lines` print nothing (an early `return 0`). Show the diff, confirm the partition test fails on `[ "${#_candidates[@]}" -gt 0 ]`, then revert.

- [ ] Before-counts and timing recorded
- [ ] Edit; after-counts identical; timing under 5 s; file total under 15 s
- [ ] Mutation (d) recorded
- [ ] Gates green; commit (`caveman:caveman-commit`)

**Interfaces:** Consumes `_make_c_prefiltered_lines` from Task 1.

## Orchestrator steps after Task 2

1. `make test </dev/null` in the worktree. It must exit 0.
2. V3 on the Studio: `git archive HEAD | ssh studio 'd=$(mktemp -d /tmp/pf.XXXXXX) && tar -x -C "$d" && cd "$d" && env -i HOME="$(mktemp -d)" PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bats tests/scripts/makefile_lint_scope.bats' </dev/null`. Every `make -C prefilter` test must be `ok`. The tarball has no `.git`, so tests that need git may skip or fail there. Judge only the `make -C prefilter` tests (V3 needs no more), and record which others did not run.
3. Phase 3 (`finishing-a-development-branch`), with the before/after timing in the PR body.

## Non-goal check

- N1: CLEAR. The helpers are added after `_is_make_c_candidate`. Task 2 changes only the partition loop's input source.
- N2: UNCLEAR. Reviewer quote: "Add `bats_require_minimum_version 1.5.0` at file top if absent" — "a file-wide directive affecting every test in the file." Resolution: plan revised. Before: test 2 used `run --separate-stderr` and added the directive if absent. After: tests 2–5 use plain `run`, read the merged `$output`, and add no directive.
