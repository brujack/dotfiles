# Root-writes scan around the bats suite

- **Date:** 2026-11-27
- **Status:** Draft (revised after Step 8 round 1)

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

- `mark <marker>` creates `<marker>` (an empty file) so its mtime is the start of the window. It fails (exit 1) if the file cannot be created.
- `check <marker>` lists every path under the roots changed since the marker:

  ```bash
  find -H <root> -xdev \( -newer <marker> -o -cnewer <marker> \) -print
  ```

  `-H` follows a root given as a symlink (on macOS `/etc` is a symlink to `private/etc`; a plain `find /etc -xdev` lists the link itself, exits 0 and visits nothing: measured on the Studio, 1 entry against 295 with `-H`). `-newer` catches a created or rewritten file and a directory whose entries changed (so a deletion shows as its directory); `-cnewer` adds a chmod, chown or rename. The roots are `/etc /usr/local /usr/share/keyrings /opt`, replaced in tests by `ROOT_WRITES_ROOTS` (a space-separated list), honoured only under bats (`_bats_seam`, the repo's rule for seams). A root that does not exist is skipped and named.

Each existing root is walked separately, and the walk must visit at least one entry; a root that `find` walked with zero entries visited fails the check, so a scan that saw nothing cannot report `none`.

Privilege: when `sudo -n true` succeeds, `check` runs `sudo -n find`, which can enter root-only directories such as `/etc/sudoers.d`, exactly where a `sudo` write lands. Then any non-zero `find` status fails the check. Without passwordless sudo, `find` runs as the user; a status of 1 is accepted only when every line `find` wrote to stderr ends in `Permission denied`, and each such directory is printed as `not scanned: <dir>`. Any other non-zero status, or any other stderr line, fails the check.

Outcomes of `check` (exit 0 only for the first row):

| Situation | Output | Exit |
|---|---|---|
| no changed path, every existing root visited | `root-writes: none` | 0 |
| changed paths | `root-writes: the suite changed real host paths:` then one path per line | 1 |
| marker missing, a root visited with zero entries, or a `find` failure as defined above | the reason | 1 |

There is no local, warn-only mode. On `claude` the scan window collects writes the suite never made: 30 paths outside the suite changed in the 24 hours to 2026-11-27 (Edge's cron, the operator's `rex` install, `ld.so.cache`, and `/opt/github-runner-*` when the self-hosted runners pick up jobs), plus whatever concurrent sessions install; and 28 directories are unreadable to the user on every run. A warning that fires for those would be tuned out. The script stays runnable by hand.

### Wiring: CI only

The scan wraps the make step in CI, not the Makefile. A Makefile hook would also run inside `tests/makefile_shard_list.bats`, which invokes a real `make test-bats` about seven times during the suite, each inheriting CI's environment.

- In `.github/workflows/ci.yml`, the `test-shard` step that runs `make bash-coverage` and the `test-macos-shard` step that runs `make test` / `make test-bats` each run `bash scripts/root-writes.sh mark "${RUNNER_TEMP}/root-writes.marker"` before make and `bash scripts/root-writes.sh check "${RUNNER_TEMP}/root-writes.marker"` after it, also when make failed. The step exits with make's status when make failed, otherwise with `check`'s.

### Gate rollout

Before the check is allowed to fail a job, one scratch-branch run (never merged) wraps the real suite on `ubuntu-latest` and `macos-latest` with `mark` and an unconditional `sudo -n find` listing, and records: the list (it must be empty, or each entry explained and its subtree pruned in the spec by amendment), the scan's run time per leg, and whether `sudo -n true` succeeds on `macos-latest`. The same scratch branch carries a deliberate escape (a test writing a file under `/usr/local/bin` through `sudo`) on each runner and shows the check fails on it.

### Tests

`tests/scripts/root_writes.bats`, with fixture roots under `BATS_TEST_TMPDIR` via `ROOT_WRITES_ROOTS`:

- untouched roots report `none`, exit 0;
- a file created, a file rewritten, a file chmodded and a file deleted after the marker are each reported, exit 1 (the deletion by its directory);
- a root given as a symlink to a directory is walked, and a file created through it is reported;
- a root walked with zero entries visited fails;
- without sudo, an unreadable subdirectory is named under `not scanned:` and a hit beside it is still reported; a `find` stderr line other than `Permission denied` fails;
- a missing marker exits 1;
- a missing root is skipped and named;
- `ROOT_WRITES_ROOTS` is ignored when `BATS_TEST_TMPDIR` is empty.

Each listed behaviour gets a mutation shown to fail its test.

### Backlog

- "The real-root-path guard has blind spots" and "The refusing-sudo PATH guard sees single-line assignments only" become watch items: each states the 2026-11-27 measurement (0 hidden hits) and that the CI root-writes scan now catches any write those blind spots would hide.
- A new row records the separate class the scan does not cover: builtin read probes such as `[[ -f /etc/... ]]` make a test's outcome depend on host state (a pass on `claude` that fails on a clean runner), with no write involved.

## Alternatives considered

- **Close each blind spot in the ledger guard** (scan every file under the test temp dir, a per-file suite ledger, a multi-line `PATH` parser): three mechanisms against zero measured hits, and still blind to a write that passes through no ledger at all.
- **A fixed list of directories to hash** (the manual md5 check): misses any directory not on the list, and the list has to track every new install target by hand.
- **Record the measurement and build nothing:** leaves the one instrument that has caught a real escape manual.
- **A Makefile hook with a local warn mode** (the first draft): runs the real scan inside the suite's own nested `make` tests, and warns on every local run for writes the suite never made.

## Requirements

- **R1.** `scripts/root-writes.sh mark <marker>` creates the marker file and exits 1 if it cannot.
- **R2.** `scripts/root-writes.sh check <marker>` walks each existing root with `find -H <root> -xdev \( -newer <marker> -o -cnewer <marker> \)` and reports every path created, modified, chmodded or chowned after the marker, and the directory of every entry deleted after it.
- **R3.** The roots are `/etc /usr/local /usr/share/keyrings /opt`; `ROOT_WRITES_ROOTS` replaces them only when `BATS_TEST_TMPDIR` is non-empty; a root that does not exist is skipped and named in the output.
- **R4.** A reported path makes `check` print `root-writes: the suite changed real host paths:` followed by one path per line and exit 1.
- **R5.** With no changed path and every existing root visited, `check` prints `root-writes: none` and exits 0.
- **R6.** A missing marker, or an existing root walked with zero entries visited, makes `check` exit 1.
- **R7.** When `sudo -n true` succeeds, `check` runs `find` through `sudo -n`, and any non-zero `find` status makes it exit 1.
- **R8.** Without passwordless sudo, `find` runs as the invoking user; a `find` status of 1 is accepted only when every stderr line ends in `Permission denied`, each such directory is printed as `not scanned: <dir>`, and paths found elsewhere are still reported; any other non-zero status or stderr line makes `check` exit 1.
- **R9.** In `.github/workflows/ci.yml`, the `test-shard` step that runs `make bash-coverage` and the `test-macos-shard` step that runs make each run `root-writes.sh mark` before make and `root-writes.sh check` after it, also when make failed, and exit with make's status when make failed and with `check`'s otherwise.
- **R10.** `tests/scripts/root_writes.bats` covers each of R1-R8 against fixture roots, including a root given as a symlink, and `tests/bats-files.txt` lists it.
- **R11.** The two guard Backlog rows are rewritten as watch items carrying the 2026-11-27 measurement, and a new Backlog row records builtin read probes as host-state dependence not covered by the scan.
- **V1.** Before R9 merges, a scratch-branch run on `ubuntu-latest` and `macos-latest` wraps the real suite with `mark` and an unconditional `sudo -n find` listing and records an empty list (or each entry explained and its subtree pruned by amendment), the scan's run time per leg, and whether `sudo -n true` succeeds on `macos-latest`.
- **V2.** On the same scratch branch, a deliberate escape (a test writing a file under `/usr/local/bin` through `sudo`) turns the wrapped step red on both `ubuntu-latest` and `macos-latest`, with that path listed.
- **V3.** On the first green CI run after merge, every `test-shard` and `test-macos-shard` log shows `root-writes: none`.
- **N1.** No change to `assert_no_real_root_paths`, `_unguarded_path_resets` or any ledger.
- **N2.** No Makefile target runs the scan.
- **N3.** No fixed list of files or directories to hash.
- **N4.** The scan never writes, moves or deletes anything under its roots.

## Multi-Lens Review

Reviewed at commit: `874aa250` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: On macOS `/etc` is a symlink; `find /etc -xdev` without `-H` visits only the link, exits 0, and the scan reports `none`. V1 expected `none`, so a blind scan passed it; only the Linux V2 tested the measurement. Otherwise worth building: it changes a decision (a red shard blocks auto-merge) and its output lives in the job log.
Assumption: No process on a GitHub runner writes under the roots while the suite runs; settle with a warn-only scratch run before wiring the gate.
Disposition: Addressed (operator, 2026-11-27) — `find -H`, a zero-entries-visited failure, a symlinked-root fixture, V2 on both runners, and a pre-merge scratch run (V1).

### Ergonomics

Finding: The local warn mode would be constant noise on `claude`: 28 directories unreadable to the user on every run (18 of them `/opt/github-runner-*`), and 30 non-suite changes under the roots in 24 hours (Edge cron, `rex`, runner pickups), plus concurrent sessions' writes. Scan time 1.6 s. Also confirmed the macOS `/etc` blind spot on the Studio (1 entry without `-H`, 295 with).
Assumption: Same as Goal-Fit; proposed a scratch `workflow_dispatch` run on both runners.
Disposition: Addressed (operator, 2026-11-27) — the local mode is dropped; the scan runs only in CI and stays runnable by hand.

### Risk

Finding: F1 the macOS `/etc` symlink (as above). F2 a Makefile hook runs the real scan inside `tests/makefile_shard_list.bats`'s nested `make test-bats`, inheriting CI's fail mode. F3 the recipe status plumbing across `test-bats`'s two bats lines was unspecified. F4 `find` exit 1 also means a missing path, a vanished entry or a lost sudo credential. F5 CI scan cost unmeasured.
Assumption: Same as Goal-Fit; proposed a scratch-branch run that marks, runs the suite and lists with `sudo -n find`.
Disposition: Addressed (operator, 2026-11-27) — wiring moved from the Makefile to the CI steps (F2, F3); with sudo any non-zero status fails and without it only `Permission denied` stderr is accepted (F4); scan time recorded by the pre-merge run (F5).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
