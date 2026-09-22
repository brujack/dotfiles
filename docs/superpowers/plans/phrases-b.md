# phrases-b.md -- CLAUDE.md fragment B: Testing intro, ShellCheck, Testing Rules,
# PowerShell Testing, Coverage, Mock Pattern (Test Seams and MAKEFLAGS excluded --
# owned by fragment C / Task 5). See docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md Task 4.
HAZARD | (Bash Automated Testing System), installed natively: | - | - | -
HAZARD | is a platform dispatcher (mirrors `install_zsh()`'s shape): `run_setup_user` calls it unconditionally on both macOS and Linux, so bats provisioning is no longer Linux-only. | - | - | -
HAZARD | `install_bats_macos()` in `lib/macos.sh` — `brew install bats-core` (also listed in `Brewfile` for `brew bundle` parity) | - | - | -
HAZARD | `install_bats_linux()` in `lib/linux_shared.sh` — `sudo apt-get install -y bats` | - | - | -
HAZARD | `make test` (runs lint, the lock and requirements-CI drift checks, the Python suite, then all BATS tests) | - | - | -
HAZARD | runs bats at `--jobs $(JOBS)` when **GNU** parallel is present, and serially with a notice when it is not. Three things about that are load-bearing: | - | - | -
DUPLICATE | ships an incompatible `parallel` under the same name, so `command -v parallel` is true for it; `HAVE_PARALLEL` greps `parallel --version` for `^GNU parallel` instead. | ~/.claude/standards/shell.md | moreutils `parallel` detection (`"command -v parallel" is not a GNU-parallel check...`) | CLAUDE.md restates the moreutils/HAVE_PARALLEL detection rule shell.md already states; both argue the same thing — detect the binary by --version, not by presence.
HAZARD | defaults to 24 and is validated in pure make at parse time** — no `$(shell)`, no fork. Override it per invocation (`make test JOBS=6`). | - | - | -
HAZARD | is a filesystem walk, not `git ls-files`.** An untracked `.bats` file is exactly what a TDD red step produces, and a tracked-only list would report it green by never running it. | - | - | -
HAZARD | carves a file out of the parallel pool to run alone afterwards. It is empty: the per-file check measured every file clean at `--jobs 12`, and the one that was not was fixed rather than exempted. | - | - | -
HAZARD | preinstalls GNU parallel, so `HAVE_PARALLEL` resolves to `yes` on the runner whatever the workflow installs — a claim to the contrary read off `ci.yml` is reading a file with no field for what the image ships (ai-config ADR-0078 Amendment 2). | - | - | -
DUPLICATE | on a 2-vCPU runner that is two workers, which ai-config's runner data shows is the worst available setting — slower than serial, while a fixed count well above the core count beats it. | ~/.claude/standards/ci.md | `$(nproc)` is the worst worker count on a 2-vCPU runner (measured in `ADR-0078 Amendment 2`) | Both argue the identical point — nproc is the worst worker count on a 2-vCPU runner, a fixed count above core count wins — sharing the phrase 'fixed count well above the core count'.
HAZARD | (runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`) | - | - | -
HAZARD | over `SHELL_FILES` (derived by `scripts/list-shell-files.sh`, which emits every tracked file whose first line is a bash/sh shebang — 107 files, measured 2026-09-08, including the `tests/mocks/` fixtures and the two extensionless hooks) | - | - | -
HAZARD | is a bash file — it stays in `SHELL_FILES` for `bash -n` and shellcheck — and is also the one deliberate entry in `ZSH_FILES` | - | - | -
HAZARD | (installs pre-commit and pre-push hooks; run once per checkout) | - | - | -
HAZARD | (regenerates `.cursor/rules/global-claude-standards.mdc` from root `CLAUDE.md`'s `@~/.claude/standards/*.md` imports, resolved against the global symlinked standards dir) | - | - | -
HAZARD | (fails when generated Cursor guidance is stale) | - | - | -
HAZARD | before every sync, and that file is the only rollback path.** `run_update` writes `pip freeze` to `~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt` before applying the lock, keeping the newest 10. | - | - | -
HAZARD | is required — the state being restored is one the resolver refuses. | - | - | -
HAZARD | added by the uv work.** All three exist for a stated reason and none grants a capability the operator did not already have: | - | - | -
HAZARD | operator escape hatch, and the only seam a test can use to drive the "not executable" branch — PATH mocking cannot remove the absolute fallback candidates | - | - | -
HAZARD | (renders **all five** CI requirements files from `uv.lock`) | - | - | -
HAZARD | renderings, deliberately separate files.** | - | - | -
HAZARD | the full local/dev test set | - | - | -
HAZARD | asserts distinctness across two tests: "the two renderings are different files with different content" (`test-lint` vs `runtime`) and "all four renderings are distinct files" | - | - | -
HAZARD | and that shape was measured and rejected rather than skipped.** Dropping every genuinely-uninvoked tool takes the test-lint rendering 80 → 73, so a consumer running three tools still installs 70 it never runs. | - | - | -
HAZARD | because it was wrong for most of the design: this was never a deletion problem.** The packages are legitimately in the venv — a human might use any of them | - | - | -
HAZARD | is stated in `pyproject.toml` and guarded by a test, not by review.** The predicted failure is erosion — a repo needs one more tool, it lands in `ci-test` because that is where tools go | - | - | -
HAZARD | stay in `test-lint` and are absent from every CI group, which is the point.** `bandit` is invoked by `security-review/SKILL.md:110` — a Phase 3 gate that runs on a developer machine | - | - | -
HAZARD | does not go in these headers, and that is load-bearing.** A `runtime`-group edit moves `uv.lock` without changing the `test-lint` export | - | - | -
HAZARD | cannot see a wrong-group declaration.** It verifies each rendering is faithful to its group; a package in the wrong group renders faithfully and passes. | - | - | -
HAZARD | is a **rendering, not a declaration** — `pyproject.toml` plus `uv.lock` are the source. It exists so the other repos' CI can `pip install -r` it with stock pip and no `uv` on the runner | - | - | -
HAZARD | is not byte-deterministic** — its header echoes the argv it was given, including an absolute `--project` path, so `scripts/sync-requirements-ci.sh` strips that header and writes a fixed one | - | - | -
HAZARD | hook is **required**. It runs on every `git commit`: | - | - | -
HAZARD | — blocks the commit on any syntax or shellcheck failure | - | - | -
HAZARD | — scans staged changes for secrets before they reach the remote. **Resolved by explicit override, then `PATH`, then absolute prefixes — not by `command -v` alone — and the skip is announced on stderr, never silent.** | - | - | Checked against shell.md/git-workflow.md ggshield material; no literal counterpart found — the ggshield actor-boundary resolution is dotfiles-specific narrative, not duplicated. Class HAZARD per instruction.
HAZARD | hook is **permanent**. It runs `make test` (lint + bats) on every push before the push reaches GitHub, and it **fails closed** | - | - | -
HAZARD | `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, and use `git rev-parse --git-common-dir` parent only as a fallback. | - | - | -
DUPLICATE | must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before invoking `make test` | ~/.claude/standards/git-workflow.md | "put `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` in every bats `setup()`" | Same mechanism (strip the git repo-location vars before running tests) argued in both files; git-workflow.md states it as the general BATS fixture rule, CLAUDE.md applies it to this repo's pre-push hook.
HAZARD | and that line must stay **below** the range-resolution loop, which legitimately needs the git environment. | - | - | This repo-specific ordering constraint is not in git-workflow.md's general rule — stays as HAZARD per instruction.
HAZARD | refuses a push whose `remote_ref` is `refs/heads/master` when the diff carries an executable-class path | - | - | -
HAZARD | is **deliberately narrower** than `sdlc-branch-guard.sh`'s `is_safe_file`, and the exclusions are chosen rather than overlooked | - | - | -
HAZARD | constraints, both load-bearing. The verdict **accumulates in a flag inside the stdin loop and is read after it**, never `exit`ing mid-loop | - | - | -
HAZARD | evaluates the push RANGE, not the tip commit, and the first person to hit that will read it as a false positive.** | - | - | -
HAZARD | is itself executable-class, so a defective guard cannot be repaired by a direct push to master.** | - | - | -
HAZARD | in `tests/scripts/pre_push.bats` push to a feature ref deliberately — do not switch them back to master.** | - | - | -
HAZARD | job (gitleaks) is a backstop, not a substitute for local scanning. Install ggshield: `brew install gitguardian/tap/ggshield && ggshield auth login`. | - | - | -
HAZARD | at the repo root carries **one** suppression, `SC1091`, and the file is byte-identical across the four repos that use the shared minimal config. | - | - | -
DUPLICATE | is structurally unavoidable rather than a preference: the lib architecture resolves source paths at runtime through `$(dirname "${BASH_SOURCE[0]}")`, which does not exist at lint time. | ~/.claude/standards/shell.md | "not yet written. `SC1091` (source path not found) qualifies: the lib architecture resolves..." | Both state the same rationale for the SC1091 suppression — the lib architecture resolves paths at runtime, which lint-time analysis cannot see.
HAZARD | the previous convention, deliberately.** Until 2026-08-08 the file blanket-disabled `SC2086`, `SC2034`, `SC1091` and `SC2181`, and this section described unquoted variables as "intentional style throughout." | - | - | -
HAZARD | was not free. One of the four `SC2181` sites it covered was a real defect: `install_homebrew` ran `xcodebuild -license accept` and `xcodebuild -runFirstLaunch` back to back and then tested `$?` | - | - | -
HAZARD | for any new suppression: | - | - | -
HAZARD | carries a reason on the same line**, and the reason names the mechanism — for `SC2034`, the file and function that consume the variable, not "used elsewhere." | - | - | -
HAZARD | to suppressing.** A variable nothing reads is dead code; annotating it makes it permanent. | - | - | -
HAZARD | is live before writing its reason.** Delete it, re-run shellcheck, and confirm its finding returns. | - | - | -
DUPLICATE | in a file is file-wide**, not scoped to the next command — verified against shellcheck 0.11.0. | ~/.claude/standards/shell.md | "A bare directive before the first non-comment command is file-wide, not next-command" | Both state the identical shellcheck 0.11.0 finding — a bare directive before the first non-comment command applies file-wide, not to the next command.
DUPLICATE | rejects a directive on a `case`-arm line** (`SC1124`). It must precede the whole `case`, which means it covers every arm | ~/.claude/standards/shell.md | "`SC1124` compounds it: a directive cannot sit on a `case`-arm line, so it must precede the whole `case`..." | Both argue SC1124 forces a suppressing directive to precede the whole case statement, covering every arm.
DUPLICATE | scope comes from `scripts/list-shell-files.sh`, not a literal list, not `find`, and not a `git ls-files` pathspec. A pathspec is extension-keyed and cannot express "every tracked shell script" | ~/.claude/standards/shell.md | "A `git ls-files` pathspec cannot express \"every tracked shell script\"" | Both make the same argument — an extension-keyed git ls-files pathspec can't express every tracked shell script, missing extensionless hooks and mocks.
HAZARD | covers `tests/mocks/`, which it did not until this branch.** All 64 mocks tracked at that time were extensionless | - | - | -
HAZARD | does NOT set OS vars, and this bullet said the opposite until 2026-09-10.** It sources `setup_env.sh`, which _defines_ `detect_env` via `lib/detect_env.sh` but returns at its sourcing guard | - | - | -
HAZARD | tests stay off real pip because `load_mocks` exports `MOCK_PYENV_WHICH_STDOUT` by default** (`tests/helpers/common.bash:13`). | - | - | -
HAZARD | in `setup_env.sh` must have a test in `tests/setup_env/unit.bats` (pure logic) or `tests/setup_env/install_guards.bats` (side effects requiring mocks) | - | - | -
HAZARD | to an existing function must update its test | - | - | -
HAZARD | get their own directory under `tests/` (e.g., `tests/scripts/`) | - | - | -
HAZARD | real system state in tests — use PATH-based mocks from `tests/mocks/` | - | - | -
HAZARD | must exit 0 before committing | - | - | -
HAZARD | for PowerShell coding and testing standards. Run tests in this repo from the `powershell/` directory: | - | - | -
HAZARD | (one-time): | - | - | -
HAZARD | 90%. `make test` and CI both fail on any drop below the floor. | - | - | -
HAZARD | `setup_windows.ps1` only. `run-tests.ps1` and `run-lint.ps1` are excluded as test/lint glue (per tdd.md "entry-point glue that purely calls already-tested functions"). | - | - | -
HAZARD | is `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh` and the two extensionless hooks (`scripts/pre-push`, `scripts/commit-msg`), derived from `git ls-files` at run time, less `scripts/bash-tracer.sh`. | - | - | -
HAZARD | was outside the set until 2026-08-09, and the stated reason for that was wrong.** This bullet used to read "nothing under test sources them, so instrumenting them would add only zeros to the denominator." | - | - | -
HAZARD | is the sole remaining exclusion, and it is measured rather than asserted.** `set -x` is its last command, so nothing before it can be traced and nothing follows it to trace. | - | - | -
HAZARD | rather than a filesystem glob is load-bearing, not stylistic.** `config/local.sh` is machine-local and git-ignored, but it exists on developer machines and not on a CI runner | - | - | -
HAZARD | counts commands, not source lines.** bash xtrace emits one line per _command_, so any construct where one command spans several lines inflates the count with lines no test can ever reach. | - | - | -
HAZARD | forms of all four still count. | - | - | -
HAZARD | was tried and removed on evidence, not preference.** The heuristic once dropped lines like `detect_env() {` from the coverable count on the theory that bash doesn't consistently trace them. | - | - | -
HAZARD | is the union of the static heuristic's coverable-line count and whatever the trace file actually contains for that file, never the heuristic alone.** | - | - | -
HAZARD | is now a hard, loud non-zero exit — replacing a silent clamp that had been hiding real over-matches.** | - | - | -
HAZARD | one file's denominator, or a full run's coverage against a real trace, without waiting on the bats suite: | - | - | -
HAZARD | CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview, labelled as one. | - | - | -
HAZARD | via PS4 xtrace (`scripts/run-bash-coverage.sh`). | - | - | -
HAZARD | or publishing a bash coverage figure, or editing `scripts/run-bash-coverage.sh` or `scripts/bash-tracer.sh`, read `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bash-coverage.md` | - | - | -
REFERENCE | for the full `MOCK_*` env var reference table and the usage pattern. | - | - | -
DUPLICATE | so tests that assert actual filesystem state work correctly. Set the corresponding exit var to a non-zero value to simulate failure instead. | ~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md | "Pass-through mocks:" (`ln`, `chmod`, `mv`, `cp`, `tee`) | Near-identical prose describing the same pass-through-mock pattern; CLAUDE.md's copy is the one flagged in the plan as sitting one line below its own pointer to this doc.
DUPLICATE | subprocess strips PATH** — `setup_ansible()`'s pyenv calls need the mock placed at `${HOME}/.pyenv/bin/pyenv`, not PATH-injected. | ~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md | `## \`env -i\` Subprocess Strips PATH — pyenv Mock Placement` | Both argue the same fact — env -i strips PATH so the pyenv mock must be placed at ${HOME}/.pyenv/bin/pyenv rather than PATH-injected.
HAZARD | parses short-option clusters, not just bare `-o`/`--fail`.** Production calls curl as `-fsS -o <file> <url>` and `-fLo <file> <url>` | - | - | Checked against shell.md's curl/-K credential-handling entry; different subject (short-option cluster parsing vs credential escaping). No counterpart. Class HAZARD per instruction.
HAZARD | write is now deferred until after the exit code is decided, and it is a deliberate deviation from real curl.** | - | - | Checked against shell.md's curl entries; no counterpart discusses the mock's deferred -o write semantics. Class HAZARD per instruction.
