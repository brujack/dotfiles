# Ansible venv interpreter guard

- **Date:** 2026-10-11
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
5. Re-test `[[ -x ${_py} ]]`. On failure, `log_error` naming `${_py}` and stating that a
   leftover `~/.pyenv/versions/${PYTHON_VER}` directory blocks reinstall (`install -s` skips
   any version whose directory exists) and must be removed; return 1.

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
from the unchecked path, and continue. The stop is the intended direction.

`lib/workflows.sh:1036` says `pyenv update` "runs only inside setup_ansible"; it is
reworded to name `_ensure_pyenv_python`, reached from `setup_ansible` and
`recreate_python_venv`.

### Test mock

`tests/mocks/pyenv` gains two behaviours, both needed because about 40 existing tests reach
`setup_ansible` or `recreate_python_venv` directly or through `run_developer_or_ansible`,
`run_setup_or_developer` and `run_recreate_venv`, and the mock's `install` today creates
nothing:

- `pyenv install <args> <ver>` creates
  `${PYENV_ROOT:-${HOME}/.pyenv}/versions/<ver>/bin/python` (executable) and exits 0 by
  default, as a successful real install does (`tdd.md` pitfall E, mock fidelity).
  `MOCK_PYENV_INSTALL_EXIT=<n>` makes it exit `<n>` and create nothing.
- `pyenv commands` prints `MOCK_PYENV_COMMANDS` (newline-separated), empty by default.

**The create must be inert outside a test directory (`tdd.md` E2).** Not every suite that
reaches these functions redirects `HOME`: `workflows.bats` exports it in 2 places against
20 runs of the affected entry points. In a suite where `HOME` is real, an unconditional
create would write an empty file over `~/.pyenv/versions/3.14.8/bin/python`, destroying the
operator's interpreter. So the mock creates only when the target path lies under
`${BATS_TEST_TMPDIR}`, and never overwrites an existing file; otherwise it exits with the
status it would have returned and touches nothing.

The mock is reached both through `PATH` and at `${HOME}/.pyenv/bin/pyenv` (the `env -i`
branch strips `PATH`), so the create must key on the version argument and `HOME`, not on
any inherited variable the `env -i` strips.

## Testing

All in `tests/setup_env/developer.bats`. Each guard is mutation-checked: delete it, confirm
the test goes red, restore.

| case                                                           | asserts                                                                 |
| -------------------------------------------------------------- | ----------------------------------------------------------------------- |
| install fails, venv points at old version (`setup_ansible`)    | rc 1; no `virtualenv-delete` call; `versions/ansible` symlink unchanged |
| install fails (`recreate_python_venv`)                         | rc 1; no `virtualenv-delete` call; venv unchanged                       |
| interpreter missing, install succeeds (`recreate_python_venv`) | `install` called before `virtualenv-delete`; rc 0                       |
| interpreter already executable                                 | no `install` call                                                       |
| version dir exists, no `bin/python`                            | rc 1; error names the interpreter path                                  |
| `pyenv commands` lists `update`                                | `pyenv update` called                                                   |
| `pyenv commands` omits `update`                                | `pyenv update` not called                                               |
| neither `LINUX` nor `MACOS`                                    | rc 1; no `virtualenv-delete` call                                       |

The existing `calls pyenv update on Linux when Python version absent` test sets
`MOCK_PYENV_COMMANDS=update` to keep testing what its name says.

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
  is not executable, and its error output names the interpreter path.
- **R3.** `_ensure_pyenv_python` returns 1 without running `pyenv install` when neither
  `LINUX` nor `MACOS` is set.
- **R4.** `_ensure_pyenv_python` runs `pyenv update` only when `pyenv commands` output
  contains a line exactly `update`.
- **R5.** `setup_ansible` calls `_ensure_pyenv_python` before any `pyenv virtualenv-delete`
  and returns 1 without deleting when it fails.
- **R6.** `recreate_python_venv` calls `_ensure_pyenv_python` before
  `pyenv virtualenv-delete` and returns 1 without deleting when it fails.
- **R7.** `setup_ansible` returns 1 when `pyenv virtualenv "${PYTHON_VER}" ansible` fails.
- **R8.** `tests/mocks/pyenv`'s `install` creates an executable
  `versions/<ver>/bin/python` on success, honours `MOCK_PYENV_INSTALL_EXIT`, and `commands`
  prints `MOCK_PYENV_COMMANDS`. The create happens only for a path under
  `${BATS_TEST_TMPDIR}` and never overwrites an existing file.
- **R9.** `lib/workflows.sh`'s comment about where `pyenv update` runs names
  `_ensure_pyenv_python`.
- **V1.** `make test` exits 0.
- **V2.** Each of the guards behind R2, R3, R5 and R6, deleted in turn, turns at least one
  test red.
- **V3.** On `claude`, in a scratch clone with `lib/constants.sh`'s `PYTHON_VER` edited to
  `9.9.9` (a plain assignment, so an environment override is ignored), `./setup_env.sh -t
  recreate-venv` exits non-zero and `readlink ~/.pyenv/versions/ansible` is byte-identical
  before and after.
- **N1.** No change to the Linux `env -i` build command, its environment, or the
  build-dependency package list.
- **N2.** No build-then-swap or pre-delete snapshot of the venv.
- **N3.** No change to `--dry-run` gating of either function.

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
Disposition:

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
Disposition:

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
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
