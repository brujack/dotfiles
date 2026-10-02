# macOS test gate

**Date:** 2026-10-02
**Status:** Draft, awaiting operator review

## Problem

No test in this repo executes on macOS. `ci.yml`'s `test` and `bash-coverage` jobs run
on `ubuntu-latest`. `lint-macos` runs on `macos-latest` but only does `bash -n` and
`zsh -n`. Until 2026-09-19 the gap was covered by accident: the dotfiles session ran on
the Mac Studio, so the pre-push hook ran `make test` on macOS on every push. The session
then moved to the Linux `claude` box and that cover went with it.

Measured 2026-10-02 on the Mac Studio (Darwin arm64, macOS 27.0.1), in a throwaway clone
of `origin/master` at `af2d024`, bash 5.3.20, bats 1.14.0:

| run | environment                                                                                          | result                              |
| --- | ---------------------------------------------------------------------------------------------------- | ----------------------------------- |
| A   | non-interactive `ssh` shell, gnubin GNU Make 4.4.1 on `PATH`, real `HOME`                            | 2155 ok, 6 not ok, rc 2             |
| B   | `env -i`, empty `HOME`, `PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`, system GNU Make 3.81 | 2155 ok, 6 not ok, rc 2, 12 skipped |
| C   | as B plus `MACOS=1` exported; `tests/setup_env/unit.bats` and `linux_ubuntu.bats` only               | 359 ok, 1 not ok                    |

Runs A and B fail the same six tests. Run C fails one.

| test                                                 | cause                                                                                                                           |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 1667, 1668 `_doctor_check_cred_dirs real`            | the test inherits `MACOS` from its parent shell. With it unset, `lib/helpers.sh:681`'s `stat -c` branch runs against BSD `stat` |
| 1698, 1700 `_doctor_check_github_mcp`                | same inheritance. `tests/setup_env/unit.bats:2237` branches on `MACOS` and takes the `date -d` arm                              |
| 1702 `_doctor_check_github_mcp ... expired`          | same inheritance; `lib/helpers.sh:895`'s `date -d` branch runs                                                                  |
| 1266 `_install_ubuntu_edge_source ... truncated key` | the expected warning is absent; cause not diagnosed. Added by #304 on 2026-10-02                                                |

So there are two findings, and they are different in kind:

- **Five tests depend on who runs them.** They pass in an interactive mac shell, which
  exports `MACOS=1`, and fail in any shell that does not: `ssh`, cron, a CI runner. That
  is a test-harness defect. It was invisible while every run came from an interactive
  shell.
- **One test (1266) fails on macOS in every environment measured.** It landed on
  2026-10-02 with nothing to stop it. This is the one confirmed instance of the problem
  the operator reported.

**Boundary.** Run C covers two of 57 bats files, the two that hold the six failures. It
shows those five tests pass with `MACOS=1`; it does not show what the other 55 files do
with `MACOS=1` exported. Run B is the closest local stand-in for a hosted runner, and it
is still a provisioned mac: Homebrew's tools are present and the hostname is mapped. The
first CI run of this change is what tests the runner itself.

This spec covers defects the bats suite can see on macOS. Defects that only appear when
`setup_env.sh` runs for real on a provisioned mac are a separate problem with a separate
instrument, and are out of scope here (see Out of scope).

## Prior decision

ADR-0008 moved `bash-coverage` from `macos-latest` to `ubuntu-latest` because macOS
runners queued for 30 to 60 minutes. That no longer holds. Measured 2026-10-02 over the
last 40 successful `ci.yml` runs: `lint-macos` queued for a median of 8s and a maximum of
12s. No spec or ADR in this repo has proposed and rejected running the test suite on
macOS.

## Design

### 1. A `test-macos` job

A new job in `.github/workflows/ci.yml`, `runs-on: macos-latest`, that runs `make test`.
`auto-merge` has no `always()`, so adding a job to its `needs:` makes it blocking with
nothing else to change. The job is added to `needs:` only after the determinism check in
Order of work passes.

Tool installs:

| tool         | source                                                                         | pinned                              |
| ------------ | ------------------------------------------------------------------------------ | ----------------------------------- |
| bash 5       | `brew install bash`                                                            | no                                  |
| bats         | `brew install bats-core`                                                       | no                                  |
| GNU parallel | `brew install parallel`                                                        | no                                  |
| shellcheck   | release tarball `shellcheck-v0.11.0.darwin.aarch64.tar.xz`, `shasum -a 256 -c` | yes, same version as the `test` job |
| uv           | release tarball `uv-aarch64-apple-darwin.tar.gz`, `shasum -a 256 -c`           | yes, same version as the `test` job |

The job prints `bash --version`, `bats --version`, `make --version` and
`parallel --version` before the suite, so a red run caused by a Homebrew upgrade can be
told from one caused by the PR. Homebrew does not offer version pins for these three.
The `test` job's `apt-get install bats` is unpinned in the same way.

The job uses the system `make` (GNU Make 3.81). Run B shows the suite gives the same
result under 3.81 as under 4.4.1. Using 3.81 here covers the one `make` version that
`ubuntu-latest` (4.3) and the development machines (4.4.1) do not.

`make test` runs with stdin from `/dev/null` and its output is written to a file, so the
exit status is `make`'s own. **The job then prints every `not ok` line and its diagnostic
block to the job log**, whether or not `make` failed. Development happens on Linux, so
the job log is the only place the author sees a macOS failure, and
`gh run view --log-failed` must show the failing test, not only a count.

`timeout-minutes: 30` to start. The job's duration on a 3-vCPU arm64 runner is not
known: the Studio took 199s on 20 cores and `ubuntu-latest` takes a median of 382s on
2 vCPUs. After five green runs the cap is re-sized to about three times the measured p90,
which is how the other caps in this file were set.

**The job also checks that the suite ran.** After `make test` it compares two counts and
fails unless they are equal and the declared count is greater than zero:

- executed: lines in the saved output matching `^(ok|not ok) `. The match is anchored
  because lint prints `bash -n OK` and the Python suite prints `OK`. A skipped test
  prints as `ok`, so skips do not break the equality.
- declared: `@test` declarations under `tests/`.

Without this, a job that ran zero tests would pass. The existing floor check in the
`test` job counts declarations, not executions, so it cannot see this.

### 2. Tests stop inheriting the platform

`load_setup_env` does not run `detect_env`, so `MACOS`, `LINUX`, `UBUNTU` and every
`HAS_*` hold whatever the parent shell exported. That is the cause of five of the six
failures.

`tests/helpers/common.bash` will unset `MACOS`, `LINUX`, `UBUNTU`, `NOBLE`, `RESOLUTE`,
`PROFILE` and every `HAS_*` variable when it is sourced. Most bats files source it, at
file top level (`git grep -l common.bash -- 'tests/*.bats'` lists them). The rest are
left alone: a grep of `tests/` found no
test that relies on an inherited platform variable. A test that needs a platform sets
it, as `CLAUDE.md`'s Testing Rules already require.

The five tests that run a real `stat` or `date` (1667, 1668, 1698, 1700, 1702) will set
the platform from `uname -s` in the test body, because they run the real tool and the
real tool is decided by the machine. No new helper is needed: 1698 and 1700 already
carry both `date` forms.

### 3. Fix 1266

Diagnose on macOS first, then fix whichever of the test or the code is wrong. The cause
is unknown, so the size of this fix is unknown. If the fix needs a change to production
behaviour in `_install_ubuntu_edge_source`, that is reported to the operator before it is
made.

### Order of work

1. The `test-macos` job lands first in the PR, outside `needs:`, before any fix. Its
   first run is expected to be red with the six failures above. A different set is a
   finding: it is reported before any fix, because it means the fix scope here is wrong.
2. That red run is re-run four more times. The five `not ok` sets must be identical. A
   blocking gate that flakes gets bypassed, and `CLAUDE.md` records tests that are
   sensitive to `bats --jobs`. If the sets differ, the flaky tests are fixed or the job
   runs `make test HAVE_PARALLEL=` before it becomes a gate.
3. The fixes follow, one behaviour per commit, until the job is green.
4. The job is added to `auto-merge`'s `needs:`.

### Reproducing a macOS failure from Linux

A throwaway clone on the Studio over `ssh`, which is how this spec's measurements were
taken:

```bash
ssh studio 'cd /tmp/<clone> && env -i HOME="$(mktemp -d)" \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  bats tests/<file>.bats' < /dev/null
```

This goes into `CLAUDE.md`'s CI section with the job description. Without it every macOS
fix costs a push and a wait.

## Verification

| check                                                                                                            | expected                                                            |
| ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| First CI run, job added, no fixes                                                                                | `test-macos` red; the `not ok` set is the six named above           |
| Four re-runs of that job                                                                                         | the same `not ok` set each time                                     |
| Executed-count check, bats step replaced by a no-op on a scratch commit                                          | red, naming 0 executed against 2161 declared                        |
| Executed-count check, declared-count path broken on a scratch commit                                             | red, naming a declared count of 0                                   |
| Hostile inheritance before the helper change: `MACOS=1` exported on `claude`, the five tests' files              | red                                                                 |
| Hostile inheritance after: `MACOS=1` exported on `claude`; `LINUX=1 UBUNTU=1` exported on the Studio; full suite | rc 0 on both, `ok` count 2161 on `claude`                           |
| After the fixes                                                                                                  | `test-macos` green; executed equals declared                        |
| `make test` on `claude` after the fixes                                                                          | rc 0, 2161 `ok`                                                     |
| Run B repeated on the Studio after the fixes                                                                     | rc 0, 2161 `ok`, 12 of them skips                                   |
| A red `test-macos` run read with `gh run view --log-failed`                                                      | the failing test names and their diagnostic lines are in the output |

2161 is the count at `af2d024`. The checks compare against the declared count at the
commit under test, not against this number.

## Documentation

- `CLAUDE.md` CI section: add `test-macos`, its `needs:` membership, its timeout, and the
  reproduction command above. Correct "All jobs run on `ubuntu-latest`".
- A new ADR recording that the macOS suite gates merge, and that ADR-0008's queue-time
  reason no longer holds for this job.
- `docs/superpowers/README.md`: index row for this spec.

## Out of scope

- **Real-run defects on a provisioned mac.** A hosted runner is not a provisioned mac:
  it has no profile, no `config/local.sh`, no pyenv and no symlinked dotfiles. Running
  `setup_env.sh -t doctor` on the Studio over `ssh` is the likely instrument, and an open
  backlog row already records that it cannot run that way today because `sshd` resolves
  bash 3.2. Tracked as its own backlog row.
- **bash coverage on macOS.** ADR-0008 established the tracer has no macOS-specific
  behaviour.
- **Intel macs and bash 3.2.** No development machine is Intel, and `setup_env.sh`
  refuses bash 3.2.
- **Running the macOS suite from the pre-push hook over `ssh`.** It would double every
  push and fail whenever the Studio is down.
- **Tests that skip on Darwin.** The GNU `ar` verifier tests skip on macOS by design.
  12 tests skip there today. The job does not print or gate on the count: nothing
  would read it.

## Multi-Lens Review

Reviewed at commit: `64ca3b07` (Step 7 self-review commit, before Step 8 dispatch).
Every reference in this section, to a test number, a row or a section, is to the spec
as it stood at that commit. The body above was revised at `fbd29d35` in response.

### Goal-Fit

Finding: Worth building and close to the minimum. (1) The cause table misdiagnosed 1698
and 1700: `tests/setup_env/unit.bats:2237` already branches on `MACOS`, so they fail for
the same inherited-variable reason as 1667, 1668 and 1702, and the proposed date helper
is unnecessary. (2) The evidence for code regressing on macOS is one undiagnosed test
(1266); the other five are a harness artefact. The Problem section should say so. Also:
the skip-count print has no reader.
Assumption: The suite is deterministic on a 3-vCPU runner at `JOBS=24`. Re-run the first
red job five times and compare the `not ok` sets before the job enters `needs:`.
Disposition:

### Ergonomics

Finding: (1) No Verification row can fail if the `common.bash` unset is a no-op. Missing:
a hostile-inheritance control, the wrong platform exported, red before the change and
rc 0 after. (2) The diagnosis path from Linux is unspecified: the job saves `make test`
output to a file and never says it prints it, and the reproduction loop on the Studio is
not named.
Assumption: A hosted runner reproduces the Studio's six failures and only those. The
first CI run with the job added and no fixes settles it.
Disposition:

### Risk

Finding: No blocking flaw. (1) The six failures were measured under GNU Make 4.4.1 and
the job uses 3.81; four bats files run real `make`. (2) The executed-count check has no
guard on the declared side, so 0 equals 0 passes; it also needs an anchored match.
Assumption: The Studio measurement predicts the runner. Run the suite on the Studio under
`env -i`, an empty `HOME` and system make, and compare the `not ok` set to the six.
Checked after the review: same six, 2155 ok (run B in Problem). The runner-image half
stays open until the first CI run.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
