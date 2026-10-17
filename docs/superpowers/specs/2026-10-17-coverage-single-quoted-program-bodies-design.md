# Bash coverage: exclude multi-line single-quoted program bodies

- **Date:** 2026-10-17
- **Status:** Draft (Phase 1)
- **Trigger:** PR #343 (apt stale-signer detection). CI `bash-coverage` read
  `TOTAL 5798 6372 90%` against the 91% gate. The same job's first attempt was cancelled at its
  25-minute cap.

## Problem

`_count_coverable_lines` (`scripts/run-bash-coverage.sh`) counts every non-blank, non-comment,
non-structural line as a coverable command, apart from a few documented exclusions. One of them
is the body of a multi-line `python3 -c "..."`, which bash xtrace reports as a single command at
its opener line. The **single-quoted** form of the same thing has no exclusion: a multi-line
argument opened with `'` and closed on a later line. That covers `awk … '`, `python3 -c '`,
`bash -lc '` and so on. Every body line counts as coverable and can never be traced, so it
reads as permanently uncovered.

PR #343 put a 28-line `awk` program in `_apt_stale_signer_hosts` (`lib/linux_shared.sh`). That
file's coverable count went from 81 on master to 122 on the branch, and the CI total dropped to
90.99%, which prints as 90%. The new code is tested. The lines it "misses" are awk, not bash.

The CI job's cap is the second, separate problem. `ci.yml` has
`timeout-minutes: 25 # p90 492s, measured 2026-08-27`. The last 11 CI runs of the job took
14–24 minutes. The cap now sits at roughly 1x a current run, where the repo's own sizing rule
(CLAUDE.md, CI section) calls for about 3x p90.

## Measurements

All on 2026-10-17.

- **M1, PR #343 CI.** Attempt 2's job log: `TOTAL 5798 6372 90%` /
  `FAIL: bash coverage 90% is below the 91% gate`. Attempt 1 was cancelled in the coverage step
  at 25m13s. Population: one CI run of #343's head `06782300` on `ubuntu-latest`.
- **M2, coverable count.** `bash scripts/run-bash-coverage.sh --count-coverable` gives 81 for
  `lib/linux_shared.sh` on `origin/master` and 122 at `06782300`. The awk program spans lines
  189–218 at that commit. Population: that one file, on `claude`.
- **M3, rule population on master.** A scan of the instrumented set (`--list-sources`) on
  `claude`. It flags non-comment lines whose last non-space character is `'` and whose `'`
  count is odd, and stops at the next line whose first non-space character is `'`. It found
  7 regions with 117 body lines:
  - `lib/developer.sh:573` `bash -lc '` (4)
  - `lib/helpers.sh:1030` and `:1072` `awk … '` (13 + 13)
  - `lib/workflows.sh:1353`, `:1393` and `:1428` `python3 -c '` (29 + 24 + 25)
  - `scripts/refresh-sha256-pins.sh:32` `python3 -I -c '` (9)

  The scan does not track heredoc, `python3 -c "` or continuation regions. It approximates the
  rule's reach and does not compute it. V1 measures the real effect.

- **M4, not matched by the rule (they stay counted, which errs toward a lower figure).**
  - `lib/workflows.sh:127` and `:141`: `python3 -c 'import json,sys`, where code follows the
    quote on the opener line.
  - `lib/update_summary.sh:463` and `:527`: `printf -v _base_json '{`, where content follows
    the quote.

## Design

### 1. The exclusion rule (`_count_coverable_lines`)

- **Opener.** A line that reaches the existing opener checks: it is outside every region
  (heredoc, `python3 -c "`, array, continuation), and it is not blank and not a comment. It
  opens a single-quoted region when, after trailing whitespace is stripped, its last character
  is `'` **and** it contains an odd number of `'` characters. The opener line itself still
  counts, because xtrace attributes the command to it, as it does for `python3 -c "`.
- **Body and closer.** The following lines are skipped up to and including the first line whose
  first non-space character is `'`. The closer may carry trailing words (`' "$1"`, `')`,
  `' file`), and it is excluded, the same way the `python3 -c "` closer is.
- **Unterminated.** If the file ends inside a single-quoted region, the run fails loudly and
  names the opening line, matching the existing unterminated-`python3 -c` behaviour. A region
  that swallows to EOF would inflate the figure.
- **Mode `lines`** prints no excluded line, exactly as for the other exclusions.
- **Direction of error.** Each way the heuristic can be wrong lowers the figure or fails the
  run. It cannot raise it:
  - An extra apostrophe on the opener line makes the count even, so no region opens and the
    lines stay counted.
  - A body line that starts with `'` closes the region early, and the rest stays counted.
  - A trailing comment ending in an odd `'` could open a false region. It would either end at
    the next `'`-led line or hit EOF and fail loudly.

  The union of the heuristic with the real trace is unchanged: a line bash does trace is added
  back from the trace.

### 2. CI cap (`.github/workflows/ci.yml`)

- `bash-coverage` `timeout-minutes` goes from 25 to 60. The comment records the new basis: runs
  of 14–24 minutes measured 2026-10-17, and 60 is about 3x a typical run.
- In `CLAUDE.md`, the CI caps sentence ("`bash-coverage` 25") changes to 60. Nothing in the
  suite asserts cap values; the 2026-08-27 timeouts spec deliberately dropped such a test.

### 3. Documentation

`CLAUDE.md`'s Bash coverage bullet ("Exclude: heredoc bodies/terminators …") gains the
single-quoted case and its opener-at-end-of-line condition.

## Alternatives

- **awk only.** Rejected by the operator: it fixes #343 and leaves the `python3 -c '` twin in
  `workflows.sh`, and the other regions, counted.
- **Any odd single-quote parity.** Rejected by the operator: a quote-parsing mistake or an
  apostrophe swallows real code and inflates the figure, which is the failure direction the
  tracer's own comments warn about.
- **Move the awk program to a `.awk` file on #343.** Fixes only that one program, adds a file and
  a path lookup, and leaves the instrument flaw for the next program.
- **Lower the gate.** Not considered: the figure is wrong, not the floor.

## Testing

New tests in `tests/scripts/unit.bats`, next to the `python3 -c` ones. Each builds its fixture
in a heredoc, the existing style, and runs `_run_coverage --count-coverable`:

1. A multi-line `awk -v x="$1" '` program between two bash lines: the count is exactly 3
   (both bash lines and the opener).
2. A multi-line `python3 -c '` program: the same shape, the same exact count.
3. A closer with trailing words (`' "$1"`): excluded, and the next bash line is counted.
4. A single-line `awk '{print $1}' file`: counted as 1, not a region.
5. An opener with content after the quote (`printf '{`): not a region, and every line is
   counted.
6. An apostrophe in an earlier double-quoted word on the opener line (an even count): not a
   region, and every line is counted.
7. A body line starting with `'`: the region closes there, and the rest is counted.
8. An unterminated region: the run exits non-zero and names the opener line, like the
   `python3 -c` test.
9. **Positive control on a real file:** the exact `--count-coverable` value for
   `lib/helpers.sh` is 907: master's 935, minus each awk region's 13 body lines and one
   closer (M3). The plan re-measures this with the scan corrected for regions before pinning
   it. The test fails if the rule stops matching anything (935) or over-matches (below 907).

Mutation controls for the plan: drop the parity check (case 6 fails), drop the end-of-line
check (case 5 fails), and drop the closer exclusion (case 1's count changes).

## Requirements

- **R1.** `_count_coverable_lines` excludes the body and closing line of a multi-line single-quoted region opened by a non-comment line, outside every existing region, whose last non-space character is `'` and whose `'` count is odd, the closing line being the first later line whose first non-space character is `'`; the opener line stays counted.
- **R2.** A file that ends inside such a region makes the coverage run exit non-zero with a message naming the opening line number.
- **R3.** `.github/workflows/ci.yml` sets `timeout-minutes: 60` for the `bash-coverage` job, with a comment giving the 2026-10-17 measurement basis.
- **R4.** `CLAUDE.md` lists the single-quoted case in the Bash coverage exclusion bullet and gives `bash-coverage` a cap of 60 in the CI caps sentence.
- **R5.** `tests/scripts/unit.bats` contains tests 1–9 from the Testing section, and they pass.
- **V1.** Run `--count-coverable` over every file from `--list-sources` on `origin/master` before and after the change; record each file whose count moves and the total moved, and confirm every moved line falls inside one of the regions M3 lists.
- **V2.** Run `bash scripts/run-bash-coverage.sh` (full trace) on the branch; confirm no excluded line appears in the trace (the heuristic-disagreement count does not rise from master's) and record the overall figure.
- **V3.** After merge, re-run PR #343's CI on its head rebased onto the new master; `bash-coverage` passes the 91% gate within the cap.
- **N1.** The `python3 -c "`, heredoc, array and continuation exclusions behave exactly as before; every existing `run-bash-coverage` test passes unchanged.
- **N2.** The 91% floor and the union-with-trace rule are unchanged.
- **N3.** No line is excluded on the basis of a tool name; the rule is structural only.
