# filelock 3.32.3 → 4.2.7 in uv.lock

- **Date:** 2026-11-02
- **Backlog row:** "filelock 3.32.3 has a fix (4.2.1, major) that `uv.lock` has not taken" (P2 bugs and security).

## Problem

`uv.lock` pins `filelock 3.32.3`, a transitive dependency of `ansible-lint`, `python-discovery` and
`virtualenv`. It is rendered into `requirements-ci.txt`, `requirements-ci-audit.txt` and
`requirements-runtime-ci.txt`.

**Premise check, 2026-11-02 (`gh api repos/brujack/dotfiles/dependabot/alerts`, state open):** 48 `filelock`
alerts across `uv.lock` and `requirements-ci.txt`, and 30 `virtualenv` alerts whose first patched version is
21.14.9.

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

1. `uv lock --upgrade-package filelock` (no other package may change).
2. `make sync-requirements-ci` regenerates the five renderings; the three that carry `filelock` change.
3. `pyproject.toml` is untouched: no floor, no `checkov` or `packaging` change.

The PR will not auto-merge, by design: `scripts/auto-merge-gate.sh` holds any PR that changes `uv.lock`
without `pyproject.toml` ("lock-only"; dotfiles#227), whatever its author. The operator merges it after
reading the lock diff, which the PR body states in its first line.

## Requirements

- **R1.** `[PR1]` `uv.lock` pins `filelock` at `4.2.7`, and no other package's version in `uv.lock` changes.
- **R2.** `[PR1]` Every rendering that pins `filelock` pins `4.2.7`, and `make check-requirements-ci` passes.
- **V1.** At the PR head, `make test` passes and every CI leg passes.
- **V2.** At the PR head, in a scratch copy, a venv built with `uv sync --frozen --all-groups` runs
  `ansible-lint --version`, `pre-commit --version` and `checkov --version`, creates a venv with `virtualenv`,
  and acquires a `filelock.FileLock`. The PR body records the output.
- **V3.** After merge, `gh api repos/brujack/dotfiles/dependabot/alerts` lists 0 open `filelock` alerts; the
  `virtualenv` alerts are moved to a new P2 Backlog row naming the `checkov` `packaging<24` pin.
- **V4.** CI's `auto-merge` job reports the lock-only hold (`uv.lock changed without pyproject.toml`); the
  PR merges only by the operator's hand.
- **N1.** `pyproject.toml` does not change.
- **N2.** No package other than `filelock` changes version in `uv.lock`.
- **N3.** No change to `checkov`, `packaging` or `virtualenv`.
