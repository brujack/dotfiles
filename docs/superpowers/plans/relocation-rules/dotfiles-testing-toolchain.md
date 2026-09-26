# Rule bullets — dotfiles-testing-toolchain.md

One entry per MOVE group whose destination is `dotfiles-testing-toolchain.md` (G53–G64).

### make test parallel jobs: detection, JOBS validation, and the CI file list

lead: none

- Detect GNU parallel by version string (`parallel --version` matching `^GNU parallel`), never by presence — moreutils ships an incompatible `parallel` under the same name, and bats' own absence-guard is inverted, so a fooled detector dies with `command not found`.
- `JOBS` defaults to 24; override per invocation with `make test JOBS=6`, and never pass `JOBS="$(nproc)"` (worst setting on a 2-vCPU runner).
- In a **test** that invokes make inside make, `unset MAKEFLAGS MFLAGS MAKELEVEL JOBS` (`tests/makefile_parallel_target.bats:21`) — a command-line `JOBS` reaches the nested make via both `MAKEFLAGS` and the recipe environment, which is why the error names `$(origin JOBS)`. Test-scoped: stripping `MAKEFLAGS` elsewhere also strips `--no-print-directory` (see MAKEFLAGS section).
- Force serial anywhere with `make test HAVE_PARALLEL=`. The bats file list is a filesystem walk, not `git ls-files` (untracked `.bats` files still run); add to `BATS_SERIAL_FILES` only with a measurement showing failure under `--jobs`.
  trigger: changing parallel-jobs detection or the JOBS/serial-file knobs | `Makefile`, `HAVE_PARALLEL`, `JOBS`, `BATS_SERIAL_FILES`
  covers:
  - a: "The guard is required rather than defensive, b"
  - a: "a **test** that invokes make inside make must uns"
  - a: "An untracked `.bats` file is exactly what a TDD "
  - a: "Never pass `JOBS=\"$(nproc)\"`: on a 2-vCPU runner"
  - b: "Override it per invocation (`make test JOBS=6`)."
  - b: "To force serial anywhere, `make test HAVE_PARALLE"
  - b: "A name here needs a measurement beside it."

### config/profiles.sh dual lint scope; scripts/phrase_check.py manifest checker

lead: none

- Keep `config/profiles.sh` in both `SHELL_FILES` (`bash -n`, shellcheck) and `ZSH_FILES` (`zsh -n`) — it is sourced from `.zprofile` and `1_init.zsh` and must parse under both. Update the pathspec at both call sites, `Makefile`'s `ZSH_FILES` and `ci.yml`'s `lint-macos` job, together, or the other silently checks a stale set.
- `scripts/phrase_check.py` must verify every classified CLAUDE.md paragraph has a `phrases.md` anchor that still holds, matching whitespace-normalised (never line-oriented, so a wrapped sentence isn't missed) and rejecting any anchor that opens a sentence or paragraph as too fragile.
- `test-python` only runs the checker's own unit tests, not the checker against the real manifest — that only runs from the four-class-resort plan's `acceptance:` blocks, so do not read this suite's coverage as evidence the manifest is enforced.
  trigger: changing lint scope or the phrase-check manifest checker | `Makefile`, `scripts/phrase_check.py`, `.github/workflows/ci.yml`
  covers:
  - a: "`config/profiles.sh` is a bash file — it stays i"
  - a: "The pathspec is duplicated at two independent ca"
  - a: "**`scripts/phrase_check.py`** verifies the CLAUDE"
  - a: "Matching is whitespace-normalised and never line-"
  - a: "`test-python` runs `tests/test_phrase_check.py`, "
  - a: "Do not read the suite's coverage as evidence the "
  - b: (none — verdict: complete)

### Ansible venv snapshot before every sync (uv sync prune/downgrade, rollback)

lead: none

- The venv is snapshotted (`pip freeze`) before every sync, and that snapshot is the only rollback path — `uv sync` prunes and downgrades, and the pre-sync state cannot be reproduced from `uv.lock`. Reverting this repo does not restore the venv.
- To roll back, run `"$(pyenv which python)" -m pip install --no-deps -r ~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt` — `--no-deps` is required because the resolver refuses the exact state being restored.
  trigger: rolling back or changing the ansible venv sync | `run_update`, `~/.local/share/dotfiles/venv-snapshots/`
  covers:
  - a: "**The venv is snapshotted before every sync, and "
  - a: "`--no-deps` is required — the state being restore"
  - b: "Reverting this repo does not restore the venv."
  - b: "To roll back:" (plus the fenced `pip install --no-deps -r …` command)

### Environment overrides added by the uv work (UV_BIN, UV_FALLBACK_PATHS, REQUIREMENTS_CI_TARGET)

lead: none

- `UV_BIN` (`resolve_uv`, `lib/helpers.sh`) is the operator escape hatch and the only seam that can drive the "not executable" branch — PATH mocking cannot remove the absolute fallback candidates.
- `UV_FALLBACK_PATHS` (`resolve_uv`) holds prefix candidates so a test can reach the genuine not-found branch, otherwise unreachable on any machine with `uv`; it is env-settable as a scalar deliberately, since `UV_BIN`, checked first, already grants the same capability.
- `REQUIREMENTS_CI_TARGET` (`scripts/sync-requirements-ci.sh`) points the drift check at a fixture, so a test that crashes between mutating and restoring cannot leave a modified tracked `requirements-ci.txt` to be committed by accident.
  trigger: editing UV resolution or the CI-requirements drift check | `lib/helpers.sh` `resolve_uv`, `scripts/sync-requirements-ci.sh`
  covers:
  - a: "| variable | read by | why it exists |" (table header/rows, truncated at "array of prefix candidates.")

### Sync/check CI requirements commands and the five renderings

lead: none

- `make sync-requirements-ci` renders all five CI requirements files from `uv.lock`; `make check-requirements-ci` fails when any of the five renderings is stale and is a prerequisite of `make test`.
- There are five renderings, and they are deliberately separate files — never collapse them into one.
  trigger: syncing or checking the CI requirements renderings | `make sync-requirements-ci`, `make check-requirements-ci`, `scripts/sync-requirements-ci.sh`
  covers:
  - a: (none retained above this pointer)
  - b: "**Sync CI requirements:** `make sync-requirements"

### Requirements CI groups: do not harmonise (distinctness tests)

lead: none

- Never harmonise the five requirements-CI renderings — `tests/setup_env/requirements_ci.bats` asserts distinctness: `test-lint` differs from `runtime`, and `test-lint`/`runtime`/`ci-test`/`ci-mutation` are four pairwise-distinct files.
  trigger: editing a requirements-ci rendering or its dependency groups | `pyproject.toml`, `tests/setup_env/requirements_ci.bats`
  covers:
  - a: "Do not harmonise them — `tests/setup_env/requi"
  - b: (none — verdict: complete)

### Requirements CI groups: purpose over CI/local, and the erosion guard

lead: none

- Scope CI requirements groups by purpose, not by pruning uninvoked tools — pruning still leaves a rendering installing packages a consumer never runs (test-lint 80→73 still left 70 unused for a 3-tool consumer). Not a deletion problem: the packages belong in the venv; each group installs only what its own job runs (`ci-test` = per-PR test/lint, `ci-mutation` = mutation).
- Keep `bandit`, `radon` and `vulture` in `test-lint` only — `bandit` runs via `security-review` on a dev machine, not CI; skills are a caller class a repo-only sweep can't see (`pip-audit`, `hypothesis` too).
- Never put provenance (a `uv.lock` SHA) in a rendering's header — a `runtime`-group edit moves `uv.lock` without changing `test-lint`'s export, forcing a re-render on unrelated changes. Provenance belongs on a consumer's own copy, at copy time.
- `ci-test`'s boundary is stated in `pyproject.toml` and **guarded by a test, not by review**: `ci-test carries none of the mutation whales` fails if `sqlalchemy`/`aiohttp`/`gitpython`/`yarl`/`frozenlist`/`multidict` ever appear there, and `ci-test is materially smaller than the full test-lint rendering` fails if the two converge. Add a tool only on a measurement, as `hypothesis` was — never because "that is where tools go".
  trigger: adding or moving a tool between requirements-CI groups | `pyproject.toml`, `ci-test`, `test-lint`
  covers:
  - a: "Dropping every genuinely-uninvoked tool takes the"
  - a: "**The framing that matters, because it was wrong "
  - a: "A repo-only sweep cannot see that call: **skills "
  - a: "A `runtime`-group edit moves `uv.lock` without ch"
  - a: "**`ci-test`'s boundary is stated in `pyproject.tom"
  - b: "**Provenance does not go in these headers, and th"
  - b: "**`bandit`, `radon` and `vulture` stay in `test-li"
  - b: "admitted deliberately, on a measurement rather th"

### Requirements CI groups: drift-gate blindness and uv export determinism

lead: none

- The drift gate only verifies a rendering is faithful to its declared group — a package in the wrong group still renders faithfully and passes, so a green `check-requirements-ci` is not evidence about grouping (`cosmic-ray` sat wrongly grouped through every green run for months).
- `requirements-ci.txt` is a rendering of `pyproject.toml` plus `uv.lock`, not a declaration — never hand-edit it.
- `uv export` is not byte-deterministic (its header echoes the invoking argv), so `scripts/sync-requirements-ci.sh` must strip and replace that header, or the drift gate fires on every PR; the Makefile guard must skip cleanly when `uv` is absent, and CI must install a pinned, checksum-verified `uv`.
  trigger: editing the requirements-ci renderings or the drift check | `scripts/sync-requirements-ci.sh`, `requirements-ci.txt`, `make check-requirements-ci`
  covers:
  - a: "**The drift gate cannot see a wrong-group declara"
  - a: "Never hand-edit it."
  - b: "A green `check-requirements-ci` is not evidence a"

### Pre-commit hook: make lint and the ggshield actor-boundary resolution

lead: none

- The pre-commit hook is required: run `make lint` (blocks on any syntax/shellcheck failure), then `ggshield secret scan pre-commit` (scans staged changes for secrets before they reach the remote).
- Resolve `ggshield` by explicit override, then `PATH`, then absolute prefixes — never `command -v` alone — since a git hook inherits whoever invoked `git`, and an interactive-only `PATH` prepend makes `ggshield` invisible to cron and `ssh host '<cmd>'`.
- If `ggshield` is unresolvable, exit 0 (a machine lacking it must still be able to commit the fix that installs it) but announce the skip twice on stderr — never silently.
  trigger: changing ggshield resolution or the pre-commit chain | `scripts/pre-commit-hook.sh`
  covers:
  - a: "The pre-commit hook is **required**."
  - a: "**Resolved by explicit override, then `PATH`, the"
  - a: "The absent case still exits 0 — a machine lacking"
  - b: "**Resolved by explicit override, then `PATH`, the" (needs unit: subject is ggshield resolution)
  - b: "The absent case still exits 0 — … but it now says" (needs unit: subject is the pre-commit hook)

### Pre-push hook: fail-closed inert-path set

lead: none

- The pre-push hook is permanent — it runs `make test` (lint + bats) on every push and fails closed: the suite runs unless every changed path is provably inert, and an unresolvable diff range also fails closed rather than reading as no-change.
- `docs/` and `.github/` are **not** wholesale-inert: `make lint`'s `SHELL_FILES` walk is recursive, so any `.sh` file anywhere in the repo — including under `docs/` or `.github/` — is linted by `make test` and must still trigger the suite.
  trigger: changing the pre-push inert-path set | `scripts/pre-push`
  covers:
  - a: "`docs/` and `.github/` are **not** wholesale-iner"
  - b: "The pre-push hook is **permanent**."

### Pre-push hook: worktree root resolution and git env strip

lead: none

- `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, falling back to the `git rev-parse --git-common-dir` parent only if that fails — direct `--git-common-dir` resolution can test the shared checkout instead of the active worktree branch.
- `scripts/pre-push` must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before invoking `make test`, and that line must stay below the range-resolution loop (which needs the git environment) — without the strip, a worktree push leaks `GIT_DIR` into every fixture-building test and `git -C <fixture>` silently operates on the leaked repo instead.
  trigger: editing pre-push repo-root resolution or its git-env handling | `scripts/pre-push`
  covers:
  - a: "**Worktree compatibility requirement:** `scripts/"
  - a: "**Git env strip requirement:** `scripts/pre-push`"
  - a: "Git exports `GIT_DIR` into the hook only when the"
  - b: (none — verdict: complete)

### Pre-push hook: direct-to-master guard (executable-class paths)

lead: none

- Refuse any push to `refs/heads/master` whose diff carries an executable-class path (`*.sh`, `*.bash`, `*.bats`, `*.zsh`, `Makefile`, or the extensionless `scripts/pre-push`/`scripts/commit-msg`) — `ci.yml` triggers on `pull_request` only, so nothing else validates a direct-to-master code push.
- Accumulate the refusal in a flag inside the stdin loop, read it after the loop finishes (never exit mid-loop — one push can carry a branch and a deletion together), and check it **before** the `needs_test` early-exit, or an inert-but-unsafe path skips the guard too.
- Evaluate the refusal against the whole push RANGE, not the tip commit: a docs-only commit stacked on an unpushed executable-class commit is still refused, since both would reach master. If a docs push is refused naming a file you did not touch in that commit, run `git diff --name-only <remote-sha>..HEAD` before assuming the guard is wrong. Never repoint the twelve `tests/scripts/pre_push.bats` tests from their feature ref to master, or they stop testing the inert-set logic and start testing this guard.
- `scripts/pre-push` is itself executable-class, so a defective guard needs a branch and a PR to fix — or `--no-verify` — never a direct push to master.
  trigger: editing the pre-push direct-to-master guard | `scripts/pre-push`, `tests/scripts/pre_push.bats`
  covers:
  - a: "**Direct-to-master guard:** `scripts/pre-push` re"
  - a: "Why: `.github/workflows/ci.yml` triggers on `pull_"
  - a: "The verdict **accumulates in a flag inside the st"
  - a: "A docs-only commit stacked on an unpushed executa"
  - a: "check `git diff --name-only <remote-sha>..HEAD` be"
  - a: "so a defective guard cannot be repaired by a direc"
  - a: "**Twelve tests in `tests/scripts/pre_push.bats` p"
  - b: "And the refusal is checked **before** the `needs_"
