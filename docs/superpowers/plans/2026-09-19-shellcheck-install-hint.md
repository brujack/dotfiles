# Platform-Aware shellcheck Install Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make lint`'s "shellcheck not found" hint names the real install path per platform, so following it on Linux never creates an unmanaged linuxbrew copy ahead of the pinned `/usr/local/bin/shellcheck`.

**Architecture:** One `printf` in the Makefile's lint skip branch chooses its hint from `$${_OVERRIDE_PLATFORM:-$$(uname -s)}`. Two bats cases drive the skip branch with `make lint SHELLCHECK=`.

**Tech Stack:** GNU Make, bash, bats.

**Spec:** `docs/superpowers/specs/2026-09-19-doctor-shellcheck-pin-design.md` (approved at `b6a5548d`).

## Global Constraints

- Darwin hint: `install: brew install shellcheck` (unchanged text).
- Every other platform: `install: ./setup_env.sh -t developer on Ubuntu (installs the pinned SHELLCHECK_VER)`.
- Test invocations use `env PATH="${CLEAN_PATH}" make --no-print-directory -C "${REPO_ROOT}" lint SHELLCHECK=`, which is the guarded form required by the MAKEFLAGS stdout partition.
- `make test` exceeds the 600s Bash cap, so task gates are scoped. The orchestrator runs `make test` once after Task 2.

## Verification (session level)

- `bats -f "lint skip hint" tests/scripts/makefile_lint_scope.bats` prints `1..2`, both ok.
- Mutations that must turn a case red: swapping the two hints (both red); printing either hint unconditionally (the other case red).
- `make test` green (orchestrator, after Task 2).
- On `claude`: `make lint SHELLCHECK=` prints the `-t developer` hint.

---

### Task 1: Platform-aware skip hint and its tests

```yaml-task
id: 1
description: Make lint's shellcheck skip hint platform-aware, with Linux and Darwin bats cases asserting presence and absence
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats -f "lint skip hint" tests/scripts/makefile_lint_scope.bats'
    exit_code: 0
    stdout_match: "^1\\.\\.2$"
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [Makefile, tests/scripts/makefile_lint_scope.bats]
depends_on: []
```

**Files:** `Makefile` (line ~105, the `else` arm of `if [ -n "$(SHELLCHECK)" ]` in `lint`), `tests/scripts/makefile_lint_scope.bats`.

**Steps:**

- [ ] Append two tests to `tests/scripts/makefile_lint_scope.bats`, using the file's `setup()` variables `REPO_ROOT` and `CLEAN_PATH`:

```bash
@test "lint skip hint names setup_env.sh -t developer on non-Darwin" {
  run env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    _OVERRIDE_PLATFORM=Linux PATH="${CLEAN_PATH}" \
    make --no-print-directory -C "${REPO_ROOT}" lint SHELLCHECK=
  [[ "${output}" == *"shellcheck not found, skipping"* ]]
  [[ "${output}" == *"./setup_env.sh -t developer on Ubuntu"* ]]
  [[ "${output}" != *"brew install shellcheck"* ]]
}

@test "lint skip hint names brew install shellcheck on Darwin" {
  run env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    _OVERRIDE_PLATFORM=Darwin PATH="${CLEAN_PATH}" \
    make --no-print-directory -C "${REPO_ROOT}" lint SHELLCHECK=
  [[ "${output}" == *"shellcheck not found, skipping"* ]]
  [[ "${output}" == *"brew install shellcheck"* ]]
  [[ "${output}" != *"setup_env.sh -t developer"* ]]
}
```

No `status` assertion: the skip branch does not fail lint, but other lint steps can, and those are not what these cases test.

- [ ] Run `bats -f "lint skip hint" tests/scripts/makefile_lint_scope.bats`. Expect the Linux case red (the current hint is `brew install shellcheck`) and the Darwin case green.
- [ ] Replace the `printf "shellcheck not found, skipping (install: brew install shellcheck)\n";` line with:

```make
	  if [ "$${_OVERRIDE_PLATFORM:-$$(uname -s)}" = Darwin ]; then \
	    printf "shellcheck not found, skipping (install: brew install shellcheck)\n"; \
	  else \
	    printf "shellcheck not found, skipping (install: ./setup_env.sh -t developer on Ubuntu (installs the pinned SHELLCHECK_VER))\n"; \
	  fi; \
```

Keep the recipe's tab indentation and trailing `\` continuations exactly.

- [ ] Re-run the filter: both ok. Run `make lint`: exit 0.
- [ ] Mutation proof. In the implementer report, state the result of each:
  1. swap the two hint strings: both cases red;
  2. make the `if` always true, so Darwin text prints everywhere: the Linux case red;
  3. make the `if` always false: the Darwin case red.

  Restore with `git diff --quiet Makefile` confirmed before committing.

- [ ] Commit (`caveman:caveman-commit`), type `fix`, message about the Linux hint pointing at an unmanaged install.

**Interfaces:** Produces the `_OVERRIDE_PLATFORM` recipe seam, which Task 2 documents.

### Task 2: Document the hint and its seam in CLAUDE.md

```yaml-task
id: 2
description: Document the platform-aware lint skip hint and _OVERRIDE_PLATFORM in CLAUDE.md (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_OVERRIDE_PLATFORM" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "setup_env.sh -t developer on Ubuntu" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md]
depends_on: [1]
```

**Files:** `CLAUDE.md`, the Testing section's `**Run lint only:**` paragraph.

**Steps:**

- [ ] Append to that paragraph: "When `shellcheck` is absent the lint step skips it and prints an install hint that names the platform's real path: `brew install shellcheck` on Darwin, and `./setup_env.sh -t developer on Ubuntu` elsewhere, because a `brew install` on Linux would put an unmanaged linuxbrew copy ahead of the pinned `/usr/local/bin/shellcheck`. The recipe reads `_OVERRIDE_PLATFORM` (default `uname -s`) so one machine can test both branches; it changes only the printed string."
- [ ] Commit, type `docs`.
