# lint: the shellcheck it runs must match SHELLCHECK_VER

**Status:** Spec
**Closes backlog rows:** "the pinned shellcheck is outranked by linuxbrew on both Linux boxes' PATH",
"`run_check_versions` checks the shellcheck on PATH, not the one the pin manages",
"doctor arm: the RESOLVED shellcheck must match `SHELLCHECK_VER`"

## Problem

`make lint` runs whichever `shellcheck` the invoking shell resolves first
(`Makefile:12`, `SHELLCHECK := $(shell command -v shellcheck)`). The repo pins it only on
Linux: `_install_ubuntu_shellcheck` installs `SHELLCHECK_VER` (0.11.0) into
`/usr/local/bin`. On `claude`, `/home/linuxbrew/.linuxbrew/bin` is at PATH position 5 and
`/usr/local/bin` at position 9, so a `brew install shellcheck` would silently put an
unmanaged copy in front of the pin, and the lint gate would run it. Competing copies were
removed by hand on 2026-09-18, so nothing stops a recurrence and nothing would report one.

On macOS, shellcheck comes from `Brewfile:108` (`brew "shellcheck"  # [HAS_DEVTOOLS]`),
which is unpinned. It matches CI's pinned 0.11.0 today only because brew's current release
is also 0.11.0.

Premise verified 2026-09-19 with `command grep -n shellcheck lib/helpers.sh`: `run_doctor`
has no shellcheck check, and every hit in `lib/helpers.sh` is a directive comment. Resolved
copies measured the same day from an interactive zsh: Studio `/opt/homebrew/bin/shellcheck`
0.11.0; `claude` and `workstation` `/usr/local/bin/shellcheck` 0.11.0, with neither
`/home/linuxbrew/.linuxbrew/bin/shellcheck` nor `/usr/bin/shellcheck` present. So on all
three development machines, a check added today passes.

## Design

**Revised after Step 8 round 1.** The first version added the check to `doctor`. The goal-fit
lens showed that nothing runs `doctor` on a schedule, so the check fired only when someone
remembered to run it, and the macOS WARN persisted nowhere. The check now lives in the lint
gate itself (operator decision, 2026-09-19). `doctor` is unchanged.

**Where.** A new `scripts/check-shellcheck-pin.sh BINARY` compares the version `BINARY`
reports with `SHELLCHECK_VER`, read from `lib/constants.sh`. `make lint` calls it first
inside its existing `if [ -n "$(SHELLCHECK)" ]` block, and adds `failed=1` on a non-zero exit, so
the rest of lint still runs and reports. It follows the pattern of the
`scripts/check-lib-exit-traps.sh` call a few lines below: guarded by `[ -f ... ]` with a
restore hint when the script is missing.

**The checked binary is the binary run.** The recipe today resolves `$(SHELLCHECK)` (parse
time, `command -v`) for its presence test, then runs a bare `shellcheck`, which the recipe
shell resolves again. Both runs of it change to `"$(SHELLCHECK)"`, so the verdict is about the
copy that lints. It also gives tests a seam: `make lint SHELLCHECK=<stub>`.

**Verdicts.**

| case | Linux | macOS |
|---|---|---|
| reported version prefix-matches the pin | prints `shellcheck pin OK (<ver>) — <path>`, exit 0 | same |
| mismatch | exit 1: `shellcheck <ver> at <path> does not match SHELLCHECK_VER <pin>`, plus the remedy: remove the competing copy (`brew uninstall shellcheck`); the pinned copy is `/usr/local/bin/shellcheck` | exit 0, with a warning line naming path, installed version and CI's pin: macOS shellcheck is brew-managed and unpinned (operator decision) |
| version cannot be parsed from the output | exit 1, fail closed: the gate cannot say which tool it is running | exit 0 with a warning |
| pin cannot be read from `lib/constants.sh` | exit 1 on both: the repo itself is misconfigured | exit 1 |

Platform comes from `uname -s`. The `MACOS`/`LINUX` variables are not in a make recipe's
environment. Test seam: `_OVERRIDE_PLATFORM` (`Darwin` or `Linux`). The constants path has
a seam too, `_OVERRIDE_CONSTANTS`, so the unreadable-pin branch is reachable. Neither grants
anything beyond editing the script's inputs directly.

Parsing uses bash regex only: `version: X.Y.Z` from the binary's output, and
`SHELLCHECK_VER="X.Y.Z"` from the constants file. The script calls no external tool except
the binary it checks, so a test's `PATH` cannot change its verdict. That is the defect all
three lenses found in the doctor version's harness.

Absent shellcheck is not this script's case. Lint already prints
`shellcheck not found, skipping` and never calls it. Making a missing tool fail on Linux is
a separate decision and out of scope.

**Actor.** `$(SHELLCHECK)` is resolved by the make process that the pre-commit or pre-push
hook started, which inherits whoever invoked git. The check therefore answers for the actor
that actually runs the gate, including editor and cron invocations that the doctor version
could not see.

**CI.** The `test` job runs `make test`, which runs lint. It resolves the pinned
`/usr/local/bin/shellcheck` it installed, so the check passes there. `lint-macos` runs no
shellcheck. `tests/setup_env/shellcheck_pin.bats` already ties `SHELLCHECK_VER` to CI's
`SC_VER`.

## Rows closed

- **Outranked pin**: a linuxbrew copy ahead of the pin now fails lint on the next commit or
  push, naming the copy and how to remove it.
- **`run_check_versions` reads PATH**: it reports on the copy lint now requires to be the
  pin, so on Linux the two cannot silently diverge. No change to `run_check_versions`.
- **Doctor arm**: superseded by the lint check, per the round-1 goal-fit finding.

## Testing

A new `tests/scripts/check_shellcheck_pin.bats` drives the script directly. The binary is a
`#!/bin/sh` stub passed by absolute path, printing `version: X`. The pin is read from the
real `lib/constants.sh` except in case 6. `_OVERRIDE_PLATFORM` is set in every case.

| # | case | expected |
|---|---|---|
| 1 | Linux, stub prints the pin | exit 0; output contains `shellcheck pin OK` and the stub's path |
| 2 | **negative control**: Linux, stub prints 0.10.0 | exit 1; output names the stub's path, `0.10.0`, the pin and `brew uninstall shellcheck` |
| 3 | Darwin, stub prints 0.12.0 | exit 0; output contains a warning naming the path, `0.12.0` and the pin; does not contain `shellcheck pin OK` |
| 4 | Linux, stub prints no version | exit 1; says the version could not be parsed |
| 5 | Darwin, stub prints no version | exit 0 with a warning |
| 6 | `_OVERRIDE_CONSTANTS` points at a file with no `SHELLCHECK_VER` | exit 1 on both platforms |
| 7 | **wiring**: `make --no-print-directory -C <repo> lint SHELLCHECK=<stub 0.10.0>`, `_OVERRIDE_PLATFORM=Linux` | non-zero, and output contains the mismatch line. The stub exits 0 for lint's own invocations |

Case 2 is the one the backlog row demands: the check passes on every development machine
today, so without a competing copy present it would ship untested against the only failure
it exists to catch. Case 7 proves the Makefile calls the script and acts on its exit. The
guarded `--no-print-directory` form keeps it inside the MAKEFLAGS stdout partition that
`tests/scripts/makefile_lint_scope.bats` enforces.

Mutations, all part of verification:

- delete the script call from the lint recipe: case 7 goes red;
- make the mismatch branch exit 0 on Linux: cases 2 and 7 go red;
- make the macOS mismatch exit 1: case 3 goes red;
- make an unparseable version exit 0 on Linux: case 4 goes red;
- revert the recipe's `"$(SHELLCHECK)"` to a bare `shellcheck`: case 7 still goes red on the
  mismatch message, but the lint run it reports on uses a different binary. This is a
  readability check on the diff, not a test.

## Verification

- `make test` green; the seven cases above pass; the four test mutations go red.
- On `claude` and `workstation`: `make lint` prints `shellcheck pin OK (0.11.0) —
  /usr/local/bin/shellcheck`.
- On the Studio: the same line with `/opt/homebrew/bin/shellcheck` today; a warning, not a
  failure, the day brew moves past 0.11.0.

## Out of scope

- Pinning shellcheck on macOS (`brew pin`, or a pinned download). The Mac verdict is a
  warning by decision; revisit if Mac-vs-CI lint skew ever costs a red CI run.
- Failing lint on Linux when shellcheck is absent.
- A `doctor` arm. Superseded, see Design.
- Lint checks for the `tflint`/`tfsec` pins, which have their own backlog row.

## Multi-Lens Review

Reviewed at commit: `7cbc04b5` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The Linux arm is worth having, but `doctor` is the wrong consumer. Its only caller
is a manual `setup_env.sh -t doctor`, and nothing schedules or stores it, so "nothing would
report one" stays true until someone thinks to run it. The macOS WARN moves no exit code and
persists nowhere, so it fails the reads-it test. A simpler path with more value: compare
`$(SHELLCHECK) --version` against `SHELLCHECK_VER` inside `make lint`, where the gate
actually decides. That runs on every commit and push, as whichever actor invoked git.
Separately, the Linux remedy is wrong: `-t developer` reinstalls into `/usr/local/bin`,
which a competing copy still outranks. All five cases fail on empty output, so none passes
vacuously.
Assumption: the removed competing copies were a one-off. Checked 2026-09-19:
terraform_ansible's `common` role does list apt `shellcheck`, but `/usr/bin` is at PATH
position 11 on both Linux boxes, behind `/usr/local/bin` at 9, so an apt copy cannot
outrank the pin. Only linuxbrew (positions 5–6) can. Neither box has the apt package
installed.
Disposition: Addressed (operator, 2026-09-19): the check moved from `doctor` into `make lint` via `scripts/check-shellcheck-pin.sh`; the remedy text now names `brew uninstall shellcheck`.

### Ergonomics

Finding: (1) Test 3 cannot hold as written. The spec's test PATH includes `/usr/bin`, so the
real python3 (Studio 3.9.6, ubuntu-latest 3.12) fails its pin and sets `_DOCTOR_FAILED`. The
existing real tests leave `/usr/bin` out for this reason; shim only `grep` and `head`.
(2) The Linux remedy should say `brew uninstall shellcheck`, not `-t developer`. (3) A
missing pin on Linux, where `make lint` skips shellcheck entirely, is reported only through
an uncounted `log_warn`, which is weaker than a mismatch. (4) mac_mini installs brew
shellcheck anyway, since the Brewfile tag doesn't gate installs, so it gets the Mac WARN too.
Assumption: the Mac WARN will be rare and brief rather than a standing warning. Settled by
comparing brew shellcheck release dates against `git log -S 'SHELLCHECK_VER='
lib/constants.sh`.
Disposition: (1) and (2) Addressed (operator, 2026-09-19): the script parses with bash regex and calls no external tool except the binary, so test PATH no longer matters; the remedy is corrected. (4) is moot, because lint does not run on a mac_mini. (3) is pending operator: the spec now lists "fail lint when shellcheck is absent on Linux" as out of scope.

### Risk

Finding: (1) The same test-PATH defect as Ergonomics (1). `_doctor_check_one_version` is
nested, so every test runs all of `_doctor_check_versions`; go, python3, ruby and zsh must be
stubbed or hidden in every case that asserts a counter. (2) Test 1 could pass on the wrong
verdict, because the parse-failure message also names the path; assert `[PASS]` or the
`_DOCTOR_PASS` increment. (3) The same wrong `-t developer` remedy. Checked with no problem
found: the optional fifth argument is safe (4 callers), and the run_doctor end-to-end tests
stub `_doctor_check_versions` by name.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-09-19): the harness no longer depends on PATH; case 1 asserts `shellcheck pin OK`; the remedy is corrected.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
