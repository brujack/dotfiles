# macOS test gate

**Date:** 2026-10-02
**Status:** Draft, awaiting operator review

## Problem

No test in this repo executes on macOS. `ci.yml`'s `test` and `bash-coverage` jobs run
on `ubuntu-latest`. `lint-macos` runs on `macos-latest` but only does `bash -n` and
`zsh -n`. Until 2026-09-19 the gap was covered by accident: the dotfiles session ran on
the Mac Studio, so the pre-push hook ran `make test` on macOS on every push. The session
then moved to the Linux `claude` box and that cover went with it.

The suite is now red on macOS. Measured 2026-10-02 on the Mac Studio (Darwin arm64,
macOS 27.0.1), from a throwaway clone of `origin/master` at `af2d024`, over a
non-interactive `ssh` shell with Homebrew's gnubin `make` on `PATH` (bash 5.3.20, GNU
Make 4.4.1, bats 1.14.0):

```
2155 ok, 6 not ok, make test rc=2
```

| test                                                 | cause                                                                                                                  |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 1698, 1700 `_doctor_check_github_mcp`                | the test body calls `date -d "+5 days"`; BSD `date` has no `-d`                                                        |
| 1667, 1668 `_doctor_check_cred_dirs real`            | `lib/helpers.sh:681`'s `stat -c` branch runs because the test inherits `MACOS` from its parent shell, and it was unset |
| 1702 `_doctor_check_github_mcp ... expired`          | same inheritance; `lib/helpers.sh:895`'s `date -d` branch runs                                                         |
| 1266 `_install_ubuntu_edge_source ... truncated key` | the expected warning is absent; cause not diagnosed. Added by #304 on 2026-10-02                                       |

**Boundary of that measurement.** `MACOS` was unset because the shell was
non-interactive. Three of the six (1667, 1668, 1702) depend on that, so an interactive
shell on a mac, which exports `MACOS=1`, probably shows three failures, not six. That was
not measured. A `macos-latest` runner also has `MACOS` unset, so it is expected to show
the same six. That is a prediction and the first CI run of this change tests it.

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

A new job in `.github/workflows/ci.yml`, `runs-on: macos-latest`, that runs `make test`
and is added to `auto-merge`'s `needs:`. `auto-merge` has no `always()`, so adding the
job to `needs:` makes it blocking with nothing else to change.

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
told from one caused by the PR. Homebrew does not offer version pins for these three, and
they are test runners, not gates whose output is the verdict. shellcheck and uv are
pinned because their output is the verdict.

The job uses the system `make` (GNU Make 3.81). `lint-macos` already parses this
Makefile under 3.81. Using it here covers the one `make` version that `ubuntu-latest`
(4.3) and the development machines (4.4.1) do not.

`make test` runs with stdin from `/dev/null` and its output is written to a file, so the
exit status is `make`'s own and the failing lines are kept.

`timeout-minutes: 30` to start. The job's duration on a 3-vCPU arm64 runner is not
known: the Studio took 199s on 20 cores and `ubuntu-latest` takes a median of 382s on
2 vCPUs. After five green runs the cap is re-sized to about three times the measured p90,
which is how the other caps in this file were set.

**The job also checks that the suite ran.** After `make test` it counts the `ok` and
`not ok` lines in the saved output and fails unless that count equals the number of
`@test` declarations under `tests/`. Without this, a job that ran zero tests would pass.
The existing floor check in the `test` job counts declarations, not executions, so it
cannot see this.

### 2. Tests stop inheriting the platform

`load_setup_env` does not run `detect_env`, so `MACOS`, `LINUX`, `UBUNTU` and every
`HAS_*` hold whatever the parent shell exported. That makes one test file give different
results in an interactive mac shell, an `ssh` command, and a CI runner.

`tests/helpers/common.bash` will unset `MACOS`, `LINUX`, `UBUNTU`, `NOBLE`, `RESOLUTE`,
`PROFILE` and every `HAS_*` variable when a test file loads it. A test that needs a
platform sets it, as `CLAUDE.md`'s Testing Rules already require. This is safe by
measurement in both directions: `ubuntu-latest` already runs with all of them unset and
is green, and the Studio run above had them unset and passed 2155 tests.

The three tests that exercise a real `stat` or `date` (1667, 1668, 1702) will set the
platform from `uname -s` in the test body, because they run the real tool and the real
tool is decided by the machine.

### 3. Fix the remaining three

- **1698, 1700:** a helper in `tests/helpers/` returns a date N days from now, using
  `date -v` on Darwin and `date -d` elsewhere. Both tests call it.
- **1266:** diagnose on macOS first, then fix whichever of the test or the code is wrong.
  The cause is unknown, so the size of this fix is unknown. If the fix needs a change to
  production behaviour in `_install_ubuntu_edge_source`, that is reported before it is
  made.

### Order of work

The `test-macos` job lands first in the PR, before any fix. Its first CI run is expected
to be red with the six failures above. That run is the evidence that the gate can fail,
and it tests the prediction that the runner matches the Studio measurement. The fixes
follow, one behaviour per commit, until the job is green.

## Verification

| check                                                                                | expected                                                                                                                 |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| First CI run, job added, no fixes                                                    | `test-macos` red; the failing tests are the six named above. A different set is a finding and is reported before any fix |
| Same run                                                                             | `auto-merge` did not run                                                                                                 |
| Executed-count check, with the bats step replaced by a no-op on a scratch commit     | red, naming 0 executed against the declared count                                                                        |
| After the fixes                                                                      | `test-macos` green; executed count equals declared count                                                                 |
| `make test` on `claude` (Linux) after the fixes                                      | rc 0, same `ok` count as before the change                                                                               |
| `make test` on the Studio after the fixes, non-interactive shell                     | rc 0                                                                                                                     |
| `make test` on the Studio after the fixes, interactive shell with `MACOS=1` exported | rc 0. This is the case the helper change exists for                                                                      |

## Documentation

- `CLAUDE.md` CI section: add `test-macos`, its `needs:` membership and its timeout.
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
  The job prints the skip count and does not gate on it.
