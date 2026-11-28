# Root-writes scan around the bats suite

- **Date:** 2026-11-27
- **Status:** Draft

## Problem

The bats suite must never write to the real host. Two guards enforce that today:

- `assert_no_real_root_paths` (`tests/helpers/common.bash`) reads recorded mock calls in three ledgers (`MOCK_CALLS_FILE`, the per-test `mock_calls`, the suite ledger) and fails a test whose calls name `/etc`, `/usr/local`, `/usr/share/keyrings` or `/opt`. It runs from the teardown of every file that calls `load_mocks` (dotfiles#497).
- `_unguarded_path_resets` (`tests/suite_isolation.bats`) flags a test that rebuilds `PATH` without `refusing_sudo_path`.

Both read a proxy for the write, not the write. The Backlog lists what the proxy cannot see: private ledgers under other names (`TFENV_CALLS_FILE`, stub logs under `STUB_DIR`), a ledger repointed inside a `zsh -c` string, the 64 of 123 bats files that never call `load_mocks`, a `PATH` assembled across lines, and misattribution through the shared suite ledger under `--jobs`.

The one instrument that has no such gaps is the one the operator's sessions have run by hand on every PR: a listing of the real root directories before and after `make test`. It caught a real escape that no ledger guard reported (the docker keyring and list written into `/etc/apt` at 12:24 on 2026-11-26, before dotfiles#497). It runs only when someone remembers to run it.

### Measured premise (2026-11-27, `claude`)

The hazard behind the Backlog rows is currently absent, so this is a regression guard, not a fix for a live leak:

- `tfenv.bats`, `repo_sessions.bats` and `zshrc.d/unit.bats` were run with `--no-tempdir-cleanup` and every file under their temp dirs grepped for the four root prefixes: 0 hits outside the preprocessed test source.
- The 64 bats files that do not call `load_mocks` were grepped for `sudo`, `ln -s`, `install`, `tee`, `cp` or `mv` naming a root prefix: 0 files.
- Tracked `.bats` files were grepped for a `PATH=` assignment continued onto another line: 0.

Population: one machine (`claude`), current master; the CI runners were not measured. The claim drawn from it is only that no blind spot is hiding a write today.

## Design

### `scripts/root-writes.sh`

Two subcommands:

- `mark <marker>` creates `<marker>` (an empty file) so its mtime is the suite's start time. It fails (exit 1) if the file cannot be created.
- `check <marker>` lists every path under the roots changed since the marker:

  ```bash
  find <roots> -xdev \( -newer <marker> -o -cnewer <marker> \) -print
  ```

  `-newer` catches a created or rewritten file and a directory whose entries changed (so a deletion shows as its directory); `-cnewer` adds a chmod, chown or rename. The roots are `/etc /usr/local /usr/share/keyrings /opt`, replaced in tests by `ROOT_WRITES_ROOTS` (a space-separated list), honoured only under bats (`_bats_seam`, the repo's rule for seams). Roots that do not exist are skipped, and the output says so.

Privilege: a non-root `find` cannot enter root-only directories such as `/etc/sudoers.d`, which are exactly where a `sudo` write lands. When `ROOT_WRITES_FAIL=1` (the CI mode below) and `sudo -n true` succeeds, `check` runs `sudo -n find`. Otherwise it runs as the user, and each directory `find` could not read is reported by name ("not scanned: <dir>") rather than silently dropped.

Outcomes of `check`:

| Situation                                                                                                  | `ROOT_WRITES_FAIL=1` (CI)                                                               | unset (local)                                             |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| no changed path                                                                                            | exit 0, prints `root-writes: none`                                                      | same                                                      |
| changed paths                                                                                              | prints `root-writes: the suite changed real host paths:` then one path per line; exit 1 | prints the same list under `root-writes: WARNING`; exit 0 |
| marker missing, or `find` exits with a status other than 0 or 1 (1 is permission denied on a subdirectory) | prints the reason; exit 1                                                               | prints the reason as a warning; exit 0                    |

Locally the scan warns rather than fails because other writers share those directories with the suite: Microsoft Edge's daily cron rewrites its apt source and keyring, and the operator installs packages (2026-11-27: `rex` added `/etc/apt/sources.list.d/rex.sources`). A CI runner has no such writers during the suite.

### Wiring

- `Makefile`: `test-bats` and `bash-coverage` run `scripts/root-writes.sh mark` before invoking bats and `scripts/root-writes.sh check` after it, whether bats passed or failed. The recipe exits with bats's status if bats failed, otherwise with `check`'s. The marker lives under `$(TMPDIR)` (default `/tmp`), named per make process.
- `.github/workflows/ci.yml`: the `test-shard` and `test-macos-shard` jobs set `ROOT_WRITES_FAIL: 1` in the environment of the step that runs make.

### Tests

`tests/scripts/root_writes.bats`, with fixture roots under `BATS_TEST_TMPDIR` via `ROOT_WRITES_ROOTS`:

- untouched roots report `none`, exit 0;
- a file created, a file rewritten, a file chmodded and a file deleted after the marker are each reported (the deletion by its directory);
- fail mode exits 1 on a hit, warn mode exits 0 with `WARNING`;
- an unreadable subdirectory is named under `not scanned:` and a hit beside it is still reported;
- a missing marker exits 1 in fail mode and 0 with a warning otherwise;
- a missing root is skipped and named;
- `ROOT_WRITES_ROOTS` is ignored when `BATS_TEST_TMPDIR` is empty.

Each listed behaviour gets a mutation shown to fail its test.

### Backlog

- "The real-root-path guard has blind spots" and "The refusing-sudo PATH guard sees single-line assignments only" become watch items: each states the 2026-11-27 measurement (0 hidden hits) and that the root-writes scan now catches any write those blind spots would hide.
- A new row records the separate class the scan does not cover: builtin read probes such as `[[ -f /etc/... ]]` make a test's outcome depend on host state (a pass on `claude` that fails on a clean runner), with no write involved.

## Alternatives considered

- **Close each blind spot in the ledger guard** (scan every file under the test temp dir, a per-file suite ledger, a multi-line `PATH` parser): three mechanisms against zero measured hits, and still blind to a write that passes through no ledger at all.
- **A fixed list of directories to hash** (the manual md5 check): misses any directory not on the list, and the list has to track every new install target by hand.
- **Record the measurement and build nothing:** leaves the one instrument that has caught a real escape manual.

## Requirements

- **R1.** `scripts/root-writes.sh mark <marker>` creates the marker file and exits 1 if it cannot.
- **R2.** `scripts/root-writes.sh check <marker>` reports every path under its roots created, modified, chmodded or chowned after the marker, and the directory of every entry deleted after it, using `find <roots> -xdev \( -newer <marker> -o -cnewer <marker> \)`.
- **R3.** The roots are `/etc /usr/local /usr/share/keyrings /opt`; `ROOT_WRITES_ROOTS` replaces them only when `BATS_TEST_TMPDIR` is non-empty; a root that does not exist is skipped and named in the output.
- **R4.** With `ROOT_WRITES_FAIL=1`, a reported path makes `check` print `root-writes: the suite changed real host paths:` followed by one path per line and exit 1.
- **R5.** Without `ROOT_WRITES_FAIL=1`, `check` prints the same paths under a line containing `root-writes: WARNING` and exits 0.
- **R6.** With no changed path, `check` prints `root-writes: none` and exits 0.
- **R7.** A missing marker, or a `find` exit status other than 0 or 1, makes `check` exit 1 with `ROOT_WRITES_FAIL=1` and exit 0 with a warning otherwise.
- **R8.** Every directory `find` could not read is printed as `not scanned: <dir>`, and paths found elsewhere are still reported.
- **R9.** With `ROOT_WRITES_FAIL=1` and `sudo -n true` succeeding, `check` runs `find` through `sudo -n`; otherwise it runs `find` as the invoking user.
- **R10.** The `test-bats` and `bash-coverage` Makefile recipes run `root-writes.sh mark` before bats and `root-writes.sh check` after it, run `check` when bats fails, and exit with bats's status when bats failed and with `check`'s otherwise.
- **R11.** The `test-shard` and `test-macos-shard` jobs in `.github/workflows/ci.yml` set `ROOT_WRITES_FAIL: 1` for the step that runs make.
- **R12.** `tests/scripts/root_writes.bats` covers each of R1-R9 against fixture roots, and `tests/bats-files.txt` lists it.
- **R13.** The two guard Backlog rows are rewritten as watch items carrying the 2026-11-27 measurement, and a new Backlog row records builtin read probes as host-state dependence not covered by the scan.
- **V1.** On a green CI run after merge, every `test-shard` and `test-macos-shard` log shows `root-writes: none`, and the scan adds no more than 60 s to any shard; if it adds more, the heavy subtree is pruned in a follow-up.
- **V2.** A deliberate escape (a test that writes a file under `/usr/local/bin` through `sudo` on a scratch branch, never merged) turns a `test-shard` leg red with that path listed.
- **V3.** The macOS runner's `sudo -n true` result is recorded from the first CI run; if it fails, the log's `not scanned:` lines are the record of what the macOS scan cannot see.
- **N1.** No change to `assert_no_real_root_paths`, `_unguarded_path_resets` or any ledger.
- **N2.** The local (non-CI) run never fails because of a root write; it only warns.
- **N3.** No fixed list of files or directories to hash.
- **N4.** The scan never writes, moves or deletes anything under its roots.
