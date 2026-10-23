# bats stdin hang: redirect the recipes, bound each test, fix the gpg mock

- **Date:** 2026-10-22
- **Backlog row:** `docs/superpowers/README.md` P2, "A bats run that inherits a live stdin socket hangs at 0% CPU indefinitely, and nothing detects or bounds it"
- **Approved:** 2026-10-22
- **Operator decisions (2026-10-22):** redirect stdin on the bats recipe lines and fix the mock that actually reads stdin; the per-test timeout first proposed is descoped to the backlog after Step 8 round 1.

## Problem

A test that reads stdin blocks forever when the stdin it inherits never reaches EOF. The
harness Bash tool runs commands under a `zsh -c` whose fd0 is a unix socket
(`socket:[283044181]`, observed 2026-10-22), so any bats process started from it without a
redirect inherits that socket. Nothing bounds a test's runtime, so the run sits at 0% CPU with
no output.

The backlog row measured this 2026-10-11 (17 min stalled, killed by PID). Re-measured
2026-10-22 on `claude` at `f5d7bfcb`, with a FIFO held open as stdin to stand in for the
socket:

| Run                                                                                              | stdin              | Result                                                              |
| ------------------------------------------------------------------------------------------------ | ------------------ | ------------------------------------------------------------------- |
| `bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats` (serial, direct) | open FIFO          | stalled after `ok 133` of `1..393`; killed by `timeout 300`, rc 124 |
| `make test` (parallel path, `bats --jobs 24`)                                                    | never-closing pipe | completed: 3373 ok, 0 not ok                                        |

The stalled test is `workflows.bats` "run_setup_or_developer calls apt-get on Ubuntu". Its
process tree at the stall showed `tests/mocks/gpg` blocked in `anon_pipe_read` with fd0 = the
FIFO. `tests/mocks/gpg` ends with an unconditional `while IFS= read -r _; do :; done`, so every
call drains stdin, including calls the real `gpg` would never read stdin for. The parallel
`make test` path survived because GNU parallel does not pass its own stdin to the jobs; the
serial paths have no such protection.

Exposed paths on master `f5d7bfcb`:

- `Makefile` `test-unit` (`bats $(BATS_FLAGS) tests/setup_env/unit.bats …`), the quickest loop and the one most often run by hand.
- `Makefile` serial recipe lines: `bats $(BATS_FLAGS) $(BATS_PARALLEL_FILES)` (no GNU parallel)
  and `bats $(BATS_FLAGS) $(BATS_SERIAL_FILES)`. The parallel line
  `bats --jobs $(JOBS) …` is protected by parallel today but has no redirect of its own.
- `scripts/run-bash-coverage.sh:807`: `"${_bats_bin}" "${_bats_args[@]}" > "${bats_log}" 2>&1`,
  serial whenever `COVERAGE_BATS_JOBS` is unset or parallel is absent.
- Any direct `bats <file>` an operator or agent runs.

The FIFO stands in for the socket only for readers that drain unconditionally. A FIFO satisfies
`[[ -p /dev/stdin ]]`, which `argv_probe_stub_path` (`tests/helpers/common.bash`) uses to decide
whether a generated stub drains stdin, and a socket does not: over the whole suite a FIFO stdin
produced 5 false hangs in such stubs (round-1 Goal-Fit lens). The two files in V2 reach none of
them. Any whole-suite claim needs a socket.

Prior art: `tests/setup_env/ledger_integration.bats` carries `exec < /dev/null` for the same
class (a `cat` in the `ledger` mock); the P3 row "A mock that `cat`s stdin blocks forever on a
non-EOF fd0" tracks the other stdin-reading mocks. No spec or ADR has proposed or rejected a
recipe redirect or a test timeout (grep of `docs/adr` and `docs/superpowers/specs` for
`stdin`, `BATS_TEST_TIMEOUT`, `hang`).

## Design

Operator decision 2026-10-22, after round 1 of Step 8: ship the stdin redirect and the gpg
mock fix; the per-test timeout is not part of this change (see "Why no timeout").

### 1. Recipes never pass an inherited stdin to bats

Append `< /dev/null` to every `bats` recipe line in the `Makefile`: the three in the `test`
recipe (the `--jobs` line, the serial `BATS_PARALLEL_FILES` line, the `BATS_SERIAL_FILES`
line) and the one in `test-unit`. Do the same for the bats invocation in
`scripts/run-bash-coverage.sh` (the `"${_bats_bin}" "${_bats_args[@]}" > "${bats_log}" 2>&1`
line). A test that needs stdin supplies its own (a heredoc, a pipe, a file); none may depend on
the caller's. One existing assertion compares a bats recipe line exactly:
`tests/makefile_parallel_target.bats` "a carved-out file leaves the parallel pool and runs
alone afterwards" uses `grep -qx` on the carve-out line; its expected string gains the
redirect (the check stays an exact match). This is already the condition `scripts/pre-push` runs the suite under: the hook
drains git's ref list before `make test`, so its stdin is at EOF and no test can rely on a live
one.

### 2. The gpg mock reads stdin only when gpg would

`tests/mocks/gpg` keeps logging every call, and drains stdin only when the invocation is one
that reads it: `--dearmor` or `--enarmor` with no file operand, or an operand of `-`. An
option's argument (for example the file after `-o`) is not an operand. Every other call returns
without touching fd0. Options that take an argument (`-o`, `--output`, `--homedir`,
`--status-fd`, `--keyring`) consume it, so `-o -` is not read as a `-` operand. The production call sites that feed gpg stdin are `lib/linux_ubuntu.sh`
`--dearmor < "${_key}"` and `--batch --yes --dearmor -o … < key`; both stay drained. Every
other production call (`--import`, `--verify`, `--show-keys`) takes a file operand. No test pipes
into `tests/mocks/gpg`. `tests/mocks/gpg-dearmor` is only reached through `_APT_KEY_GPG_BIN`,
whose caller always redirects stdin from a file, and is left alone. The `ledger` mock and the
other stdin-reading mocks stay on their P3 row.

This is the fix that reaches a direct `bats <file>` run, which no `Makefile` change can, and it
carries most of the value. Measured by the round-1 Goal-Fit lens with a real unix socket as stdin
(Python `socketpair`, plain `bats` over the whole suite in six groups): with this mock change,
3373/3373 ok; with the original mock, only "run_setup_or_developer calls apt-get on Ubuntu"
hung. The §1 redirects are defence in depth for the serial `make` paths (`HAVE_PARALLEL=`,
`BATS_SERIAL_FILES`, `test-unit`, a serial coverage run): GNU parallel already withholds stdin
from `--jobs` runs.

Rejected: `exec 0</dev/null` in `tests/helpers/common.bash`, the backlog row's own candidate.
Only 56 of the 80 `.bats` files load that helper, so it would protect a subset by accident of
which files load it, and the cause would remain in the mock.

### Why no timeout

`BATS_TEST_TIMEOUT` was in the first draft and is moved to the backlog, because round 1
measured three defects in it:

- On bats 1.10.0 (CI's `test` and `bash-coverage` jobs install it from apt), the watchdog
  sends `kill -ABRT $$` then `pkill -P`, direct children only; 1.13 kills the descendant tree.
  A fixture `run f` whose `f` blocks in a `while read` on an open FIFO never timed out on 1.10
  (killed by an outer `timeout`, rc 124) and timed out in 7 s on 1.13. The stalled test above
  is that `run` shape.
- The slowest test (`makefile_lint_scope.bats` "every stdout-capturing make -C …") took
  232.6 s under `taskset -c 0-3 make test JOBS=24` and 210.8 s alone on two pinned cores,
  against 66.45 s on `claude`'s 48 threads; under the coverage tracer it ran 1.8x slower. 300 s
  would fail `bash-coverage` on every PR.
- `tests/scripts/unit.bats` defines and exports a `kill()` function in two tests; bats stops
  its watchdog with a plain `kill`, so the watchdog survives and each run of that file waits out
  the full timeout (8 s measured under `BATS_TEST_TIMEOUT=8` with both tests passing in 3 ms).

## Testing

| Case | Expect |
| --- | --- |
| `make -n test` with GNU parallel, `make -n test HAVE_PARALLEL=`, `make -n test BATS_SERIAL_FILES=tests/setup_env/git_hooks.bats`, and `make -n test-unit` | each prints at least one line starting `bats`, and every such line ends with `< /dev/null` (the `BATS_SERIAL_FILES` form is the only one that prints the carve-out line) |
| `scripts/run-bash-coverage.sh` | its bats invocation line redirects stdin from `/dev/null` |
| `tests/mocks/gpg --homedir x --list-keys` with stdin an open FIFO | returns within 5 s and logs the call |
| `tests/mocks/gpg --dearmor` with stdin a file of known bytes | consumes the file (a following read of the same fd sees EOF) and logs the call |
| `tests/mocks/gpg --batch --yes --dearmor -o out` with stdin a file | consumes it (the `-o` argument is not an operand) |
| `tests/mocks/gpg --dearmor key.asc` with stdin an open FIFO | returns within 5 s (a file operand means stdin is not read) |
| `tests/mocks/gpg --dearmor -o -` with stdin a file | consumes it (`-` here is `-o`'s argument, and there is no operand) |

A mock that never drained would fail the two "consumes" cases; one that always drained would
fail the two FIFO cases; a recipe that dropped a redirect would fail the `make -n` case. The
serial reproduction is not a suite case (it nests a 393-test run); it is V2.

## Requirements

- **R1.** Every `bats` command line in the `Makefile` `test` and `test-unit` recipes redirects stdin from `/dev/null`.
- **R2.** The bats invocation in `scripts/run-bash-coverage.sh` redirects stdin from `/dev/null`.
- **R3.** `tests/mocks/gpg` reads stdin only when invoked with `--dearmor` or `--enarmor` and no file operand (the argument of `-o`, `--output`, `--homedir`, `--status-fd` or `--keyring` is not an operand), or with a `-` operand; otherwise it returns without reading fd0, and it logs every call as before.
- **R4.** Tests in the repo's bats suite cover the Testing table's cases.
- **V1.** `make test` exits 0 on the branch.
- **V2.** The serial direct reproduction (`bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats` with stdin an open FIFO, under `timeout 600`) completes on the branch with 393 tests; record the output in the PR body.
- **V3.** The P2 backlog row is narrowed to the timeout remainder, carrying the round-1 measurements (bats 1.10 direct-child watchdog, 232.6 s / 1.8x tracer, `kill()`-shadowing stall).
- **N1.** No test's assertion is weakened or removed; an exact-match expectation of a recipe line may change only to include the new redirect.
- **N2.** No mock other than `tests/mocks/gpg` changes behaviour.
- **N3.** No `BATS_TEST_TIMEOUT` is set by the `Makefile`, `scripts/` or `tests/helpers/`.


## Multi-Lens Review

Reviewed at commit: `3f2fb6b3` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Reported after the descope, against `3f2fb6b3`. (1) The gpg fix carries nearly all the value: with a real unix socket as stdin (`socketpair`, whole suite, plain `bats` in six groups) the patched mock gave 3373/3373 ok and the original hung only "run_setup_or_developer calls apt-get on Ubuntu"; the recipe redirects change an outcome only on serial paths, since GNU parallel already withholds stdin; the spec gave no reason for rejecting the row's own `exec 0</dev/null` in `common.bash` candidate (56 of 80 files load it). (2) The FIFO stand-in is not the socket: `argv_probe_stub_path` drains on `[[ -p /dev/stdin ]]`, so a whole-suite FIFO run gave 5 false hangs; V2's two files are unaffected. (3) The timeout cases were textual or tested upstream bats, not the Makefile wiring (moot after the descope). (4) R4's operand clause over-specifies: no production `--dearmor` call passes a file operand. Also measured: `BATS_TEST_TIMEOUT` timed out a direct child blocked on stdin on 1.10.0 and 1.13.0.
Assumption: 300 s clears the slowest test on CI's traced `bash-coverage` (moot after the descope; carried to the backlog row).
Disposition: Addressed (operator, 2026-10-22). Findings 1-2: rejected-alternative line, defence-in-depth statement and FIFO-vs-socket caveat added; 3 moot after the descope; 4 kept deliberately: the operand clause mirrors real gpg and round 2 verified it misclassifies no call.

### Ergonomics

Finding: (1) R3's timeout does not bound the motivating hang on bats 1.10.0 (CI `test`/`bash-coverage`, apt): its watchdog sends `kill -ABRT $$` then `pkill -P` (direct children only), so a `run f` whose `f` blocks reading an open FIFO never timed out (outer `timeout` rc 124); 1.13 timed it out in 7 s. The stalled test is `run`-wrapped; the sleep fixture passes on 1.10 regardless. (2) 300 s is past V2's 50% line: the slowest test took 210.8 s on two pinned cores (`taskset -c 0,1`), 3.2x the 66 s figure. (3) `make test-unit` (`Makefile:246`) gets neither redirect nor timeout. (4) `make -n` cannot show a Makefile `export`, and inlining the variable breaks seven anchored `'^bats --jobs N '` greps in `tests/makefile_parallel_target.bats`. (5) `BATS_TEST_TIMEOUT=0` means immediate timeout; off is the empty value, undocumented.
Assumption: 300 s stays above the slowest test on CI's 2-vCPU `test` job and the traced `bash-coverage` job; settle with a CI run under `--timing`.
Disposition: Addressed (operator, 2026-10-22: "Ship redirect + gpg fix, backlog timeout"). Timeout removed (new N3), its measurements carried to the backlog (V3); `test-unit` added to R1; the `make -n` timeout case is gone with it.

### Risk

Finding: (1) 300 s fails CI: `taskset -c 0-3 make test JOBS=24 --timing` put the slowest test at 232.6 s (next 92.8 s); under the coverage tracer it ran 1.8x slower (112 s vs 61 s alone), projecting about 420 s for `bash-coverage`. (2) `tests/scripts/unit.bats:192/206` define and export `kill()`; bats stops its watchdog with a plain `kill`, so the watchdog survives and the file waits out the full timeout (8 s measured at `BATS_TEST_TIMEOUT=8`, tests passing in 3 ms). (3) N3 (no timeout in test files) contradicted the timeout fixture row. (4) The fixture row could pass vacuously if the inner bats inherits `tests/mocks/sleep`. (5) The `make -n` timeout row is unobservable under `export`. (6) `test-unit` missed. (7) The serial reproduction as a suite case nests a 393-test run. Checked clean: `< /dev/null` is safe (`scripts/pre-push` already runs the suite at stdin EOF); R4's gpg rule matches every production call, no producer pipes into gpg, no SIGPIPE.
Assumption: the slowest test stays under 300 s on CI runners and the tracer; emulation says false for `bash-coverage`.
Disposition: Addressed (operator, 2026-10-22: "Ship redirect + gpg fix, backlog timeout"). Timeout and its fixture, export and N3-conflict findings removed with it; `kill()`-stall carried to the backlog row; `test-unit` added; reproduction moved from the suite to V2.

### Round 2 (scoped Risk)

Reviewed at commit: `13d4891d`, scoped to the descoped Design, Testing and Requirements; told the round-1 record is history.

Finding: No design defect. Two apparatus gaps, both measured on a prototype from `git archive 13d4891d` with the redirects added: (1) `tests/makefile_parallel_target.bats` "a carved-out file leaves the parallel pool and runs alone afterwards" uses `grep -qx` on the carve-out line and went `not ok 9`; its expected string must gain the redirect, not lose `-x`. (2) `BATS_SERIAL_FILES` is empty, so `make -n test` never prints the carve-out line: with its redirect removed, all three table cases still found zero missing lines; setting `BATS_SERIAL_FILES=tests/setup_env/git_hooks.bats` found it. The gpg rule misclassifies none of the repo's real call shapes provided `-o` is an argument-taking option; V2 with a prototype mock passed (393 ok, 0 not ok, 305 s on an open FIFO). Checked clean: other anchored greps, `tests/scripts/unit.bats:1132`, the pre-push EOF claim, the coverage runner's FIFO read by path.
Assumption: no uncertain assumption found (best candidate, that the gpg mock is the only stdin reader those two files reach, was settled true by the prototype V2 run).
Disposition: Addressed — carve-out case and "at least one `bats` line" added to the Testing table, the exact-match edit named in Design §1 and N1, the argument-taking option list put in §2 and R3, and an `-o -` row added (operator, 2026-10-22: "Addressed, approve spec").

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Spec alignment (2026-10-23)

- spec: docs/superpowers/specs/2026-10-22-bats-stdin-hang-design.md
- anchor: 5382c2f0836798c2b7ba3536d2c4bf4f1b50a8dd
- in scope: R1, R2, R3, R4
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |

### Reviewed

- none

### Verifications

- V1: make test on the branch: 1..3386, 3386 ok, 0 not ok, rc 0 (at e2bb52f0; fdb2be6c changes one test-helper line, mocks_gpg.bats 8/8)
- V2: mkfifo f; exec 3<>f; timeout 600 bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats <&3 at 9b6131de: rc 0, 1..393, 393 ok, 0 not ok, 299 s
- V3: post-merge on master: P2 backlog row narrowed to the timeout remainder
