# ADR-0035: `make test` runs bats in parallel under a validated `JOBS` knob

**Date:** 2026-09-21
**Status:** Accepted.

## Context

`make test` ran `bats --recursive tests/` serially. That target is the pre-push hook, so
every non-docs push paid the full serial cost: **717s** measured on the Linux `claude` box
(Threadripper 3960X, 24 cores / 48 threads) on master `c2990e5c`, 2072 ok / 0 not ok.

Two consequences beyond the wait. It is past the harness Bash tool's 600s cap, so no
`timeout` value lets an agent run the gate — or a `git push` that triggers it — in the
foreground. And a gate that costs twelve minutes is one a session is tempted to route
around, which is how `--no-verify` gets reached for.

ai-config shipped the same change first (its ADR-0078) and measured `make test` 285.3s to
86.4s.

## Decision

`make test` runs `bats --jobs $(JOBS)` over a `find`-derived file list when **GNU**
`parallel` is present, and serially with a notice when it is not.

**`JOBS ?= 24`, from measurement rather than from the core count.** 4 concurrent scratch
clones, 12 runs per arm, arms alternated across three rounds (6/12/24, 24/12/6, 12/24/6):

| `JOBS` | n   | median     | min-max |
| ------ | --- | ---------- | ------- |
| 6      | 12  | 303.0s     | 277-308 |
| 12     | 12  | 159.0s     | 150-166 |
| 24     | 12  | **115.5s** | 114-116 |

The selection rule, fixed before the measurement, was "the smallest `JOBS` whose median is
within 10% of the best". 12 is 38% off, so the rule decides it. Note the spread _narrows_
as the worker count rises — 24's twelve runs span 2 seconds against 6's 31 — so the fastest
arm is also the most predictable, which is the opposite of the intuition that a count near
the core count is the safe one.

Single-session gain on an idle box: **717s to 71s, 10.1x**, 3 runs per arm after a warm-up.
Under 4-way contention it is 6.0x. Both figures are true and answer different questions;
the first is the ceiling, the second the floor.

**Detection asks what the binary is, not that one exists.** moreutils ships an incompatible
`parallel` under the same name (dpkg diverts it to `/usr/bin/parallel.moreutils` here), so
`command -v parallel` is true for it. `HAVE_PARALLEL` greps `parallel --version` for
`^GNU parallel`. The guard is required rather than defensive, because bats' own guard is
inverted: `bats-exec-suite:106` reads
`! type -p "$p" >/dev/null && "$p" --version &>/dev/null && ...`, so with `parallel` absent
the second term invokes the binary just established not to exist, the conjunction is false,
the branch meant to decline is skipped, and `bats --jobs` dies with `command not found`.

**`JOBS` is validated in pure make at parse time** — no `$(shell)`, no fork: exactly one
word, nothing left once digits are stripped, no leading zero. The error names the value and
`$(origin JOBS)`, because a command-line `JOBS` reaches a nested make through **both**
`MAKEFLAGS` and the recipe environment.

**The file list is a filesystem walk, not `git ls-files`.** An untracked `.bats` file is
exactly what a TDD red step produces; a tracked-only list would report it green by never
running it. The lint variables in the same Makefile use `git ls-files` deliberately and for
the opposite reason — they must not lint an untracked parked worktree — so the two
derivations differ on purpose.

**`BATS_SERIAL_FILES` carves a file out of the parallel pool to run alone afterwards, and
is empty.** The per-file check measured every file clean at `--jobs 12`; the one that was
not was fixed rather than exempted (below). A carve-out is a permanent exemption from the
gate everything else runs under, so a name goes in only with a measurement beside it.

**`HAVE_PARALLEL=` on the command line forces serial**, because a command-line assignment
beats the Makefile's own detection. No second knob.

## What the pilot found

**One real defect, fixed rather than carved out.** `git_hooks.bats` and
`pyenv_rehash_hook.bats` read a file's mtime as `stat -f '%m' f || stat -c '%Y' f`. On GNU
coreutils `-f` is **filesystem status**, not format — it succeeds, prints a filesystem
block, and the `||` never fires. The two comparison sites then fail in opposite directions:
an equality assertion compares two identical filesystem blobs and passes for the wrong
reason, while an inequality assertion is satisfied by free-block counters moving between
the two calls — a **false pass**, measured 10 of 10 with the guarded `cp` deleted and
`dd`+`rm` churn asserted live against the same tmpfs, and 0 of 6 both idle and with the
churn aimed at a different filesystem.

Serial runs never see it, because nothing else is writing. `--jobs` creates the condition
by construction. Both sites now read `stat -c '%Y'` first and assert the value matches
`^[0-9]+$` before comparing, so a blob cannot reach a comparison.

**Isolation: 80 of 80 runs clean.** 20 rounds of 4 concurrent clones at `JOBS=24`, random
start offsets; every run `rc=0`, 2072 ok / 0 not ok, `git status --porcelain` empty
afterwards. Zero failures over 80 runs bounds the per-run rate below about 3.7% at 95%
_only if the runs were independent_, and they are not — four clones per round share one
box. The honest statement is the observation, not a rate.

## CI

**CI takes the parallel path, and not because the workflow asks for it.** `ubuntu-latest`
preinstalls GNU parallel (`parallel 20231122+ds-1`, per `actions/runner-images`' Ubuntu2404
README; independently confirmed here by running this repo's new target test in an
`ubuntu:24.04` container). An earlier draft of the spec claimed dotfiles' CI would stay
serial because the workflow installs no `parallel` — that read `ci.yml`, which records what
a workflow _installs_ and has no field for what the _image ships_. ai-config's job log
settles it: `bats --jobs 12` present, serial notice zero times, workflow installs only
`bats`.

Runner-measured `test` job durations from ai-config, via the GitHub API:

| arm                   | n   | median   |
| --------------------- | --- | -------- |
| serial                | 15  | 324s     |
| `--jobs $(nproc)` = 2 | 1   | 374s     |
| `--jobs 12`           | 2   | **279s** |

So the regression that prompted ai-config's #276 came from `JOBS="$(nproc)"` — two workers
on a 2-vCPU runner, the worst available setting — not from parallel itself.

**Never pass `JOBS="$(nproc)"`.** The workflow is otherwise unchanged, so the default
applies, and `JOBS=24` on a 2-vCPU runner is an **extrapolation** from ai-config's 2-and-12
evidence rather than a measurement. Stated before the fact: dotfiles' `test` job has a
20-run serial baseline of median 454.5s (range 358-600); if the first three runs under the
parallel path have a median above that, the workflow gets `make test HAVE_PARALLEL=` and
the figure is recorded either way. A parallel-only test failure blocks regardless of timing.

`macos-latest` ships no `parallel` and that job runs only `bash -n`/`zsh -n`, not
`make test`, so detection takes the serial path there by construction.

## Consequences

- The push-path gate costs ~71s instead of ~717s, and now fits inside the harness Bash
  tool's cap — an agent can run `make test` and `git push` in the foreground again.
- `make test` depends on a package nothing provisions. GNU `parallel` is hand-installed on
  `claude` (pulled in as a Recommends of `bats` on 2026-09-12) and is named in no
  `Brewfile`, `ubuntu_*_packages.txt`, `lib/` or `scripts/` entry — so a rebuild loses the
  speedup silently, degrading to the serial notice rather than failing. Tracked as a
  backlog row.
- Anything asserting on timing or on a global mutable (free blocks, inodes, a shared
  `/tmp`) is now under concurrency by default. `unit.bats` uses bare `mktemp -d` rather
  than `BATS_TEST_TMPDIR`, so bats does not reap it and `JOBS=24` multiplies `/tmp` churn
  accordingly — correct today (unique dir per call), worth knowing if a timing-sensitive
  test ever lands.
- `tests/makefile_parallel_target.bats` pins every branch of the recipe from `make -n test`
  output under a from-scratch `PATH`, including the carve-out branch that ships unused.

## Related

- ai-config ADR-0078 and its Amendment 2, which retracts the CI-serial claim.
- `ai-config/.claude/standards/ci.md`, "A workflow file says what CI _installs_, never what
  the runner image _ships_".
- `ai-config/.claude/standards/shell.md`, "`cmd || fallback` CONCATENATES when the failing
  command already wrote to stdout" — the pitfall the `stat` fix repairs.
- `specs/2026-09-21-parallel-bats-pilot-design.md` for the full pilot evidence.
