# Doctor check: every jscpd a box can resolve matches the pin

**Date:** 2026-11-24
**Status:** Retired 2026-11-24 by the operator after Step 8, before approval. Nothing was built; see Multi-Lens Review.
**Source:** operator decision 2026-11-24 on the jscpd drift Backlog row (becccf41), relayed
from ai-config's sub-project 1 spec (`2026-11-24-machine-written-dod-records-design.md`, N9).

## Problem

ai-config's maintainability duplication rule (JSCPD001) is becoming a blocking pre-push gate,
so its verdict must not depend on which jscpd a box happens to resolve. dotfiles pins
`JSCPD_VER` (`lib/constants.sh`, 5.4.1) and installs it with `npm install -g` from
`run_developer_or_ansible` and the `-t update` npm section, through whichever `npm` is first on
PATH.

Measured 2026-11-24:

| box           | copies of `jscpd`                                                                              | version |
| ------------- | ---------------------------------------------------------------------------------------------- | ------- |
| `workstation` | `/home/linuxbrew/.linuxbrew/bin/jscpd`                                                         | 5.4.1   |
| `workstation` | `/usr/local/bin/jscpd` (system npm, `/usr/bin/npm`, prefix `/usr/local`, installed 2026-08-14) | 5.0.14  |
| `claude`      | `/home/linuxbrew/.linuxbrew/bin/jscpd` (no `/usr/local/lib/node_modules`)                      | 5.4.1   |
| Studio        | `/opt/homebrew/bin/jscpd` (no `/usr/local/lib/node_modules`)                                   | 5.4.1   |

Interactive zsh on `workstation` resolved the Linuxbrew copy, and a non-interactive
`ssh workstation` resolved the stale one. The stale copy was removed on 2026-11-24 with
`sudo -n /usr/bin/npm uninstall -g jscpd` at the operator's instruction. Nothing reported it in
the three months it existed.

Nothing in `-t doctor` reads jscpd today. `_doctor_check_dev_tools` checks presence only, for
`pwsh tflint zig terraform tfsec`, on Linux with `HAS_DEVTOOLS`. `_doctor_check_versions`
checks only the first binary `command -v` returns. Doctor runs from an interactive PATH where
Linuxbrew comes first, so a first-on-PATH check would have passed on `workstation` while the
stale copy existed. The check therefore has to examine every copy, not only the one doctor's
own PATH picks.

ai-config resolves jscpd for its gate as PATH, then `/home/linuxbrew/.linuxbrew/bin`, then
`/opt/homebrew/bin`, then `/usr/local/bin`, with no override variable. This check examines the
same candidate set, so any copy the gate could pick is covered.

## Design

A new doctor arm, `_doctor_check_jscpd` in `lib/helpers.sh`, called from `run_doctor`
immediately after `_doctor_check_versions`.

1. **Gate.** Returns 0 with no output unless `HAS_DEVTOOLS` is set. It runs on macOS and Linux
   alike: jscpd is a gate dependency on every development box.
2. **Section header.** Prints `\njscpd:\n`.
3. **Candidates.** Every `jscpd` on PATH (`type -ap jscpd`, files only), then
   `<prefix>/jscpd` for each prefix in `_DOCTOR_JSCPD_PREFIXES`, which defaults to
   `/home/linuxbrew/.linuxbrew/bin /opt/homebrew/bin /usr/local/bin`. A candidate counts only
   when it is an executable file. Candidates that resolve to the same file
   (`readlink -f`) are examined once, under the first path that reached them.
4. **None found.** `doctor_warn "jscpd" "not found — setup_env.sh -t developer"`.
5. **Per candidate.** Run `<path> --version` with stdin from `/dev/null`, bounded by the
   existing `_doctor_resolve_timeout` and `_DOCTOR_PROBE_TIMEOUT` (default 10 s), unbounded when
   no timeout binary resolves, as in `_doctor_check_dev_tools`. Take the first match of
   `[0-9]+\.[0-9]+\.[0-9]+` in its combined output.
   - Matches `JSCPD_VER` exactly: `doctor_pass "jscpd ${JSCPD_VER} — <path>"`.
   - Any other version: `doctor_fail "jscpd" "<path> reports <version>, pinned ${JSCPD_VER} — <remedy>"`.
   - Non-zero exit, timeout, or no version in the output:
     `doctor_fail "jscpd" "<path> does not report a version (rc <rc>) — <remedy>"`.
6. **Remedy.** The managed prefix is the output of `npm prefix -g` for the `npm` on PATH (empty
   when `npm` is absent or fails). A candidate whose directory is `<managed prefix>/bin` gets
   `setup_env.sh -t update`. Every other candidate gets
   `remove it: npm --prefix <dir of candidate>/.. uninstall -g jscpd`, prefixed with `sudo ` when
   `<dir of candidate>/../lib/node_modules` is not writable by the current user.

The arm never installs, removes or rewrites anything; the remedy text is for the operator.

A FAIL makes `-t doctor` exit non-zero, as the existing version-drift FAILs do. A mismatched copy
fails even when interactive PATH never reaches it (operator decision, 2026-11-24): the gate's
fallback order can reach it, and a bare-PATH actor resolves it first.

## Testing

`tests/setup_env/doctor_jscpd.bats` (added to `tests/bats-files.txt`), with stub `jscpd` scripts
in fixture directories under `BATS_TEST_TMPDIR`, a fixture PATH, and `_DOCTOR_JSCPD_PREFIXES`
set at `setup()` scope to fixture directories, so no test reads the real
`/home/linuxbrew`, `/opt/homebrew` or `/usr/local`. `npm` is a stub printing a fixture prefix.

Cases: one pinned copy (PASS); a pinned copy on PATH plus a stale copy only in a prefix (PASS
plus FAIL, doctor failed); none found (WARN, no FAIL); a copy printing no version (FAIL); a copy
exiting non-zero (FAIL); a hung copy under `_DOCTOR_PROBE_TIMEOUT=1` (FAIL, bounded); the same
file reached through PATH and a prefix symlink (examined once); `HAS_DEVTOOLS` unset (no output);
both remedy branches, including `sudo ` for an unwritable `lib/node_modules`; a stale copy whose
output is `cpd 5.0.14`, the real stale binary's form.

`run_doctor` end-to-end tests stub the new arm, as they stub the other external-tool arms.

## Requirements

- **R1.** `lib/helpers.sh` defines `_doctor_check_jscpd`, and `run_doctor` calls it immediately after `_doctor_check_versions`.
- **R2.** `_doctor_check_jscpd` returns 0 and prints nothing when `HAS_DEVTOOLS` is unset or empty, on macOS and Linux alike.
- **R3.** The candidates are every executable file named `jscpd` on PATH, then `<prefix>/jscpd` for each prefix in `_DOCTOR_JSCPD_PREFIXES` (default `/home/linuxbrew/.linuxbrew/bin /opt/homebrew/bin /usr/local/bin`), each file examined once by its `readlink -f` target under the first path that reached it.
- **R4.** With no candidate, the arm emits `doctor_warn "jscpd" "not found — setup_env.sh -t developer"` and no FAIL.
- **R5.** Each candidate runs `--version` with stdin from `/dev/null`, bounded by `_doctor_resolve_timeout` and `_DOCTOR_PROBE_TIMEOUT` (default 10), and its version is the first match of `[0-9]+\.[0-9]+\.[0-9]+` in its combined stdout and stderr.
- **R6.** A candidate whose version equals `JSCPD_VER` emits `doctor_pass "jscpd ${JSCPD_VER} — <path>"`.
- **R7.** A candidate reporting any other version emits `doctor_fail "jscpd" "<path> reports <version>, pinned ${JSCPD_VER} — <remedy>"`.
- **R8.** A candidate that exits non-zero, times out, or prints no version emits `doctor_fail "jscpd" "<path> does not report a version (rc <rc>) — <remedy>"`.
- **R9.** The remedy is `setup_env.sh -t update` when the candidate's directory is `<npm prefix -g>/bin` for the `npm` on PATH, and otherwise `remove it: npm --prefix <candidate dir>/.. uninstall -g jscpd`, preceded by `sudo ` when `<candidate dir>/../lib/node_modules` is not writable by the current user.
- **R10.** `tests/setup_env/doctor_jscpd.bats`, listed in `tests/bats-files.txt`, points every candidate prefix and `npm` at fixtures and covers: one pinned copy (PASS); a pinned copy on PATH plus a stale copy only in a prefix (PASS and FAIL); no copy (WARN, no FAIL); a copy printing no version (FAIL); a copy exiting non-zero (FAIL); a hung copy under `_DOCTOR_PROBE_TIMEOUT=1` (FAIL within the bound); one file reached through PATH and a prefix symlink (one result); `HAS_DEVTOOLS` unset (no output); the `setup_env.sh -t update` remedy; the `remove it:` remedy with and without `sudo `; and a stale copy printing `cpd 5.0.14`.
- **V1.** On `claude`, `workstation` and the Studio, `setup_env.sh -t doctor`, run as `CLAUDE.md` prescribes for each box, prints exactly one jscpd PASS line naming the managed copy and no jscpd FAIL.
- **V2.** A stale copy planted in a scratch prefix and named through `_DOCTOR_JSCPD_PREFIXES` makes a real `-t doctor` FAIL with the `remove it:` remedy.
- **N1.** The arm never installs, upgrades, removes or rewrites any file or package.
- **N2.** No change to how `run_developer_or_ansible` or `-t update` install npm globals.
- **N3.** No version check for npm globals other than jscpd.

## Multi-Lens Review

Reviewed at commit: `34963939` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The premise is false and the arm cannot carry the goal. ai-config's gate resolves jscpd
on PATH only (`.claude/scripts/duplication_checker.py` `_find_jscpd`, `shutil.which("jscpd",
path=env.get("PATH"))` at d564309c, `feat/push-time-gates` and the `ai-config-gates` worktree);
no ref has a fallback order, so `_DOCTOR_JSCPD_PREFIXES` mirrors nothing. The arm's output is read
only on a manual `-t doctor` and cannot change a gate verdict. ai-config already reads the version
of the exact binary the gate runs (`_check_jscpd_version`) and only warns; failing closed there
removes the box-dependence at the moment of use.
Assumption: drift reaches a gate verdict only if the pre-push hook's PATH can reach a different
copy than interactive zsh does; settled by printing `type -ap jscpd` inside a real hook run.
Disposition: Accepted, operator 2026-11-24: retire this spec; the gate fails closed instead.

### Ergonomics

Finding: R9 classifies the managed copy by the actor's `npm prefix -g`. Under a bare PATH on
`claude` and `workstation` that is `/usr/bin/npm`, prefix `/usr/local` (measured on `claude`),
so the remedy would tell the operator to uninstall the Linuxbrew copy and to run `-t update` for
the `/usr/local` one, recreating the two-copy state. A bare `setup_env.sh -t update` also runs
the real repo-sync and `rsync --delete` sections. The same mechanism (a bare-PATH setup or
update installing through the system npm into `/usr/local`) is the likely origin of the stale
copy.
Assumption: every jscpd the gate's actor can reach appears in doctor's PATH plus the three
prefixes; settled by diffing `type -ap jscpd` inside a real hook run against doctor's list.
Disposition: Accepted, operator 2026-11-24: retire; the likely origin goes to the Backlog.

### Risk

Finding: The candidate set is a sound superset, but a doctor PASS does not mean the gate resolves
a pinned jscpd: on `claude`, `env -i PATH=/usr/bin:/bin bash -c 'command -v jscpd'` finds none,
while doctor would PASS through the Linuxbrew prefix. The FAIL policy's "the gate's fallback
order can reach it" rests on a mechanism that does not exist. The remedy branch is over-built.
`plugin_node_paths.bats` would run the real arm on fleet boxes (`HAS_DEVTOOLS` inherited).
Assumption: a doctor PASS means jscpd resolves on the PATH the pre-push gate runs under; refuted
on `claude` for a bare PATH.
Disposition: Accepted, operator 2026-11-24: retire.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
