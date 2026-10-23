# bats stdin hang: redirect the recipes, bound each test, fix the gpg mock

- **Date:** 2026-10-22
- **Backlog row:** `docs/superpowers/README.md` P2, "A bats run that inherits a live stdin socket hangs at 0% CPU indefinitely, and nothing detects or bounds it"
- **Operator decisions (2026-10-22):** redirect stdin on the bats recipe lines and add a per-test timeout; also fix the mock that actually reads stdin.

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

- `Makefile` serial recipe lines: `bats $(BATS_FLAGS) $(BATS_PARALLEL_FILES)` (no GNU parallel)
  and `bats $(BATS_FLAGS) $(BATS_SERIAL_FILES)`. The parallel line
  `bats --jobs $(JOBS) …` is protected by parallel today but has no redirect of its own.
- `scripts/run-bash-coverage.sh:807`: `"${_bats_bin}" "${_bats_args[@]}" > "${bats_log}" 2>&1`,
  serial whenever `COVERAGE_BATS_JOBS` is unset or parallel is absent.
- Any direct `bats <file>` an operator or agent runs.

Prior art: `tests/setup_env/ledger_integration.bats` carries `exec < /dev/null` for the same
class (a `cat` in the `ledger` mock); the P3 row "A mock that `cat`s stdin blocks forever on a
non-EOF fd0" tracks the other stdin-reading mocks. No spec or ADR has proposed or rejected a
recipe redirect or a test timeout (grep of `docs/adr` and `docs/superpowers/specs` for
`stdin`, `BATS_TEST_TIMEOUT`, `hang`).

## Design

### 1. Recipes never pass an inherited stdin to bats

Append `< /dev/null` to each of the three `bats` recipe lines in `Makefile` (the
`--jobs` line, the serial `BATS_PARALLEL_FILES` line, the `BATS_SERIAL_FILES` line) and to the
bats invocation at `scripts/run-bash-coverage.sh:807`. A test that needs stdin must supply its
own (a heredoc, a pipe, a file); none should depend on the caller's.

### 2. Every test is bounded

Export `BATS_TEST_TIMEOUT` from the `Makefile` for the `test` and `bash-coverage` targets, from
one variable `BATS_TEST_TIMEOUT ?= 300` so a caller can override it per call. bats then fails
an over-running test with `not ok N <name> # timeout after 300s` and continues with the next,
so a hang becomes a named failure. Probed 2026-10-22 on bats 1.13.0: a `sleep 10` test under
`BATS_TEST_TIMEOUT=2` reported `# timeout after 2s` and the following test still ran.

The value: measured 2026-10-22 with `make test BATS_FLAGS="--print-output-on-failure --timing"`
on `claude` (3370 timed tests, `bats --jobs 24`, no other session's suite running, untraced), the slowest test took 66.45 s
(`makefile_lint_scope.bats` "every stdout-capturing make -C invocation in-domain is guarded or
measuring, both sets nonempty"), the next 15.26 s, and every other test under 5.1 s. 300 s is
4.5x the slowest, leaving room for tracing overhead under `bash-coverage` and for contention
from concurrent sessions. The same measurement is not available for CI's runners or the
traced coverage run; V2 records them.

### 3. The gpg mock reads stdin only when gpg would

`tests/mocks/gpg` keeps logging every call, and drains stdin only when the invocation is one
that reads it: `--dearmor` or `--enarmor` with no file operand, or an operand of `-`. Every
other call returns without touching fd0. The production call sites that feed gpg stdin are
`lib/linux_ubuntu.sh` `--dearmor < "${_key}"` and `--batch --yes --dearmor -o … < key`; both
stay drained. `tests/mocks/gpg-dearmor` is only reached through `_APT_KEY_GPG_BIN`, whose
caller always redirects stdin from a file, and is left alone. The `ledger` mock and the other
stdin-reading mocks stay on their P3 row.

## Testing

| Case                                                                             | Expect                                                                                                   |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `make -n test` (parallel and `HAVE_PARALLEL=` forms) and `make -n bash-coverage` | every `bats` command line carries `< /dev/null`; the `bash-coverage` recipe's runner line carries it too |
| `scripts/run-bash-coverage.sh` source                                            | the bats exec line redirects stdin from `/dev/null`                                                      |
| `make -n test`                                                                   | `BATS_TEST_TIMEOUT=300` reaches the bats environment; `make -n test BATS_TEST_TIMEOUT=7` shows 7         |
| a fixture bats file whose test sleeps longer than a small `BATS_TEST_TIMEOUT`    | the run reports `timeout after`, names the test, and the next test still runs                            |
| `tests/mocks/gpg --homedir x --list-keys` with stdin an open FIFO                | returns within 5 s, logs the call                                                                        |
| `tests/mocks/gpg --dearmor` with stdin a file                                    | drains it (the file's bytes are consumed) and logs the call                                              |
| the reproduction above (serial direct bats of the two files, stdin an open FIFO) | completes, 393 tests, no `timeout`                                                                       |

The gpg cases and the reproduction pin the cause; the `make -n` cases pin the containment. A
mock that drained nothing at all would fail the `--dearmor` case; a recipe that dropped the
redirect would fail the `make -n` cases.

## Requirements

- **R1.** Each `bats` command line in the `Makefile` `test` recipe (the `--jobs` line and both serial lines) redirects stdin from `/dev/null`.
- **R2.** The bats invocation in `scripts/run-bash-coverage.sh` redirects stdin from `/dev/null`.
- **R3.** `BATS_TEST_TIMEOUT` reaches every bats run started by `make test` and `make bash-coverage`, with default 300 set once in the `Makefile` and overridable per call (`make test BATS_TEST_TIMEOUT=<n>`).
- **R4.** `tests/mocks/gpg` reads stdin only when invoked with `--dearmor` or `--enarmor` and no file operand, or with a `-` operand; otherwise it returns without reading fd0, and it logs every call as before.
- **R5.** Tests in the repo's bats suite cover the Testing table's cases.
- **V1.** `make test` exits 0 on the branch.
- **V2.** CI's `test`, `test-macos` and `bash-coverage` jobs pass with the timeout in force; record each job's bats version and whether any test came within 50% of 300 s, from the job logs, in the PR body.
- **V3.** The serial direct reproduction (`bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats` with stdin an open FIFO) completes on the branch; record the output in the PR body.
- **N1.** No test's assertion is weakened or removed.
- **N2.** No mock other than `tests/mocks/gpg` changes behaviour.
- **N3.** `BATS_TEST_TIMEOUT` is not set inside test files or `tests/helpers/`.
- **N4.** The timeout is not used to hide a known slow test: no test is skipped or split to fit under it.
