# Parallel bats execution pilot (dotfiles) — design

Date: 2026-09-21
Status: Draft — awaiting spec review

## Problem

`make test` in dotfiles runs `bats --recursive tests/` serially. Measured on the Linux
`claude` box (Threadripper 3960X, 24 cores / 48 threads), on master `c2990e5c`, in a
`--no-hardlinks` scratch clone:

```
bats --recursive tests/   rc=0   694s   2072 ok   0 not ok
```

That gate is the pre-push hook, so every non-docs push from every dotfiles session pays
**11.6 minutes**. It is also past the harness Bash tool's 600s cap, which is its own cost:
no `timeout` value lets a gate or a `git push` complete in the foreground, so every agent
run of it needs the redirect-and-poll form.

ai-config shipped the same change (ADR-0078, #275) and measured `make test` 285.3s → 86.4s,
**3.30x**, with 79 concurrent-clone runs showing zero parallel-only failures.

## Scope

In:

1. `Makefile`: `bats --jobs $(JOBS) --recursive tests/` when GNU `parallel` is present,
   serial with a notice otherwise. `JOBS ?= 12`, validated in pure make at parse time.
2. A serial carve-out for the timing-sensitive files, run after the parallel phase.
3. `tests/` fixes for any file the per-file check shows racing.
4. A target test (`tests/makefile_parallel_target.bats`) asserting every branch of the
   recipe from `make -n test` output under a from-scratch `PATH`: GNU parallel present,
   absent, and present-but-moreutils; `JOBS` validation; the default under a leaked outer
   `JOBS`/`MAKEFLAGS`; an untracked `.bats` file reaching the list; the carve-out branch;
   and an empty file list refusing rather than passing.
5. `CLAUDE.md` Testing section: the new gate shape and the GNU-parallel detection rule.

Out, and stated rather than implied:

- **Any workflow change.** CI inherits the parallel path from the runner image without
  one; see the next section, and the revert rule there.
- **pytest-xdist.** dotfiles tracks 2 `.py` files against 54 `.bats`; `test-python` runs
  three files by name. There is nothing for xdist to parallelise.
- **`bash-coverage`.** The PS4 tracer appends per traced shell to fd 9; its behaviour under
  `--jobs` is unverified and it stays serial.

## CI takes the parallel path automatically, and that is the correct default

An earlier draft of this spec carried a section titled *"CI must stay serial, and the
reason is measured"*, citing ai-config's #275/#276 and a container experiment. **It was
wrong, and the way it was wrong is worth more than the conclusion it reached.**

**GNU `parallel` is preinstalled on the `ubuntu-latest` runner image** (`parallel
20231122+ds-1`, per `actions/runner-images`' Ubuntu2404 README). So "CI never installs
parallel" — read off `ci.yml`, which records what a workflow *installs* and has no field
for what the *image ships* — licensed no conclusion at all. ai-config's own job log
settles it: on run `35556679522`, post-#276, the serial notice appears **0** times and
`bats --jobs 12` appears, while the workflow installs only `bats`.

Runner-measured `test` job durations, from the GitHub API rather than from a container
standing in for it:

| repo | arm | n | median |
| --- | --- | --- | --- |
| ai-config | serial (pre-#275) | 15 | 324s (265–355) |
| ai-config | `--jobs $(nproc)` = 2 | 1 | 374s |
| ai-config | `--jobs 12` (today) | 2 | **279s** |
| dotfiles | serial (today) | 20 | 454.5s (358–600) |

So `--jobs 12` is about **14% faster than serial** on a 2-vCPU runner, not 3x slower. The
regression #275 measured came from `JOBS="$(nproc)"` — two workers, the worst available
setting — and the container's ratios never transferred, because that arm was a different
population (31 files, no pytest phase, no lint).

**Decision for dotfiles:** let CI take the parallel path it will take anyway, and **never**
pass `JOBS="$(nproc)"`. The workflow is unchanged, so the default applies — which after
step 2 is **24**, and that is the one number here measured on a 48-thread box and *not* on
a 2-vCPU runner. ai-config's runner evidence covers 2 and 12 only, and its shape (12 beat
serial, 2 lost to it) says more workers helps rather than hurts on that hardware, but 24 on
two cores is an extrapolation and is named as one.

**Revert rule, stated before the measurement so it cannot be rationalised after it.** The
dotfiles `test` job has a 20-run serial baseline of median 454.5s. If the first three runs
under the parallel path have a median above that baseline, CI is pinned to serial with
`make test HAVE_PARALLEL=` in the workflow — a one-word command-line override of the
detection variable, not a second knob — and the figure is recorded here either way. A
parallel-only test failure on CI is a correctness finding and blocks regardless of timing.

**`macos-latest` is unaffected**: it ships no `parallel` (checked against the macos-15 and
macos-14 arm64 READMEs, zero hits), and dotfiles' macOS job runs only `bash -n`/`zsh -n`,
not `make test`. Detection there takes the serial path by construction.

## Design

Identical in shape to ADR-0078, with three dotfiles-specific differences.

**The file list is derived, not `--recursive`.** dotfiles has `tests/setup_env/`,
`tests/zshrc.d/`, `tests/scripts/` and more, so the obvious form is
`bats --jobs $(JOBS) --recursive tests/`. It is not usable as-is, because a carve-out has
to be *subtractable*: `--recursive tests/` cannot express "every file except this one", so
a carved-out file would run twice. The list is therefore
`$(shell find tests -name '*.bats' | sort)`, and the carve-out is `$(filter-out ...)` over
it. Verified to name the same set `--recursive` walks.

Do **not** substitute a `git ls-files`-derived list: it drops untracked files, so a new
`.bats` file in a TDD red step would report green by never running. That cost ai-config a
review round. The lint variables in the same Makefile use `git ls-files` deliberately and
for the opposite reason — they must *not* lint an untracked parked worktree — so the two
derivations differ on purpose.

**The serial fallback runs the filtered list too**, not the full one, for the same
double-run reason. Caught by review after the first version shipped `BATS_ALL_FILES`
there; both runs pass, so no assertion about outcomes would have found it.

**An empty derived list refuses rather than passing.** bats does exit 1 on no arguments,
but its message ("Must specify at least one <test>") reads as a usage mistake rather than
as a broken derivation, which is the actual fault — so the recipe says so itself. A
conditional, not a parse-time `$(error)`: that would abort `make help` as well.

**Detection checks what the binary is, not that it exists.**

```make
HAVE_PARALLEL := $(shell parallel --version 2>/dev/null | grep -q '^GNU parallel' && echo yes)
```

moreutils ships an incompatible `parallel` under the same name — on this box `dpkg -S`
shows the moreutils binary diverted to `/usr/bin/parallel.moreutils`. `command -v parallel`
is true for it, so the promised serial fallback would never happen and `bats --jobs` would
fail on whatever the other binary does with those arguments. The guard is also required
rather than optional, because bats' own one is inverted. `bats-exec-suite:106` (bats
1.13.0) reads:

```bash
if ! type -p "${parallel_binary_name}" >/dev/null && "${parallel_binary_name}" --version &>/dev/null && ...
```

With `parallel` absent, `! type -p` is true and the very next term *invokes the binary that
was just established not to exist*, so the conjunction is false and the branch meant to
decline is skipped — `bats --jobs` then dies with `command not found`. Detecting in the
Makefile is what turns that into a clean serial run with a notice.

**`JOBS` is validated in pure make**, with no `$(shell)` and no fork: exactly one word, nothing
left after the digits are stripped, no leading zero. The error names the value and
`$(origin JOBS)`, so a stray exported `JOBS` is diagnosable. The block sits above every
other assignment in the file, so a bad value aborts before four subprocesses have run.

**`HAVE_PARALLEL=` on the command line is the force-serial escape hatch** — a command-line
assignment beats the Makefile's own detection, so a machine or a CI job that must not run
in parallel needs no second knob. The serial notice therefore names both causes ("GNU
parallel absent, or overridden on the command line"), because "not found" would be false
in the override case.

## Serial carve-out

**Empty, and that is a measurement rather than an omission.** The per-file check ran all
54 files at `--jobs 12` against a serial control; 53 agreed on the first pass and the 54th
(`tests/setup_env/git_hooks.bats`) was root-caused to a GNU/BSD `stat` portability defect
and **fixed** (`39704a12`) rather than carved out. A carve-out is a permanent exemption
from the gate every other file runs under, so a name goes in `BATS_SERIAL_FILES` only with
a measurement beside it.

The Makefile still carries the carve-out branch with an empty list, and the target test
exercises it by overriding `BATS_SERIAL_FILES` on the command line — so the shape is under
test before the first name needs it, and adding one is a one-word edit rather than a
recipe rewrite.

Two counts were offered as risk proxies and are **not** the property. Recorded so nobody
re-derives them as findings:

- Three fixed `/tmp` literals exist (`git_hooks.bats:2231`, `:2237`, `unit.bats:437`) and
  none is a collision hazard: all three are assertion _values_ compared as strings, and
  nothing under `tests/` `mkdir`s or `touch`es either literal.
- 28 files reference `HOME=`. Almost all resolve per-test-unique — `TMPDIR_TEST`,
  `_fake_home` and `_fixture` are each `mktemp -d`. The count is not the risk; the three
  files that pass the operator's real `$HOME` are, and all three passed the per-file check.

## Pilot evidence

Run in scratch clones under the session scratchpad, never in the worktree, with
`</dev/null` on every suite invocation. **Every run must exit 0 with per-outcome counts
equal to the serial baseline** (2072 ok / 0 not ok), or it is a failure and not a data
point.

1. **Per-file races.** Each of the 54 files, 5 runs at `--jobs 12` vs one serial run,
   comparing rc and per-outcome counts. Any file that differs is fixed, or joins the serial
   carve-out with the reason recorded.
2. **`JOBS` choice.** 4 concurrent clones, `JOBS` ∈ {6, 12, 24}, 3 rounds each after a
   discarded warm-up, arms alternated (6/12/24, 24/12/6, 12/24/6) so a drifting machine
   cannot favour whichever arm ran first. Default is the **smallest `JOBS` whose median is
   within 10% of the best** — the tie-break is toward fewer workers, because a session is
   rarely alone on the box.

   The measured command is the recipe's own `bats --jobs N <file list>`, not `make test`:
   `lint`, `check-lock`, `check-requirements-ci` and `test-python` are fixed cost that does
   not vary with `JOBS`, so including them would shrink every ratio by a constant and
   measure the prerequisites' scheduling noise rather than the knob. The file list is the
   same `find`-derived list the recipe passes, so the invocation under measurement is the
   one that ships. Step 5 reports the whole-gate figure the operator actually feels.
3. **Isolation.** 20 rounds of 4 concurrent clones at the chosen `JOBS`, random start
   offsets. Counts equal to baseline in every run; `git status --porcelain` empty after each.
   Zero failures bounds the per-run rate below about 3.7% at 95% **only if runs were
   independent, which they are not** — they share load. Report the observation, never a rate.
4. **Timing files under load — not run, because the configuration it measures is not the
   one that ships.** As specified, this arm ran the carve-out files *alone* while other
   clones loaded the box, against a serial control. With `BATS_SERIAL_FILES` empty there
   are no such files: every timing-sensitive file runs *inside* the parallel pool, which
   step 3 exercises 20 times at 4-way concurrency — strictly harsher than alone-under-load,
   since it adds intra-suite contention on top of the same external load. Dropping it is a
   scope decision recorded here rather than a step quietly skipped; if a file is ever added
   to `BATS_SERIAL_FILES`, this arm becomes live again and must run before that name lands.
5. **Single-session gain.** Master serial vs branch at the chosen `JOBS`, 3 runs each after
   a warm-up, arms alternated.

A run lost to something external — the pyenv shim rebuild that cost ai-config one run of 80
— is recorded as environmental and **not** re-run to replace it.

## Pilot results

**Step 2 — `JOBS` choice. `JOBS ?= 24`.** 4 concurrent scratch clones, 3 rounds per arm
after a discarded warm-up, arms alternated 6/12/24, 24/12/6, 12/24/6. Every one of the 40
runs (36 + 4 warm-up) exited 0 with **2072 ok / 0 not ok** and an empty
`git status --porcelain`.

| `JOBS` | n | median | min-max | vs best |
| --- | --- | --- | --- | --- |
| 6 | 12 | 303.0s | 277-308 | 2.62x |
| 12 | 12 | 159.0s | 150-166 | 1.38x |
| 24 | 12 | **115.5s** | 114-116 | 1.00x |

The rule was "the smallest `JOBS` whose median is within 10% of the best". 12 is 38% off,
so the rule selects 24 without a judgement call. Note the spread narrows as `JOBS` rises —
24's 12 runs span 2 seconds against 6's 31 — so the fastest arm is also the most
predictable, which is the opposite of what oversubscription is supposed to do and is worth
remembering before assuming a worker count near the core count is "safer".

**Against the serial baseline: 694s to 115.5s, a 6.0x reduction — and that is measured
under 4-way contention**, where the serial figure was measured alone. Step 5 reports the
uncontended single-session figure, which is the one an operator on an otherwise idle box
actually feels.

**Step 3 — isolation. 80 of 80 runs clean.** 20 rounds of 4 concurrent scratch clones at
`JOBS=24`, random start offsets up to 90s so the rounds interleave rather than march in
lockstep. Every run: `rc=0`, **2072 ok / 0 not ok**, and an empty `git status --porcelain`
afterwards. Median 89s, range 69-106 — faster than step 2's 115.5s because the offsets mean
fewer clones are in their heavy phase at the same moment, which is the realistic shape.

Zero failures over 80 runs bounds the per-run failure rate below about **3.7% at 95%** —
**but only if the runs were independent, and they are not**: four clones per round share one
box, so a round is closer to one observation than four. The honest statement is the
observation, not a rate: no parallel-only failure appeared in 80 runs across 20 rounds, and
no run left a dirty tree.

**Step 5 — single-session gain. 717s to 71s, 10.1x.** Master serial against the branch at
`JOBS=24`, alternated, 3 runs per arm after a discarded warm-up per arm, on an otherwise
idle box. All 8 runs `rc=0`, 2072 ok / 0 not ok, clean tree.

| arm | runs | median |
| --- | --- | --- |
| master, serial | 712s, 717s, 722s | **717s** |
| branch, `JOBS=24` | 71s, 78s, 71s | **71s** |

The serial rows record a start-of-run load average of 8-11, which is residue decaying from
the parallel run that preceded each of them, not concurrent work. It cost nothing: the
serial **warm-up** ran at load 0.06 and took 717s, the same as the median of the three
loaded starts. Recorded rather than dropped, because a load column that looks alarming and
is not is worth explaining once instead of re-investigating later.

Note the two gain figures answer different questions and neither supersedes the other: 6.0x
is what a session gets while three peers are also running a suite, 10.1x is what it gets
alone. The first is the floor and the second is the ceiling.

## Verification

- `make test` green on `claude` on the branch. The suite count is master's 2072 plus the
  cases `tests/makefile_parallel_target.bats` adds — not 2072, which was the pilot
  clones' count and is this branch's baseline rather than its target.
- The empty-list branch refuses: `make -n test BATS_ALL_FILES=` emits `exit 1` and no
  `bats` invocation. bats does exit 1 on no arguments, but its message reads as a usage
  mistake rather than as a broken file-list derivation, which is the actual fault.
- The target test's cases each red under their own mutation.
- CI green, and the `test` job's duration recorded against dotfiles' 20-run serial
  baseline (median 454.5s) under the revert rule above. The job log is the instrument:
  `bats --jobs 12` present and the serial notice absent means the parallel path ran.
- Pilot steps 1–5 in the PR body, each against its stated rule.

## Fan-out

The Makefile change moves every dotfiles session's push-path gate, so per
`git-workflow.md`'s tier table it needs notice **before** merging, not after. Agreed form
with the dotfiles session: a message carrying the measurements, plus the `CLAUDE.md` Testing
line in the same PR. Not a backlog row — the backlog is for findings deferred without
shipping, and this ships.
