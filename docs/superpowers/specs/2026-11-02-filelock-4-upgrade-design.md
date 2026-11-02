# filelock 3.32.3 → 4.2.1 in uv.lock

- **Date:** 2026-11-02
- **Backlog row:** "filelock 3.32.3 has a fix (4.2.1, major) that `uv.lock` has not taken" (P2 bugs and security).

## Problem

`uv.lock` pins `filelock 3.32.3`, a transitive dependency of `ansible-lint`, `cachecontrol`,
`python-discovery` and `virtualenv`. It is rendered into `requirements-ci.txt`, `requirements-ci-audit.txt` and
`requirements-runtime-ci.txt`.

**Premise check, 2026-11-02 (`gh api repos/brujack/dotfiles/dependabot/alerts`, state open):** 48 `filelock`
alerts, 12 in each of `uv.lock`, `requirements-ci.txt`, `requirements-ci-audit.txt` and
`requirements-runtime-ci.txt`, whose highest first-patched version is 4.2.1; and 30 `virtualenv` alerts (15 in
`uv.lock`, 15 in `requirements-ci.txt`) whose first patched version is 21.14.9.

**Feasibility, measured in a `git archive` copy of `be5549c3` on `claude`:**

- `uv lock --upgrade-package filelock` changes exactly one package: `Updated filelock v3.32.3 -> v4.2.7`.
- A venv built from that lock with `uv sync --frozen --all-groups`: `filelock 4.2.7`, `virtualenv 21.14.1`;
  `ansible-lint --version` (26.8.0), `pre-commit --version` (4.6.2) and `checkov --version` (3.3.13) run;
  `virtualenv` creates a venv; `filelock.FileLock` acquires and releases.
- `virtualenv` cannot reach 21.14.9: forcing `virtualenv>=21.14.9` fails with `checkov>=3.3.13 depends on
packaging>=23.0,<24.0 and virtualenv>=21.14.9 depends on packaging>=26.3`. Same shape as the existing
  `asteval` row, where `checkov` pins the vulnerable version.

**Population.** The smoke test ran on `claude` (Linux, CPython 3.14.10). The lock is shared with macOS, where
the venv is built from the same `uv.lock`; filelock 4 is pure Python. CI runs `make test`, whose
`check-requirements-ci` covers the renderings but never imports the venv's tools.

## Design

1. `uv lock --upgrade-package filelock==4.2.1` (no other package may change). Measured in an archive copy of
   `0d870360`: `Updated filelock v3.32.3 -> v4.2.1`, nothing else. 4.2.1 is the highest first-patched version
   of the 48 alerts and was uploaded 2026-10-17, so it satisfies `renovate.json`'s `minimumReleaseAge: 14 days`;
   4.2.7 (uploaded 2026-11-02) would not. The version is pinned so a later run cannot drift.
2. `make sync-requirements-ci` regenerates the five renderings; the three that carry `filelock` change.
3. `pyproject.toml` is untouched: no floor, no `checkov` or `packaging` change.

The PR will not auto-merge, by design: `scripts/auto-merge-gate.sh` holds any PR that changes `uv.lock`
without `pyproject.toml` ("lock-only"; dotfiles#227), whatever its author. The operator merges it after
reading the lock diff, which the PR body states in its first line.

## Requirements

- **R1.** `[PR1]` `uv.lock` pins `filelock` at `4.2.1`, and no other package's version in `uv.lock` changes.
- **R2.** `[PR1]` Every rendering that pins `filelock` pins `4.2.1`, and `make check-requirements-ci` passes.
- **V1.** At the PR head, `make test` passes and every CI leg passes. This is a regression guard only: no CI
  job installs the venv or a rendering, so it says nothing about filelock's consumers.
- **V2.** At the PR head, in a `mktemp -d` archive copy, build the venv as the real path does
  (`uv sync --frozen --group runtime --group test-lint` with `UV_PROJECT_ENVIRONMENT` inside the copy,
  `ANSIBLE_COLLECTIONS_PATH` and `HOME` pointed at scratch paths) and run, with a `sitecustomize` probe that
  counts `filelock.BaseFileLock.acquire` calls: (a) `ansible-lint` on a fixture one-task playbook with a fresh
  cache dir, asserting its exit status and finding count are the same under filelock 3.32.3 and 4.2.1 and
  that at least one acquire happened; (b) `virtualenv <dir>`, asserting it creates the venv and acquires at
  least once; (c) `virtualenv -p python3.14 <dir>` with `VIRTUALENV_OVERRIDE_APP_DATA` set to an empty scratch
  dir, recording whether python-discovery's `FileLock` is reached. The PR body records each command, rc and
  acquire count.
- **V3.** After merge, one `gh api repos/brujack/dotfiles/dependabot/alerts --paginate` query reports all 48
  `filelock` alerts as `state` `fixed` (0 open) and the 30 `virtualenv` alerts still open; an empty or failed
  query fails V3. The `virtualenv` alerts move to a new P2 Backlog row naming `checkov`'s `packaging<24` pin
  (checkov 3.4.3, the newest, still declares it).
- **V4.** CI's `auto-merge` job reports the lock-only hold (`uv.lock changed without pyproject.toml`); the
  PR merges only by the operator's hand.
- **N1.** `pyproject.toml` does not change.
- **N2.** No package other than `filelock` changes version in `uv.lock`.
- **N3.** No change to `checkov`, `packaging` or `virtualenv`.

## Multi-Lens Review

Reviewed at commit: `51607952` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth doing as scoped; pinning 4.2.7 (or 4.2.1, the highest first-patched version) clears all 48
`filelock` alerts. Premise wording is wrong: the 48 are 12 each across four manifests (`uv.lock`,
`requirements-ci.txt`, `requirements-ci-audit.txt`, `requirements-runtime-ci.txt`), all of which the design
regenerates. The `virtualenv` block really is only `checkov`: its newest release (3.4.3) still requires
`packaging<24.0,>=23.0`, and with `checkov` removed `virtualenv` resolves to 21.15.2. Reads-it: V1 is a
regression guard, not upgrade evidence (CI never imports the venv's tools); V2's `ansible-lint --version` may
never reach `FileLock(` in `initialize_options()`; V3 passes on an empty `gh api` result, so pin
`filelock` = 0 and `virtualenv` = 30 in the same query.
Assumption: that filelock 4 keeps the API ansible-lint uses at lint time; settled by linting a one-task
playbook in the upgraded venv.
Disposition: Addressed (operator, 2026-11-02) — premise counts corrected to 4 manifests × 12; V1 stated as a
regression guard only; V2 lints a fixture playbook; V3 pins `filelock` fixed and `virtualenv` 30 in one query.

### Ergonomics

Finding: The target version moves. Design step 1 runs an unpinned `--upgrade-package filelock`, and 4.2.7 was
uploaded 2026-11-02T16:09Z, so a later run can produce 4.2.8 and fail R1. 4.2.7 also skips the repo's own
`minimumReleaseAge: 14 days` (`renovate.json:51`); 4.2.1, the release carrying the fix, is 16 days old. Pin
the version (`--upgrade-package filelock==<ver>`) and either take 4.2.1 or record why the age policy is
waived. Verified: the change touches exactly `uv.lock` and the three renderings (6 lines each),
`check-requirements-ci` passes, `requirements_ci.bats` 31/31, and the auto-merge gate prints `uv.lock changed
without pyproject.toml -- leaving open for a human`. V3 should read each alert's `state` as `fixed`.
Assumption: that the unpinned upgrade resolves to the same version at implementation time; removed by pinning.
Disposition: Addressed (operator, 2026-11-02) — the version is pinned at 4.2.1 (operator's choice), which meets
the 14-day `minimumReleaseAge`; V3 reads `state` `fixed`.

### Risk

Finding: V2 cannot catch a real filelock break in three of its five checks. A `sitecustomize` probe wrapping
`BaseFileLock.acquire` counted 0 acquires for `ansible-lint --version` (`initialize_options` skips the cache
lock when `options.version` is set), `pre-commit --version` and `checkov --version`; 2 for `virtualenv <dir>`
(`_CountedFileLock`); 1 for `ansible-lint` on a one-task playbook (two parallel runs on a shared cache: no
Timeout). Replace the `--version` probe with a lint of a fixture playbook asserting a specific result; keep
the `virtualenv` create. API checked: virtualenv 21.14.1 subclasses `FileLock` and calls `acquire(timeout,
poll_interval)`/`release(force)` positionally, which 4.2.7's signatures keep; virtualenv declares
`filelock<5,>=3.24.2`. Fact errors: `cachecontrol` is a fourth consumer (0 acquires under `pip-audit -r`);
the real build path (`lib/helpers.sh:284`) syncs `--group runtime --group test-lint`, not `--all-groups`.
Apparatus: set `ANSIBLE_COLLECTIONS_PATH` to a scratch path, since ansible-lint otherwise discovers the real
venv's collections.
Assumption: that python-discovery's `_cache.locked()` (`with FileLock(...)`) works under 4.x; no V2 check
reached it. Settled by `virtualenv -p python3.14 <dir>` with `VIRTUALENV_OVERRIDE_APP_DATA=<tmp>` and
watching for a `UnixFileLock` acquire from `python_discovery`.
Disposition: Addressed (operator, 2026-11-02) — V2 rebuilt: real build groups, scratch `ANSIBLE_COLLECTIONS_PATH`,
acquire-counting probe, ansible-lint fixture compared across 3.32.3 and 4.2.1, `virtualenv` create, and a
python-discovery reach check; `cachecontrol` named as a consumer.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
