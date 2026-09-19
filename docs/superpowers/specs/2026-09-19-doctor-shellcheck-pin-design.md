# lint's shellcheck install hint names the pinned path on Linux

**Status:** Approved 2026-09-19 (descoped, see "Decision")
**Closes backlog rows:** "the pinned shellcheck is outranked by linuxbrew on both Linux boxes' PATH",
"`run_check_versions` checks the shellcheck on PATH, not the one the pin manages",
"doctor arm: the RESOLVED shellcheck must match `SHELLCHECK_VER`"

## Problem, as measured

The three rows assume a linuxbrew `shellcheck` can sit ahead of the pinned
`/usr/local/bin/shellcheck` and make the lint gate run an unmanaged copy. Measured
2026-09-19, the hazard is hypothetical:

- **The copies removed on 2026-09-18 were apt copies at `/usr/bin`**, per the #285 commit
  and PR body: workstation 0.9.0, `claude` 0.11.0. `/usr/bin` is at PATH position 11 on both
  Linux boxes, behind `/usr/local/bin` at 9, so an apt copy cannot outrank the pin.
  terraform_ansible's `common` role still lists apt `shellcheck`, which is harmless for the
  same reason.
- **linuxbrew holds no shellcheck** on `claude` or `workstation`: none in the Cellar, and
  `brew uses --installed --recursive shellcheck` returns nothing on either box. Nothing in
  this repo installs one there.
- **The one realistic source is this repo's own advice.** When shellcheck is absent,
  `make lint` prints `shellcheck not found, skipping (install: brew install shellcheck)`
  (`Makefile:105`) on every platform. On Linux, following it creates exactly the linuxbrew
  copy the rows worry about. The pinned path is `setup_env.sh -t developer`, which reaches
  `_install_ubuntu_shellcheck` through `install_ubuntu_packages` → `_install_ubuntu_misc`.

## Decision

Operator, 2026-09-19, after two Step 8 rounds: **descope to the hint fix.** Both rounds'
corrections kept adding mechanism: the check moved from `doctor` to `make lint`, then needed
path branching, then a separate stale-pin case to avoid locking out Linux commits after any
`SHELLCHECK_VER` bump. All of that guards a hazard that nothing currently creates. The
review history below records the full check's design and its defects, so it can be revived
if a linuxbrew copy ever appears.

## Design

`Makefile:105`'s skip branch names the platform's real install path:

| platform | hint |
|---|---|
| Darwin | `install: brew install shellcheck` (unchanged; `Brewfile:108` is the source there) |
| anything else | `install: ./setup_env.sh -t developer on Ubuntu (installs the pinned SHELLCHECK_VER)` |

The "on Ubuntu" qualifier is load-bearing. `_install_ubuntu_shellcheck` runs only when
`UBUNTU` and `HAS_DEVTOOLS` are both set, so on another Linux distribution, or an unmapped
host, `-t developer` installs nothing. Every Linux box in today's fleet meets both conditions.

The platform comes from `$${_OVERRIDE_PLATFORM:-$$(uname -s)}` in the recipe. A make recipe
has no `MACOS`/`LINUX` in its environment. The override exists so one machine can test both
branches, and it grants nothing beyond changing a printed string.

## Rows closed

All three close on the measurements above: the outranking hazard has no current source, and
the fix removes the one source this repo provided. `run_check_versions` reading the PATH copy
is correct whenever that copy is the pin, which is the only state the fleet reaches.

## Testing

In `tests/scripts/makefile_lint_scope.bats`, beside the existing lint tests. Each case runs
`env PATH="${CLEAN_PATH}" make --no-print-directory -C <repo> lint SHELLCHECK=`, the same
mock-stripped `PATH` the file's other real-lint cases use, so the `git` and `make` mocks
cannot shadow the real tools. Overriding the variable to empty on
the command line takes the skip branch on any machine, including ones that have
shellcheck, and the guarded form keeps the case inside the MAKEFLAGS stdout partition.

| # | case | expected |
|---|---|---|
| 1 | `_OVERRIDE_PLATFORM=Linux` | output contains `shellcheck not found, skipping` and `setup_env.sh -t developer`; does **not** contain `brew install shellcheck` |
| 2 | `_OVERRIDE_PLATFORM=Darwin` | output contains `brew install shellcheck`; does not contain `setup_env.sh -t developer` |

Each case asserts both presence and absence, so neither passes on the other branch's text or
on an unconditional message. Mutations that must go red: swapping the two hints (both
cases), and printing one hint unconditionally (the other case).

## Verification

- `make test` green; both cases pass; both mutations go red.
- On `claude`: `make lint SHELLCHECK=` prints the `-t developer` hint.

## Out of scope

- The resolved-shellcheck version or path check, in `doctor` or `make lint`. Considered over
  two review rounds and not built; see Decision and the review history.
- Failing lint on Linux when shellcheck is absent.
- Pinning shellcheck on macOS.

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
Disposition: (1) and (2) Addressed (operator, 2026-09-19): the script parses with bash regex and calls no external tool except the binary, so test PATH no longer matters; the remedy is corrected. (4) is moot, because lint does not run on a mac_mini. (3) Accepted (operator, 2026-09-19): out of scope for this change, with a backlog row to consider failing on Linux once the pin is expected to be present.

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

### Round 2

Reviewed at commit: `864b1976` (the check moved into `make lint`). The round-1 blocks above are
history.

**Goal-Fit.** Finding: lint's own skip hint (`install: brew install shellcheck`) is the only
realistic way a linuxbrew copy gets created on Linux, so the mismatch message and the skip
message would give opposite advice. A version check also lets a linuxbrew copy at 0.11.0
pass, so the "outranked pin" row would not really close. Case 5 did not assert its warning
text. Assumption: that a linuxbrew shellcheck will come back at all. Checked 2026-09-19: the
removed copies were apt at `/usr/bin`, and linuxbrew has no shellcheck and no dependents on
either box. Disposition: Addressed (operator, 2026-09-19): descoped to the hint fix.

**Ergonomics.** Finding: after any `SHELLCHECK_VER` bump, the pinned `/usr/local/bin` copy is
stale, so every Linux commit fails lint (the bump commit included) until re-provisioning. The
remedy then printed would point at brew for the pinned copy. The macOS warning on every
commit trains people to ignore lint output. Assumption: brew's shellcheck stays at 0.11.0 for
months. Disposition: Addressed (operator, 2026-09-19): the check is not built, so neither
the lockout nor the per-commit warning exists.

**Risk.** Finding: the same stale-pinned-copy remedy defect, independently found; case 5
lacked content and absence assertions. Checked with no problem found: no lint lockout for the
commit that fixes the script, `make VAR=` is the only override that works (`:=` beats an
exported variable), and case 7 costs less than the existing real-`make lint` test.
Assumption: no uncertain assumption found. Disposition: Addressed (operator, 2026-09-19):
descoped.

### Round 3 (scoped)

Reviewed at commit: `3ae53ad7`, one risk lens on the descoped sections only. Finding: no
blocking issues. Two wording gaps: the tests must use the file's `CLEAN_PATH`, and the Linux
hint holds only where `UBUNTU` and `HAS_DEVTOOLS` are set. Checked clean: `SHELLCHECK=` takes
the skip branch (`Makefile:98` tests `$(SHELLCHECK)`), each case asserts presence and absence,
and the apt claim matches `eccf7a1a`. Assumption: no uncertain assumption found. Disposition:
Addressed. Both are wording fixes applied in the commit after `3ae53ad7`, which is why there
is no re-review.

