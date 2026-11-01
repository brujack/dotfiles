# macOS shard weights measured on the runner

- **Date:** 2026-11-01
- **Status:** Retired 2026-11-01 without shipping: Step 8 refuted the premise (see Multi-Lens Review).
- **Backlog row:** "bats process-spawn cost (part 2 of the setup floor)" (operator chose the CI wall-clock win first, as option 3 of the part-2 brainstorm)

## Problem

The macOS gate is the long pole of every PR. Its three `test-macos-shard` legs are packed by
`scripts/bats-shard.sh` from `tests/bats-weights.tsv`, and the packing is badly unbalanced on the
runner even though it is balanced on paper.

Measured on run 41323131527 (dotfiles#415, `macos-26-arm64` image `20261021.618` on all three legs):

| Leg | Predicted CPU s (table) | `Run tests` step | Heaviest file in the leg                    |
| --- | ----------------------- | ---------------- | ------------------------------------------- |
| 1   | 879                     | 359 s            | `tests/setup_env/unit.bats` (176.6)         |
| 2   | 902                     | 141 s            | `tests/setup_env/linux_ubuntu.bats` (529.1) |
| 3   | 900                     | 418 s            | `tests/setup_env/workflows.bats` (380.3)    |

The previous merged run (41262365883, dotfiles#414) shows the same shape: one leg about 2m47s while
the others took 6m32s and 7m47s. The slowest leg sets the gate's wall time, so the gate waits about
4.6 minutes longer than a balanced split of the same work would.

Population: the table was measured on the Mac Studio (2026-10-31, `ab92a62d`, `bats --jobs 3 <file>`
per file under `env -i`); the claim it is used for is CPU cost on a `macos-latest` runner. The two
differ. Leg 2 holds the table's single heaviest file and finished first, so that file's Studio
weight greatly overstates its cost on the runner. Why is not derivable from the repo:
`linux_ubuntu.bats` has one `skip`, gated on Darwin without GNU `ar`, and both hosts are Darwin.

The same table balances the Linux legs (dotfiles#415: 4m13s / 5m08s / 5m14s), so the defect is a
macOS-runner one.

The existing reseed procedure (ai-config
`docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Shard weights: reseed procedure`) already
says to reseed when a leg drifts more than 10% from its packed weight. Leg 2's step time over its
weight is 0.16 s/CPU s against 0.40 and 0.46 for the others. A Studio reseed would measure the wrong
host again.

## Design

Measure the macOS table on the runner, with a reusable dispatch-only workflow, and point the macOS
legs at it. The table's definition is unchanged: user plus system CPU seconds, children included, of
`bats --jobs 3 <file>` run alone. Only the host changes.

### `scripts/measure-bats-weights.sh <list-file>`

For each path in `<list-file>`, run that file alone as `"${_MEASURE_TIME_BIN}" -p
"${_MEASURE_BATS_BIN}" --jobs 3 <file> < /dev/null`, and print one row:
`<path>\t<user+sys>\t<ok count>\t<rc>`.

- Seams: `_MEASURE_TIME_BIN` (default `/usr/bin/time`) and `_MEASURE_BATS_BIN` (default `bats`).
- Files run one after another, never concurrently, so a 3-vCPU runner is not contended.
- A red file's row carries its real rc and the next file still runs. After the last file the script
  exits 1 if any row's rc is non-zero.
- A timer output with no `user` line or no `sys` line gives that row rc 2 and the message
  `no CPU figure: <path>` on stderr.
- The Studio form of the reseed procedure calls this script instead of its inline `one()` function,
  so one implementation serves both hosts.

### `scripts/build-bats-weights.sh <host-label> <tsv>...`

Merge measured rows into a weights table on stdout.

It exits 1, naming the path on stderr, on any of:

- a row whose rc is not 0;
- a row whose CPU figure is 0.0 or not a number;
- a path that appears in more than one row;
- a `find tests -name '*.bats'` file with no row;
- a row for a path that is not a `find` result.

It runs from the repo root and reads the short SHA from `git rev-parse --short HEAD`. Otherwise it prints one header comment
(`# CPU s (user+sys, children) of bats --jobs 3 <file>; <host-label> @ <short sha>; reseed: ai-config docs/knowledge/dotfiles-bats-test-infrastructure.md`)
then `<path>\t<cpu>` rows with one decimal, sorted with `LC_ALL=C sort`. That is the format
`bats-shard.sh` already reads, so the packer is unchanged.

### `.github/workflows/bats-weights-macos.yml`

Triggered by `workflow_dispatch` only.

- `measure`: a 3-leg matrix on `macos-latest`, with the same tool installs as `test-macos-shard`
  (unpinned Homebrew bash, bats-core, parallel, coreutils; pinned, checksum-verified shellcheck and
  uv), copied rather than shared, as `ci.yml` already repeats them. Each leg runs
  `bash scripts/bats-shard.sh <i> 3` to choose its files (any table will do; balance only changes
  wall time), runs the measure script on them and uploads its rows as `weights-rows-<i>`.
- `build`: on `ubuntu-latest`, `needs: measure`, `if: always()`. Downloads every `weights-rows-*`
  artifact, runs `build-bats-weights.sh "macos-latest runner"` over them and uploads
  `bats-weights-macos.tsv`. A missing upload or a red row makes the build refuse, so no partial
  table exists.
- Every job: `permissions: contents: read`, `timeout-minutes`, and
  `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`. Actions are SHA-pinned as in `ci.yml`.

### CI switch

`test-macos-shard`'s "Compute shard list" step gains `env: BATS_WEIGHTS: tests/bats-weights-macos.tsv`.
`test-shard` keeps `tests/bats-weights.tsv`.

### Rollout

GitHub dispatches only a workflow whose file is on the default branch, so this ships as two PRs:

1. **PR1:** both scripts, their tests and the workflow.
2. After PR1 merges: `gh workflow run bats-weights-macos.yml --ref master`, wait for it, download
   the `bats-weights-macos.tsv` artifact.
3. **PR2:** commit `tests/bats-weights-macos.tsv` and the CI `env:` line; the PR body names the
   dispatch run ID.

### Error handling

- One red file does not hide the others' cost, but no table is built from a run with any red file.
- A cancelled or failed leg leaves files without rows, and the build refuses naming them.
- A timer that prints no CPU figure fails that row, so a broken instrument cannot write zeros.
- A file added after the reseed has no row; `bats-shard.sh`'s existing fallback weighs it by
  `@test` count. Balance degrades, the file set does not.
- Without the `env:` line the macOS legs fall back to the Studio table, which is today's behaviour;
  a shape test pins the line.

### Testing

`tests/scripts/measure_bats_weights.bats` (new), with the time and bats seams pointed at stubs:

- The time stub prints `user 1.25` and `sys 0.50`; the row's CPU figure is exactly `1.75`.
- A bats stub emitting 3 `ok` lines gives ok count 3.
- A red file's row carries its rc, the next file still runs and the script exits 1.
- A timer with no `user`/`sys` line gives rc 2 and `no CPU figure: <path>`.
- A bats stub that reads stdin sees EOF.

`tests/scripts/build_bats_weights.bats` (new), on a fixture tree under `tests/fixtures/`, never the
real `find`:

- A complete fixture produces a golden table: header, one decimal, `LC_ALL=C` order.
- Each refusal fails naming the path: rc not 0, zero CPU, non-numeric CPU, duplicate, missing file,
  dead row.

CI shape, parsed per job:

- `tests/scripts/ci_bats_weights_macos.bats` (new): the workflow's only trigger is
  `workflow_dispatch`; every job has `timeout-minutes` and `contents: read`; `build` has
  `if: always()`.
- `tests/scripts/ci_test_macos_shard.bats` (PR2): the "Compute shard list" step of
  `test-macos-shard` sets `BATS_WEIGHTS: tests/bats-weights-macos.tsv`; `test-shard`'s does not.
- `tests/scripts/bats_shard.bats` (PR2): its table-format test also covers
  `tests/bats-weights-macos.tsv`.

### Docs

- The reseed section in ai-config `docs/knowledge/dotfiles-bats-test-infrastructure.md` is rewritten
  around the two scripts: the dispatch command for the macOS table, the Studio command for the
  default table.
- `CLAUDE.md`'s `tests/bats-weights.tsv` line names both tables and which legs read each.

## Requirements

- **R1.** `[PR1]` `scripts/measure-bats-weights.sh <list>` runs each listed file alone as `<time> -p <bats> --jobs 3 <file> < /dev/null` and prints `<path>\t<user+sys>\t<ok count>\t<rc>` per file.
- **R2.** `[PR1]` The measure script records a red file's real rc, still runs the remaining files, and exits 1 when any row's rc is non-zero.
- **R3.** `[PR1]` The measure script gives a row rc 2 and prints `no CPU figure: <path>` on stderr when the timer output lacks a `user` or `sys` line.
- **R4.** `[PR1]` `_MEASURE_TIME_BIN` (default `/usr/bin/time`) and `_MEASURE_BATS_BIN` (default `bats`) select the timer and bats binaries.
- **R5.** `[PR1]` `scripts/build-bats-weights.sh <host-label> <tsv>...` exits 1 naming the path on a non-zero rc, a zero or non-numeric CPU figure, a duplicate path, a `find tests -name '*.bats'` file with no row, or a row for a path `find` does not return.
- **R6.** `[PR1]` On valid input the build script prints one header comment naming the host label, the short SHA and the reseed section, then `<path>\t<cpu>` rows with one decimal in `LC_ALL=C sort` order.
- **R7.** `[PR1]` `.github/workflows/bats-weights-macos.yml` triggers only on `workflow_dispatch`, runs a 3-leg `macos-latest` `measure` matrix and an `ubuntu-latest` `build` job with `needs: measure` and `if: always()`, and uploads `bats-weights-macos.tsv`.
- **R8.** `[PR1]` Every job in that workflow declares `timeout-minutes`, `permissions: contents: read` and `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`, and every action is SHA-pinned.
- **R9.** `[PR2]` `tests/bats-weights-macos.tsv` is the build script's output from a dispatch run at master.
- **R10.** `[PR2]` `test-macos-shard`'s "Compute shard list" step sets `BATS_WEIGHTS: tests/bats-weights-macos.tsv`; `test-shard`'s does not set `BATS_WEIGHTS`.
- **V1.** The first dispatch at master produces a table with one row per `find tests -name '*.bats'` file (92 at writing), every one measured rc 0; the PR2 body names the run ID.
- **V2.** Over the first 3 PR runs after PR2 merges, each run's slowest `test-macos-shard` `Run tests` step is at most 1.15 times that run's three-leg mean (run 41323131527: 418 s against 306 s, 1.37).
- **V3.** The slowest macOS `Run tests` step is below 418 s on at least 2 of those 3 runs.
- **V4.** The ai-config reseed section (another repo, so outside this diff) runs the Studio table through `scripts/measure-bats-weights.sh` and `scripts/build-bats-weights.sh` and documents the dispatch command for the macOS table, landing with PR1.
- **N1.** `tests/bats-weights.tsv` and the `test-shard` legs are unchanged.
- **N2.** `scripts/bats-shard.sh` and `lib/bats_shard_pack.awk` are unchanged.
- **N3.** The shard count of either platform is unchanged.
- **N4.** The new workflow has no `schedule`, `push` or `pull_request` trigger.

## Multi-Lens Review

Reviewed at commit: `2a3e2b29` (Step 7 self-review commit, before Step 8 dispatch)

All three lenses independently refuted the premise. `Run tests` step times per leg over the five
`test-macos-shard` runs since the job existed (shard lists downloaded and diffed; same image
`macos-26-arm64` on every leg):

| Run | Leg 1 (`setup_env/unit`) | Leg 2 (`linux_ubuntu`) | Leg 3 (`workflows`) | max/mean |
| --- | --- | --- | --- | --- |
| 41323131527 (#415) | 359 s | 141 s | 418 s | 1.37 |
| 41262365883 (#414) | 443 s | 370 s | 152 s | 1.38 |
| 41252117611 | 468 s | 166 s | 409 s | 1.35 |
| 41244276701 | 316 s | 433 s | 422 s | 1.11 |
| 41240902996 | 347 s | 495 s | 308 s | 1.29 |

Leg 2's list was byte-identical in #414 and #415 and took 370 s then 141 s. The Problem section's
reading of #414 as "the same shape" is wrong: its short leg was leg 3.

### Goal-Fit

Finding: Premise false. The imbalance does not follow the files, so a static table cannot fix it,
and the design's own `measure` matrix spreads files over three runner instances and would freeze one
run's per-instance noise into the table. V2's 1.15 bound passed in 1 of 5 runs with today's table,
so it would pass or fail by chance. Simpler path: keep per-file `bats --timing` output from shard
legs on success for three runs and find where the variance lives.
Assumption: runner speed is equal across a run's three legs and stable between runs. Refuted or
confirmed by comparing one file's per-file time across legs and runs.
Disposition: Accepted, reason: premise refuted by the five-run table; spec retired without shipping (operator, 2026-11-01).

### Ergonomics

Finding: Premise false (same data). Secondary, only if it survived: the Linux table would still be
reseeded on the Studio, which hosts no sessions; no signal says either table is stale (the current
table already lacks rows for 6 of 92 files); the header should record the runner image version.
Assumption: a leg's `Run tests` time is a stable function of its file list on a fixed SHA.
Settled by re-running all jobs of one CI run two or three times on the same SHA.
Disposition: Accepted, reason: premise refuted by the five-run table; spec retired without shipping (operator, 2026-11-01).

### Risk

Finding: Premise false (same data). Per-file CPU is a sound predictor of leg wall time on equal
hosts (the Linux legs balance on this table); the defect is host variance, which also inflates CPU
seconds on a slow instance. Minor gaps if it survived: the build job needs `actions/checkout`; the
measure script must keep timer stderr apart from bats stderr; it drops the Studio procedure's `env -i`.
Assumption: one file's CPU seconds on one `macos-latest` instance predict its cost on another.
Settled by a dispatch where all three legs measure the same list and rows are compared.
Disposition: Accepted, reason: premise refuted by the five-run table; spec retired without shipping (operator, 2026-11-01).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Probe after retirement (operator-approved re-runs, same SHA)

All jobs of run 41323131527 (`d4851db1`) re-run twice; identical file lists per leg on every attempt:

| `Run tests` | Leg 1 | Leg 2 | Leg 3 | max/mean |
| --- | --- | --- | --- | --- |
| macOS, attempt 1 | 359 s | 141 s | 418 s | 1.37 |
| macOS, attempt 2 | 380 s | 319 s | 345 s | 1.09 |
| macOS, attempt 3 | 281 s | 318 s | 337 s | 1.08 |
| Linux, attempt 1 | 214 s | 289 s | 299 s | 1.12 |
| Linux, attempt 2 | 269 s | 283 s | 291 s | 1.05 |
| Linux, attempt 3 | 152 s | 276 s | 312 s | 1.32 |

The same leg on the same SHA ranged 141-319 s (macOS leg 2) and 152-269 s (Linux leg 1). With
attempt 1's outlier set aside, the Studio-measured table already balances the macOS legs to about
1.08, so the slowest leg is set by which runner a leg lands on, consistent with the operator's
reading that hosted runners are sometimes overloaded.
