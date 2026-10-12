# Ansible venv interpreter guard

- **Date:** 2026-10-11
- **Approved:** 2026-10-11
- **Backlog rows closed:** `setup_ansible` deletes the ansible venv when its own
  `pyenv install` fails; `-t recreate-venv` destroys the venv after a `PYTHON_VER` bump;
  `setup_ansible` calls `pyenv update`, which linuxbrew pyenv lacks.

## Problem

Two functions in `lib/developer.sh` delete the `ansible` virtualenv before proving the
interpreter the replacement needs exists. A failed or skipped Python build therefore ends
with no venv at all, and the only rollback path (`uv_sync_venv`'s `pip freeze` snapshot)
runs after the recreate, so it captures the new, empty venv rather than the old one.

Premises, each checked against the code on `65f8f668`:

1. **`setup_ansible` (`lib/developer.sh:523`).** The install block is gated on
   `! -d ${HOME}/.pyenv/versions/${PYTHON_VER}`. Neither the Linux
   `env -i … bash -lc '… pyenv install -s -v "${PYTHON_VER}"'` (`:552-565`) nor the macOS
   `pyenv install -s "${PYTHON_VER}"` (`:569`) has its exit status read. When
   `readlink ~/.pyenv/versions/ansible` no longer names `${PYTHON_VER}/envs/ansible`, the
   function then runs `pyenv virtualenv-delete -f ansible` (`:581`) and
   `pyenv virtualenv "${PYTHON_VER}" ansible` (`:582`), the second also unchecked.
2. **`recreate_python_venv` (`:625`).** Runs `pyenv virtualenv-delete -f` (`:637`), then
   `pyenv virtualenv "${PYTHON_VER}" … || return 1` (`:640`) with no install step. An
   uninstalled `PYTHON_VER` returns 1 with the venv already gone.
3. **`pyenv update` (`:538`).** Measured 2026-10-11 in interactive zsh on each host:

   | host          | `pyenv`                                                   | `pyenv commands` lists `update` | `pyenv update` rc |
   | ------------- | --------------------------------------------------------- | ------------------------------- | ----------------- |
   | `claude`      | `/home/linuxbrew/.linuxbrew/bin/pyenv`                    | 0                               | 1                 |
   | `studio`      | Homebrew                                                  | 0                               | 1                 |
   | `workstation` | linuxbrew, plus a git-era `~/.pyenv/plugins/pyenv-update` | 1                               | 0                 |

   So the call errors on two of three development machines and works on the third only
   because of leftover plugin checkouts. It runs unchecked, so today it costs an error line,
   not a failure.

**Why now.** Both bugs are latent: `claude` and `workstation` both have
`versions/ansible -> 3.14.8/envs/ansible` and `PYTHON_VER="3.14.8"`. The next `PYTHON_VER`
bump arms them, and `check-versions --update` now writes `PYTHON_VER` (#331).

## Design

### `_ensure_pyenv_python` (new, `lib/developer.sh`)

The install block moves out of `setup_ansible` into one function both callers use. Let
`_py="${HOME}/.pyenv/versions/${PYTHON_VER}/bin/python"`.

1. `[[ -x ${_py} ]]` → return 0. This replaces the `-d` directory test: a directory left by
   an interrupted build no longer counts as installed.
2. Linux (`LINUX` set): the existing build-dependency `apt-get` line, unchanged; then
   `pyenv update` **only when** `pyenv commands 2>/dev/null | grep -qx update`; then the
   existing `/tmp/python-build.*` cleanup, `~/.pyenv/bin/pyenv` symlink and `env -i` build,
   unchanged.
3. macOS (`MACOS` set): `pyenv install -s "${PYTHON_VER}"`, unchanged.
4. Neither set: `log_error` naming the missing platform detection, return 1. Today this
   branch silently does nothing.
5. Re-test `[[ -x ${_py} ]]`. On failure, `log_error` naming `${_py}`; when
   `~/.pyenv/versions/${PYTHON_VER}` exists, also state that it blocks reinstall
   (`install -s` skips any version whose directory exists) and must be removed. Return 1.

The post-install interpreter test is the single source of truth. The install commands'
own exit codes are not read: the test subsumes a failed build, a skipped build and a broken
leftover directory, and it is the one condition the callers actually depend on.

### Callers

- `setup_ansible`: first statement after its banner is `_ensure_pyenv_python || return 1`.
  `pyenv virtualenv "${PYTHON_VER}" ansible` gains `|| return 1`. Nothing else moves.
- `recreate_python_venv`: `_ensure_pyenv_python || return 1` after `eval "$(pyenv init -)"`
  and before the delete.

**Behaviour change, stated.** `run_developer_or_ansible` calls `setup_ansible || return 1`
(`lib/workflows.sh:622`). After a failed build, `-t developer` and `-t ansible` now stop
before `clone_personal_repos` with the venv intact. Today they delete the venv, return 0
from the unchecked path, and continue. The stop is the intended direction. It also reaches
two cases that today continue silently: a mac without `HAS_DEVTOOLS` (`mac_mini`), whose
install still runs although the venv step is skipped, and any box with no pyenv, where the
install commands fail and the interpreter test now reports it. `-t setup` alone never
calls `setup_ansible` (`setup_env.sh:98`) and is unchanged.

`lib/workflows.sh:1036` says `pyenv update` "runs only inside setup_ansible"; it is
reworded to name `_ensure_pyenv_python`, reached from `setup_ansible` and
`recreate_python_venv`.

### Test mock

`tests/mocks/pyenv` gains two behaviours. About 40 existing tests reach `setup_ansible` or
`recreate_python_venv` directly or through `run_developer_or_ansible`,
`run_setup_or_developer` and `run_recreate_venv`, and the mock's `install` today creates
nothing, so without them every one of those tests would fail the new interpreter test.

**The Linux build runs the mock under `env -i`.** That strips everything except `HOME`,
`USER`, `SHELL`, `TERM`, `PYTHON_VER`, `PYENV_ROOT`, `PYENV_VIRTUALENV_DISABLE_PROMPT`,
`PYTHON_CONFIGURE_OPTS` and `PATH` (`lib/developer.sh:552-561`). `BATS_TEST_TMPDIR`,
`MOCK_PYENV_*` and `MOCK_CALLS_FILE` are all gone there. Measured:
`env -i bash -c 'echo [$BATS_TEST_TMPDIR]'` prints `[]`. So every input the mock's install
step reads must be derived from `HOME` or the argument list:

- **Order.** `install` checks, in turn: the failure-injection file, then
  `MOCK_PYENV_EXIT` (visible only on the caller-shell macOS path), then `-s` with an
  existing `versions/<ver>` (create nothing, exit 0, as real `install -s` does), then
  create.
- **Create.** `pyenv install <args> <ver>` creates `${HOME}/.pyenv/versions/<ver>/bin/python`
  (executable) and exits 0, as a successful real install does (`tdd.md` pitfall E). It keys
  on `HOME` only, never `PYENV_ROOT`: developer shells export
  `PYENV_ROOT=/home/bruce/.pyenv`, which `developer.bats` does not unset, so a
  `PYENV_ROOT`-keyed target would aim local runs at the real interpreter while CI, which has
  no `PYENV_ROOT`, stayed green.
- **Inert outside bats (`tdd.md` E2).** The create happens only when `HOME` matches
  `*/bats-run-*`, the shape of every bats test directory (measured on bats 1.13.0:
  `BATS_TEST_TMPDIR=/tmp/bats-run-Wtu3GU/test/1`). A real `HOME` never matches, and an empty
  `HOME` does not match, so in both cases the mock creates nothing, prints one stderr line
  naming the declined `HOME`, and exits with the status it would otherwise return. It also
  never overwrites an existing file. Every suite
  affected redirects `HOME` under `BATS_TEST_TMPDIR`, most in `setup()` (for example
  `workflows.bats:44`, `developer.bats:10`); the guard is defence in depth, not a fix for a
  known unredirected suite.
- **Failure injection.** If `${HOME}/.mock-pyenv-install-exit` exists, `install` exits with
  the number it contains and creates nothing. A file, not an environment variable, because
  the environment does not survive `env -i`.
- **`pyenv commands`** prints `MOCK_PYENV_COMMANDS` (newline-separated), empty by default.
  This call runs in the caller's shell, outside `env -i`, so a variable is fine here.

## Testing

All in `tests/setup_env/developer.bats`. Each guard is mutation-checked: delete it, confirm
the test goes red, restore. On the Linux branch the mock's call log is lost under `env -i`
(it falls back to `/tmp/mock_calls`), so Linux cases assert on the filesystem and on calls
made from the caller's shell (`virtualenv-delete`, `virtualenv`, `update`), never on the
`install` call itself. Every rc-1 case pairs with an assertion that only the intended path
satisfies, and every absence assertion pairs with a positive one.

| case | platform | asserts |
| --- | --- | --- |
| install fails, venv points at old version (`setup_ansible`) | Linux | rc 1; no `virtualenv-delete`; `versions/ansible` symlink unchanged; error names `bin/python` path |
| same | macOS | same, plus `install` was called |
| install fails (`recreate_python_venv`) | macOS | rc 1; no `virtualenv-delete`; venv unchanged; error names path |
| interpreter missing, install succeeds (`recreate_python_venv`) | macOS | rc 0; `install` before `virtualenv-delete` in the log |
| interpreter missing, install succeeds (`setup_ansible`) | Linux | rc 0; `versions/<ver>/bin/python` now exists; `virtualenv` called |
| interpreter already executable | macOS | rc 0; `virtualenv` called; no `install` |
| version dir exists, no `bin/python` | macOS | rc 1; error names the path and says to remove the directory |
| `pyenv commands` lists `update` | Linux | `pyenv update` called; rc 0 |
| `pyenv commands` omits `update` | Linux | `pyenv update` not called; rc 0; `bin/python` created |
| neither `LINUX` nor `MACOS` | none | rc 1; no `virtualenv-delete`; error names platform detection |
| mock guard: `HOME` outside `*/bats-run-*` | n/a | mock `install` creates no file under that `HOME`, prints the decline line; positive control: same call with `HOME` under `BATS_TEST_TMPDIR` creates `bin/python`. The outside `HOME` is a `mktemp -d` under `/tmp` without `bats-run-` in its path, removed in `teardown` |
| `-s` with existing `versions/<ver>`, no `bin/python` | mock | mock creates nothing, exits 0 |

Existing tests the change reaches, each updated in the same commit as the change that
moves it:

- `developer.bats:688` (`calls pyenv update on Linux…`): sets `MOCK_PYENV_COMMANDS=update`.
- `developer.bats:926` (`pyenv rehash still runs…` for `setup_ansible`): its blanket
  `MOCK_PYENV_EXIT=3` now fails the checked `pyenv virtualenv`; it scopes the failure to
  `rehash` and its comment about unchecked calls is corrected.
- `developer.bats:961` (`pyenv rehash still runs…` for `recreate_python_venv`): its
  shell-function `pyenv` makes `command -v pyenv` return a bare word, so the Linux symlink
  points at itself; the fixture supplies an executable `versions/${PYTHON_VER}/bin/python`.
- `developer.bats:853`, `:877`, `:909`, `workflows.bats:1386`, `:1391`: create
  `versions/${PYTHON_VER}` without `bin/python`, so under `-x` they would silently take the
  install path (`tdd.md` E4); each creates an executable `bin/python` to keep testing the
  path its name describes.

The full `make test` run is the check that this list is complete.

## Out of scope

- **No build-then-swap.** If `pyenv virtualenv` fails after the interpreter is proven, the
  venv is still lost. The interpreter guard removes the cause named in both backlog rows;
  an atomic swap is a separate design.
- **No pre-delete snapshot.** `uv_sync_venv` snapshots after the recreate. Snapshotting the
  old venv before deletion is a separate change.
- **Workstation's git-era `~/.pyenv/plugins/python-build`.** It sits on `PATH` ahead of
  linuxbrew's copy and may shadow brew's build definitions. Recorded as a backlog row in
  the implementation PR, not fixed here.

## Requirements

- **R1.** `lib/developer.sh` defines `_ensure_pyenv_python`, which returns 0 without
  running `pyenv install` when `${HOME}/.pyenv/versions/${PYTHON_VER}/bin/python` is
  executable.
- **R2.** `_ensure_pyenv_python` returns 1 when, after its install step, that interpreter
  is not executable; its error output names the interpreter path, and says to remove
  `versions/${PYTHON_VER}` only when that directory exists.
- **R3.** `_ensure_pyenv_python` returns 1 without running `pyenv install` when neither
  `LINUX` nor `MACOS` is set.
- **R4.** `_ensure_pyenv_python` runs `pyenv update` only when `pyenv commands` output
  contains a line exactly `update`.
- **R5.** `setup_ansible` calls `_ensure_pyenv_python` before any `pyenv virtualenv-delete`
  and returns 1 without deleting when it fails.
- **R6.** `recreate_python_venv` calls `_ensure_pyenv_python` before
  `pyenv virtualenv-delete` and returns 1 without deleting when it fails.
- **R7.** `setup_ansible` returns 1 when `pyenv virtualenv "${PYTHON_VER}" ansible` fails.
- **R8.** `tests/mocks/pyenv`'s `install` exits with the number in
  `${HOME}/.mock-pyenv-install-exit` and creates nothing when that file exists; otherwise
  honours `MOCK_PYENV_EXIT`; otherwise creates nothing and exits 0 when `-s` is passed and
  `${HOME}/.pyenv/versions/<ver>` exists; otherwise creates an executable
  `${HOME}/.pyenv/versions/<ver>/bin/python` and exits 0, only when `HOME` matches
  `*/bats-run-*`, never overwriting an existing file, and prints one stderr line when it
  declines for `HOME`. `commands` prints `MOCK_PYENV_COMMANDS`.
- **R9.** `lib/workflows.sh`'s comment about where `pyenv update` runs names
  `_ensure_pyenv_python`.
- **V1.** `make test` exits 0.
- **V2.** Each of the guards behind R2, R3, R5 and R6, deleted in turn, turns at least one
  test red.
- **V3.** On `studio` (macOS branch, no sudo), create a throwaway venv
  (`pyenv virtualenv 3.14.8 v3probe`), then in a scratch clone with `lib/constants.sh`'s
  `PYTHON_VER` edited to `9.9.9` run `./setup_env.sh -t recreate-venv --venv-name v3probe`:
  it exits non-zero and `readlink ~/.pyenv/versions/v3probe` is byte-identical before and
  after. Delete `v3probe` afterwards. The real `ansible` venv is never the target.
- **N1.** No change to the Linux `env -i` build command, its environment, or the
  build-dependency package list.
- **N2.** No build-then-swap or pre-delete snapshot of the venv.
- **N3.** No change to `--dry-run` gating of either function.

## Amendments

- R2 -> `_ensure_pyenv_python` returns 1 when, after its install step, that interpreter is not executable; its error output names the interpreter path, and says to remove `versions/${PYTHON_VER}` only when `versions/${PYTHON_VER}/bin` exists. — pyenv 2.8.9 `pyenv-install:212` skips `install -s` only when `${PREFIX}/bin` exists; a bare version directory is installed into, so the hint and its trigger must key on `bin/`.
- R8 -> `tests/mocks/pyenv`'s `install` exits 1 with a message for a version starting with `-` or containing `/`; exits with the base-10 number in `${HOME}/.mock-pyenv-install-exit` (validated as 0-255, else exit 1 with a message) and creates nothing when that file exists; otherwise honours `MOCK_PYENV_EXIT`; otherwise creates nothing and exits 0 when `-s` is passed and `${HOME}/.pyenv/versions/<ver>/bin` exists; otherwise creates an executable `${HOME}/.pyenv/versions/<ver>/bin/python` and exits 0, only when `HOME` matches `*/bats-run-*`, never overwriting an existing file, and prints one stderr line when it declines for `HOME`. When `MOCK_CALLS_FILE` is unset and `HOME` matches `*/bats-run-*` it logs to `${HOME}/.mock_calls`. `commands` prints `MOCK_PYENV_COMMANDS`. — same pyenv skip condition (mock fidelity, `tdd.md` E); plus the input validation and local call log added in Task 1 review.
- adds R10: `_ensure_pyenv_python` resolves the binary it symlinks to `${HOME}/.pyenv/bin/pyenv` with `type -P pyenv`, and creates no link when that prints nothing. — `recreate_python_venv` runs `eval "$(pyenv init -)"` first, which defines a `pyenv` shell function, so `command -v pyenv` prints the bare word and `ln -sf` writes a dangling relative link (Task 2 code review).

## Multi-Lens Review

Reviewed at commit: `d12e625b` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: R8's mock guard contradicts the spec's own `env -i` rule. The Linux build runs the
mock under `env -i`, which strips `BATS_TEST_TMPDIR`, `MOCK_PYENV_INSTALL_EXIT` and
`MOCK_CALLS_FILE`. So on Linux the mock never creates `bin/python`, every Linux test that
reaches the install returns 1, the "install succeeds" case cannot be expressed, and the
three rc-1 cases pass vacuously. Goal otherwise holds: every mechanism feeds the
`|| return 1` in `run_developer_or_ansible`. R3's neither-platform branch has thin value.
V3 on `claude` runs a real `sudo apt-get install`; name it or run V3 on macOS.
Assumption: the mock reached through `env -i` can tell a test directory from the real
`$HOME` using only what survives `env -i`. Settled by checking whether every suite reaching
the Linux branch redirects `HOME` under `BATS_TEST_TMPDIR`.
Disposition: Addressed — mock guard keyed on `HOME` matching `*/bats-run-*`; failure injection by file; Linux cases assert on disk; V3 moved to `studio`. R3 point: Accepted, reason: a silent no-op is the defect class.

### Ergonomics

Finding: same contradiction as Goal-Fit, plus a worse reading: a naive prefix test on an
empty `BATS_TEST_TMPDIR` matches every path, so a suite with real `HOME` and a bumped
`PYTHON_VER` would write a non-executable stub into the operator's real tree, recreating
the leftover-directory trap. Fix by keying on something `env -i` keeps, and state the
empty-input behaviour. Lesser: the "already executable" case is absence-only and passes if
`_ensure_pyenv_python` never runs; add a positive control. The operator-facing stop and its
error are well placed and actionable.
Assumption: the mock can tell a sandbox from a real `HOME` using only what survives
`env -i`; refuted if the `install_functions.bats` Linux tests go red or a probe with real
`HOME` and no `BATS_TEST_TMPDIR` creates a file.
Disposition: Addressed — guard keyed on `HOME`, empty input stated; positive controls added to every absence case.

### Risk

Finding: (1) same `env -i` contradiction, measured: `env -i bash -c 'echo
[$BATS_TEST_TMPDIR]'` prints `[]`; the case table does not say which platform each case
uses. (2) The mock targets `${PYENV_ROOT:-${HOME}/.pyenv}` while the guard reads
`${HOME}/.pyenv`; developer shells export `PYENV_ROOT=/home/bruce/.pyenv`, so locally the
macOS-branch tests would aim at the real interpreter and go red while CI stays green; key
on `HOME` only. (3) The stated reason for the guard is wrong: `workflows.bats:44` is inside
`setup()`, so `HOME` is redirected for every test there. (4) Unstated behaviour changes:
`-t developer` on a non-`HAS_DEVTOOLS` mac, or on a box with no pyenv, now aborts before
`clone_personal_repos` when the install fails. (5) Verdict count: absence-only and rc-1
cases pass a no-op or an always-1 function; only "missing, install succeeds -> rc 0"
fails a no-op.
Assumption: `bin/python` marks a working install on every host, including workstation's
git-era python-build. Checked 2026-10-11: `ls -l ~/.pyenv/versions/*/bin/python` on
`claude`, `workstation` and `studio` shows a `python -> python3.N` link in every installed
version (3.12.7 through 3.14.8). Confirmed.
Disposition: Addressed — mock keys on `HOME` only, never `PYENV_ROOT`; platform column added; guard reason corrected; behaviour changes stated; positive controls added.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `36dd6755` (revision after round 1; all three lenses re-run, told the
round-1 section is history).

#### Goal-Fit

Finding: the mock does not model `install -s`, which skips any version whose directory
exists. As R8 reads, it heals a leftover `versions/<ver>` by creating `bin/python`, so the
"version dir exists, no `bin/python`" case cannot fail as described, and
`workflows.bats:1391` (a bare `mkdir versions/${PYTHON_VER}`) passes only because the mock
fills it in. Fix: the mock creates nothing when `-s` is passed and `versions/<ver>`
exists; that test creates its own executable `bin/python`. Lesser: V3 runs against
`studio`'s real `ansible` venv, so a regressed guard would destroy it; use `--venv-name` on
a throwaway venv. Goal holds; verdict count good.
Assumption: CI's bats 1.10.0 names its run directory `bats-run-XXXXXX`. Checked 2026-10-11:
`v1.10.0/libexec/bats-core/bats:321` is
`BATS_RUN_TMPDIR=$(mktemp -d "${BATS_TMPDIR}/bats-run-XXXXXX")`, same as 1.11.0 and 1.13.0.
Confirmed.
Disposition: Addressed — mock models `install -s`; `workflows.bats:1391` creates its own `bin/python`; V3 targets a throwaway venv via `--venv-name`.

#### Ergonomics

Finding: (1) R7's new `|| return 1` breaks `developer.bats:926`, which sets a blanket
`MOCK_PYENV_EXIT=3` and expects rc 3 from `rehash`; the spec does not say how
`MOCK_PYENV_EXIT` interacts with `install` in the caller-shell path. (2) Same `install -s`
gap as Goal-Fit. (3) When the `HOME` guard declines, it is silent, so a future test with
`HOME=$(mktemp -d)` gets the leftover-directory error pointing at the wrong cause; print
one stderr line. Operator error actionable.
Assumption: a failed macOS build leaves `versions/<ver>` without `bin/python`, so the
"remove the directory" advice applies. Resolved without a probe on the real tree: the
advice is printed only when `versions/<ver>` exists, so it is correct whether pyenv cleans
up after a failed build or not.
Disposition: Addressed — `developer.bats:926` listed and updated; `MOCK_PYENV_EXIT` order stated; decline line added; removal advice conditional on the directory existing.

#### Risk

Finding: the guard holds (bats 1.10.0 and 1.13.0 share the shape; only an exported
`BATS_RUN_TMPDIR` or `--tempdir`, which the Makefile does not use, escapes it; the
injection file cannot leak because every affected `HOME` is per-test). But the revision
breaks or reroutes tests the spec does not name: (1) `developer.bats:926`, as Ergonomics;
(2) `developer.bats:961` shadows `pyenv` with a shell function, so on the Linux branch
`command -v pyenv` returns the bare word and `ln -sf` makes a self-referential link, the
`env -i` build finds no pyenv and the function returns 1 where the test expects 3;
(3) `developer.bats:853/877/909` and `workflows.bats:1386` create `versions/${PYTHON_VER}`
without `bin/python`, so under `-x` they silently take the install path (`tdd.md` E4);
(4) the "mock guard" row is absence-only and its `HOME` must live outside
`BATS_TEST_TMPDIR`, which the spec does not place or clean up.
Assumption: every test reaching `_ensure_pyenv_python` resolves `pyenv` to the mock as a
file; items (1) and (2) already break it. Settled only by running the suites against the
new mock, which is Phase 2's first red test.
Disposition: Addressed — `developer.bats:926`, `:961`, `:853`, `:877`, `:909` and `workflows.bats:1386`, `:1391` listed with their fixture changes; guard row gains a positive control and a placed, cleaned-up `HOME`. No round 3: every finding is in the test apparatus, and the remaining assumption is settled only by running the suites, which is Phase 2's first red test.
