# Root-writes scan around the bats suite

- **Date:** 2026-11-27
- **Status:** Approved
- **Approved:** 2026-11-27

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
  find <resolved root> -xdev \( -newer <marker> -o -cnewer <marker> \) -print
  ```

  On macOS `/etc` is a symlink to `private/etc`, and a plain `find /etc -xdev` lists the link itself, exits 0 and visits nothing (measured on the Studio: 1 entry, against 295 for the resolved directory), so every root is resolved before it is walked (below). `-newer` catches a created or rewritten file and a directory whose entries changed (so a deletion shows as its directory); `-cnewer` adds a chmod, chown or rename. The roots are `/etc /usr/local /usr/share/keyrings /opt`, replaced in tests by `ROOT_WRITES_ROOTS` (a space-separated list), honoured only under bats (`_bats_seam`, the repo's rule for seams). A root that does not exist is skipped and named.

#### Prune list

The script carries one prune list per OS (`ROOT_WRITES_PRUNE_LINUX`, `ROOT_WRITES_PRUNE_DARWIN`), empty at first, applied to the walk as `-path <p> -prune -o`. A prune enters the list only by spec amendment, and each entry's comment cites the V1 or V2 run that produced it. No prune may equal or contain a directory that `lib/` installs into: today `/etc/apt`, `/etc/docker`, `/etc/sysctl.d`, `/usr/share/keyrings`, `/usr/local/bin`, `/opt/homebrew` (and on macOS `/private/etc/apt`, `/private/etc/docker`, `/private/etc/sysctl.d`). A hit that could only be cleared by such a prune means the gate does not ship.

#### Walk

Each existing root is first resolved to the directory it names (`cd <root>/. && pwd -P`, so `/etc` on macOS becomes `/private/etc`) and then walked separately. Resolution is the one mechanism against a symlinked root; `find` gets no `-H`.

The walk counts the entries it visits below the root itself (`find` always prints its starting point, so a walk that never descended visits exactly one entry, the same as a genuinely empty directory). Whether a root is empty is decided independently of the walk: by listing `<root>/.` (`ls -A`), run with the same privilege as `find`. A root whose listing shows at least one entry but whose walk visits none fails the check; a root whose listing is refused fails the check; a root whose listing succeeds and is empty is reported as `empty: <root>` and is not a failure. The `none` line carries every root's visited count, for example `root-writes: none (/etc 1840, /usr/local 9120, /usr/share/keyrings 12, /opt 30544)`, so each green log shows the scan saw something.

Privilege: when `sudo -n true` succeeds, `check` runs `sudo -n find`, which can enter root-only directories such as `/etc/sudoers.d`, exactly where a `sudo` write lands. Then any non-zero `find` status fails the check. Without passwordless sudo, `find` runs as the user; a status of 1 is accepted only when every line `find` wrote to stderr ends in `Permission denied`, and each such directory is printed as `not scanned: <dir>`. Any other non-zero status, or any other stderr line, fails the check.

Outcomes of `check` (exit 0 only for the first row):

| Situation | Output | Exit |
|---|---|---|
| no changed path, every existing root walked | `root-writes: none (<root> <count>, ...)` | 0 |
| changed paths | `root-writes: the suite changed real host paths:` then one path per line | 1 |
| marker missing, a non-empty root whose walk visited nothing below it, a root whose listing is refused, or a `find` failure as defined above | the reason | 1 |

There is no local, warn-only mode. On `claude` the scan window collects writes the suite never made: 30 paths outside the suite changed in the 24 hours to 2026-11-27 (Edge's cron, the operator's `rex` install, `ld.so.cache`, and `/opt/github-runner-*` when the self-hosted runners pick up jobs), plus whatever concurrent sessions install; and 28 directories are unreadable to the user on every run. A warning that fires for those would be tuned out. The script stays runnable by hand.

### Wiring: CI only

The scan wraps the make step in CI, not the Makefile. A Makefile hook would also run inside `tests/makefile_shard_list.bats`, which invokes a real `make test-bats` about seven times during the suite, each inheriting CI's environment.

- On Linux, shard 1 runs `make test-prereqs` as its own step before `make bash-coverage`, while macOS shard 1's `make test` includes the prerequisites. So that both OSes scan the same work, `test-shard` gets a separate `mark` step placed before the prerequisites step, and its `make bash-coverage` step runs `check`; the `test-macos-shard` step that runs `make test` / `make test-bats` runs both `mark` and `check`.
- Concretely: in `.github/workflows/ci.yml`, `test-shard` runs `bash scripts/root-writes.sh mark "${RUNNER_TEMP}/root-writes.marker"` in its own step before the prerequisites step, and the `test-macos-shard` step runs it before make and `bash scripts/root-writes.sh check "${RUNNER_TEMP}/root-writes.marker"` after it, also when make failed. The step fails if any check inside it fails, and keeps every check it already runs: the `test-macos-shard` step already runs `scripts/ci-suite-report.sh` (executed tests equal declared) and exits with that report's status when make passes, so there the step exits with make's status if make failed, else the report's if the report failed, else `check`'s. The `test-shard` suite report is a separate step and is unchanged. The Linux step is a bare `run: make bash-coverage` today, so it gains `set +e` to reach `check` after a failing make.
- The check runs from the PR branch's own copy of the script and workflow, so it catches accidental escapes; it is not tamper-proof against a change that edits the scan itself.

### Reproducing a red shard

A red shard names paths, not tests (a shard runs about 40 files under `--jobs`). The script stays runnable by hand, and the clean place to run it is the container CLAUDE.md already names for CI reproduction: in `ubuntu:26.04` with the repo mounted, `bash scripts/root-writes.sh mark /tmp/m`, then `BATS_FILES_FROM=<shard list> make test-bats`, then `bash scripts/root-writes.sh check /tmp/m`, bisecting the list.

### Gate rollout

Before the check is allowed to fail a job, a scratch branch (never merged) runs, from a push-triggered workflow on that branch:

- **Null windows:** 10 runs per OS (`ubuntu-latest`, `macos-latest`) of `mark`, a sleep as long as the longest shard's suite step, then `check`, with no suite. Any hit is a background writer: its subtree is pruned by spec amendment, or the gate does not ship.
- **Suite windows:** 2 runs per OS of the real wrapped steps, recording each `check` output (visited counts included), the scan's run time per leg, and whether `sudo -n true` succeeds on `macos-latest`. Any hit in a suite window is either an escape, fixed before merge, or a harmless write, pruned by spec amendment before merge; either way the gate does not ship with it unexplained.
- **Stop rule:** a window that can only be cleared by a prune equal to or containing a directory `lib/` installs into (the list under "Prune list") means the gate does not ship: those are where real escapes land, and the 2026-11-26 escape landed in `/etc/apt`.
- **`find` status:** every window records `check`'s output, including `find`'s exit status and stderr under `sudo -n`. A non-zero status or a stderr line (for example `Operation not permitted` from SIP/TCC on macOS) in a null window means the gate does not ship until the cause is resolved by amendment.
- **Deliberate escape:** a bats file that does not call `load_mocks` and skips unless `GITHUB_ACTIONS` is set (so a pre-push `make test` on a developer box never runs it) calls the absolute `/usr/bin/sudo` to create a file under `/usr/local/bin`. The wrapped step must go red on both OSes with `root-writes: the suite changed real host paths:` and that path in its log. Going through `tests/mocks/sudo` would not do: the existing ledger guard already fails that test, so a red step would prove nothing about the scan.

### Tests

`tests/scripts/root_writes.bats`, with fixture roots under `BATS_TEST_TMPDIR` via `ROOT_WRITES_ROOTS`:

- untouched roots report `none`, exit 0;
- a file created, a file rewritten, a file chmodded and a file deleted after the marker are each reported, exit 1 (the deletion by its directory);
- a root given as a symlink to a directory is resolved and walked, and a file created through it is reported; the mutation that removes the resolution makes the walk visit nothing below the link while the listing shows entries, so the check fails;
- an empty root directory is reported as `empty:` and passes; a root whose listing is refused fails;
- the `none` line carries each root's visited count;
- without sudo, an unreadable subdirectory is named under `not scanned:` and a hit beside it is still reported; a `find` stderr line other than `Permission denied` fails;
- a missing marker exits 1;
- a missing root is skipped and named;
- `ROOT_WRITES_ROOTS` is ignored when `BATS_TEST_TMPDIR` is empty.

Each listed behaviour gets a mutation shown to fail its test. Paths in expectations are resolved with `pwd -P` too, since on macOS `BATS_TEST_TMPDIR` under `/var/folders` resolves to `/private/var/folders`.

The prune list gets its own tests: a write beside a pruned subtree is reported and a write inside it is not; a prune equal to or containing a `lib/` install directory is refused by a test that reads the list.

The CI wiring gets a test in the repo's per-job style (parse `ci.yml` per job, never grep the whole file): in `test-shard` a `mark` step precedes the prerequisites step and the `make bash-coverage` step runs `check` after make; in `test-macos-shard` the make step runs `mark` before make and `check` after it; neither step has an `exit` between make and `check`; and each step's final exit can come from `check`.

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
- **R2.** `scripts/root-writes.sh check <marker>` resolves each existing root with `cd <root>/. && pwd -P`, walks the resolved directory with `find <resolved> -xdev` applying each entry of the OS's prune list as `-path <p> -prune -o` and then `\( -newer <marker> -o -cnewer <marker> \)` (no `-H`), and reports every path created, modified, chmodded or chowned after the marker, and the directory of every entry deleted after it.
- **R3.** The roots are `/etc /usr/local /usr/share/keyrings /opt`; `ROOT_WRITES_ROOTS` replaces them only when `BATS_TEST_TMPDIR` is non-empty; a root that does not exist is skipped and named in the output.
- **R4.** A reported path makes `check` print `root-writes: the suite changed real host paths:` followed by one path per line, and exit 1.
- **R5.** With no changed path, `check` prints `root-writes: none (` followed by each walked root and the number of entries visited below it, comma-separated, then `)`, and exits 0.
- **R6.** A missing marker makes `check` exit 1. Emptiness is decided by `ls -A <root>/.` run with the same privilege as `find`: a root whose listing shows an entry but whose walk visits no entry below the root makes `check` exit 1; a root whose listing is refused makes `check` exit 1; a root whose listing succeeds and is empty is printed as `empty: <root>` and does not fail.
- **R7.** When `sudo -n true` succeeds, `check` runs `find` through `sudo -n`, and any non-zero `find` status makes it exit 1.
- **R8.** Without passwordless sudo, `find` runs as the invoking user; a `find` status of 1 is accepted only when every stderr line ends in `Permission denied`, each such directory is printed as `not scanned: <dir>`, and paths found elsewhere are still reported; any other non-zero status or stderr line makes `check` exit 1.
- **R9.** In `.github/workflows/ci.yml`, `test-shard` runs `root-writes.sh mark` in its own step before the shard-1 prerequisites step and its `make bash-coverage` step runs `root-writes.sh check` after make, also when make failed; the `test-macos-shard` step that runs make runs `root-writes.sh mark` before make and `root-writes.sh check` after it, also when make failed; the `test-shard` step exits with make's status if make failed, else `check`'s; the `test-macos-shard` step exits with make's status if make failed, else `ci-suite-report.sh`'s if it failed, else `check`'s.
- **R10.** `tests/scripts/root_writes.bats` covers each of R1-R8 and R12 against fixture roots, including a root given as a symlink and an empty root, with expected paths resolved by `pwd -P`; a per-job test of `ci.yml` covers R9 (mark before the work, `check` after make with no `exit` between, the step's final exit able to come from `check`); `tests/bats-files.txt` lists each new file.
- **R11.** The two guard Backlog rows are rewritten as watch items carrying the 2026-11-27 measurement, and a new Backlog row records builtin read probes as host-state dependence not covered by the scan.
- **R12.** The script carries a prune list per OS, empty at merge unless V1 or V2 added an entry by amendment; each entry is applied as `-path <p> -prune`; no entry equals or contains `/etc/apt`, `/etc/docker`, `/etc/sysctl.d`, `/usr/share/keyrings`, `/usr/local/bin`, `/opt/homebrew`, `/private/etc/apt`, `/private/etc/docker` or `/private/etc/sysctl.d`, and a test reading the list enforces it.
- **V1.** Before R9 merges, a scratch branch runs 10 null windows per OS on `ubuntu-latest` and `macos-latest` (`mark`, a sleep as long as the longest shard's suite step, `check`, no suite), recording `find`'s exit status and stderr; every run reports `none` with a zero status and empty stderr, or each hit is pruned by spec amendment under R12 before merge; a hit only R12-forbidden pruning could clear, or an unresolved non-zero status, means the gate does not ship.
- **V2.** On the same branch, 2 runs per OS of the wrapped suite steps record each `check` output with its visited counts, the scan's run time per leg, and whether `sudo -n true` succeeds on `macos-latest`; every hit is fixed as an escape or pruned by spec amendment before merge, and the gate does not ship if clearing a window needs `/etc`, `/private/etc`, `/usr/local/bin` or `/opt/homebrew` pruned wholesale.
- **V3.** On the same branch, a bats file that does not call `load_mocks` and skips unless `GITHUB_ACTIONS` is set uses `/usr/bin/sudo` to create a file under `/usr/local/bin`, and the wrapped step goes red on both OSes with `root-writes: the suite changed real host paths:` and that path in the log.
- **V4.** On the first green CI run after merge, every `test-shard` and `test-macos-shard` log shows `root-writes: none (` with a non-zero visited count for every non-empty root.
- **N1.** No change to `assert_no_real_root_paths`, `_unguarded_path_resets` or any ledger.
- **N2.** No Makefile target runs the scan.
- **N3.** No fixed list of files or directories to hash; the only path list is R12's prune list.
- **N4.** The scan never writes, moves or deletes anything under its roots.
- **N5.** No check the `test-shard` or `test-macos-shard` jobs run today is dropped or weakened.

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

## Multi-Lens Review, round 2

Reviewed at commit: `ae63dbcd` (revision after round 1)

### Goal-Fit

Finding: R9 applied literally to the macOS step drops the existing `ci-suite-report.sh` gate (executed equals declared), since that step exits with the report's status when make passes. Otherwise holds: the escape class the spec cites went through real sudo (`tests/helpers/suite_isolation.bash`), which hosted runners also have, so CI reproduces it.
Assumption: no background writer under the roots on hosted runners during the suite window, or one rare enough not to make the gate flaky; one scratch run cannot bound a rare writer.
Disposition: Addressed (operator, 2026-11-27) — R9 composes make, report and check statuses; N5 added; V1 is now 10 null windows per OS.

### Ergonomics

Finding: V2's escape through `tests/mocks/sudo` is already caught by the ledger guard, so a red step proves nothing about the scan; V1's bare `sudo -n find` bypasses the visited-count rule; a real-sudo escape on the scratch branch would run in pre-push on `claude`; a red shard names paths but no test and the spec gave no repro.
Assumption: same as Goal-Fit; proposed repeated null runs per image.
Disposition: Addressed (operator, 2026-11-27) — the escape uses `/usr/bin/sudo` from a file without `load_mocks`, gated on `GITHUB_ACTIONS`, and must show the scan's own line; the rollout runs `check`; the `ubuntu:26.04` repro is named and hits print their mtimes.

### Risk

Finding: "zero entries visited" cannot tell the macOS blind walk from an empty directory (`find` always prints its start point: 1 entry in both; Studio `/etc` 1 without `-H`, 295 with). R9 drops the macOS report status. One sample cannot bound the gate's flake rate. The PR branch scans itself, so the gate is not tamper-proof.
Assumption: same as Goal-Fit; proposed 5 dispatch runs per OS recording `find`'s status and stderr.
Disposition: Addressed (operator, 2026-11-27) — roots resolved with `pwd -P`, visits counted below the root, empty roots named and passing, per-root counts on the `none` line; R9 composes three statuses; 10 null windows per OS; the tamper limit is stated.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review, round 3 (scoped Risk re-review)

Reviewed at commit: `68a61d3c`, sections new in that revision only

### Risk

Finding: Root resolution with `pwd -P` makes `-H` redundant, so deleting `-H` breaks no test and R6's failure branch (the blind walk) cannot be reached by the mutation the spec described. "Empty" was not defined apart from the walk, so a root the user can enter but not list would print `empty:` and pass. Minor: a `-cnewer`-only hit prints a pre-marker mtime, mtime printing needs GNU/BSD `stat` variants under sudo; V2 gave no rule for a harmless suite-window hit.
Assumption: null windows on hosted runners show no background writes under the roots, or few enough to prune by subtree without blinding the scan where escapes land.
Disposition: Addressed (operator, 2026-11-27) — `-H` dropped, resolution is the one mechanism; emptiness by `ls -A <root>/.` under the same privilege, a refused listing fails; the R6 test mutates the resolution away; mtime printing dropped; suite-window hits are fixed or pruned by amendment, and a stop rule refuses wholesale pruning of `/etc`, `/private/etc`, `/usr/local/bin` or `/opt/homebrew`.

## External Review

### Round 1 (reviewed at `291f0a56d506b0f713c9e936956a4d8f8c18929f`)

Report: [round1.md](2026-11-27-root-writes-scan-design.external-review/round1.md)

#### Author response

| finding | disposition | evidence | reviewer verdict | operator (Step 9) |
| ------- | ----------- | -------- | ---------------- | ----------------- |
| F1.1 | Fixed | Added "Prune list" (per-OS lists, `-path <p> -prune`, entries only by amendment citing their run), R12 with the `lib/` install directories no prune may equal or contain, a test enforcing it, the restated stop rule, R2 and N3 amended. | unjudged | "spec approved" (2026-11-27) |
| F1.2 | Fixed | `test-shard` gets its own `mark` step before the shard-1 prerequisites step, so both OSes scan the prerequisites; R9 amended. | unjudged | "spec approved" (2026-11-27) |
| F1.3 | Fixed | R10 now includes a per-job `ci.yml` test pinning R9's order, the absence of an `exit` between make and `check`, and that the step's exit can come from `check`. | unjudged | "spec approved" (2026-11-27) |
| F1.4 | Fixed | V1 records `find`'s exit status and stderr; a non-zero status or stderr line in a null window stops the gate until resolved by amendment. The measurement itself is V1's, run on the hosted runner. | unjudged | "spec approved" (2026-11-27) |
| F1.5 | Fixed | Test expectations resolve paths with `pwd -P` (stated under Tests and in R10). | unjudged | "spec approved" (2026-11-27) |

Stopped: reviewer recommended stopping in round 1
