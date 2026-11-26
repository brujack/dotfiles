# Pinned uv for the requirements renderings Implementation Plan

> **Status: DONE** (#463, merged 2026-11-19)

spec: docs/superpowers/specs/2026-11-19-pinned-uv-renderings-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `check-requirements-ci`, `sync-requirements-ci` and `check-lock` run under the pinned
`uv` 0.13.0 at `~/.local/share/dotfiles/pinned/uv-${UV_VER}/uv`, never brew's, and fail closed
when it is absent.

**Architecture:** Pins in `lib/constants.sh`; `_uv_pinned_asset` and `resolve_pinned_uv` in
`lib/helpers.sh`; platform installers reuse `_install_pinned_release_binary` (new `targz` kind,
`mkdir -p` first); one dispatcher `install_uv_pinned` feeds setup, a `pinned-uv` update section and
`make install-pinned-uv`; the two Makefile check targets resolve in-recipe; CI exports
`PINNED_UV_BIN` and a per-job test keeps its pins equal to the constants.

**Tech Stack:** bash, GNU Make, bats, GitHub Actions YAML.

## Global Constraints

- No change to `PATH` in any shell startup file, hook or Makefile (N1).
- No removal or pinning of brew's `uv`; no `Brewfile` change (N2).
- The venv `uv sync` callers keep `resolve_uv`; `scripts/refresh-uv-lock.sh`'s own `_UV_BIN` calls are untouched (N3).
- `UV_VER` stays `0.13.0`; no `requirements-ci*.txt` is re-rendered (N4).
- No network inside `make test`: every installer test uses `tests/mocks/curl` with `MOCK_CURL_STDOUT` (N5).
- Never mock `sha256sum`; supply the real digest of the fixture bytes (CLAUDE.md).
- Every new `.bats` file is added to `tests/bats-files.txt` in the same commit (`git ls-files '*.bats' | LC_ALL=C sort`).
- Per-task gates are scoped bats files plus `make lint`. The full suite exceeds the 600 s Bash cap, so the
  orchestrator runs `make test < /dev/null` once after Task 7 and once after Task 9.
- Pre-provisioned 2026-11-19: claude, studio, workstation and laptop already hold
  `~/.local/share/dotfiles/pinned/uv-0.13.0/uv`, so local `make test` stays green throughout.

## Verification

- Session gate: `make test < /dev/null` exits 0 in the worktree after Task 7 and after Task 9, and its
  log contains `OK: requirements-runtime-ci.txt matches uv.lock` with brew `uv` 0.13.9 first on `PATH`.
- Negative: `PINNED_UV_BIN=/nonexistent make check-lock` exits non-zero printing
  `pinned uv not found at /nonexistent; run make install-pinned-uv`.
- Swap control (R17) and zero-match control (R16) are tests in the suite.
- After merge: V1 on claude, V2 on the Studio, V3 from the PR's CI logs.

---

### Task 1: Pins and refresh support

```yaml-task
id: 1
description: Add UV_VER and the two UV_SHA256 pins to lib/constants.sh and teach refresh-sha256-pins.sh the uv tool, TDD
role: executor
model: sonnet
tdd: required
requirements: [R1, R2]
acceptance:
  - cmd: 'bats tests/scripts/refresh_sha256_pins.bats'
    exit_code: 0
  - cmd: 'bash -c "source lib/constants.sh; [[ $UV_VER == 0.13.0 && $UV_SHA256_FOR_VER == 0.13.0 && -z ${UV_SHA256_LINUX_ARM64+x} ]]"'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, scripts/refresh-sha256-pins.sh, tests/scripts/refresh_sha256_pins.bats]
depends_on: []
```

- [ ] In `lib/constants.sh`, beside the shellcheck pins, add `UV_VER="0.13.0"`,
      `UV_SHA256_LINUX_AMD64="1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154"`,
      `UV_SHA256_DARWIN_ARM64="a9c1b29002cf3c83f07fa9cd8a887a3be0107d90e23189721221e7257db8e3d6"`,
      `UV_SHA256_FOR_VER="0.13.0"`, each with a `# read by ...` comment naming its readers. No Linux arm64 pin.
- [ ] Failing test first in `tests/scripts/refresh_sha256_pins.bats`: `refresh-sha256-pins.sh uv` against a
      fixture constants file rewrites `UV_SHA256_LINUX_AMD64`, `UV_SHA256_DARWIN_ARM64` and
      `UV_SHA256_FOR_VER` (follow the existing kind/yq cases' seams; read the script first). uv's two pins
      are keyed by asset (`uv-x86_64-unknown-linux-gnu.tar.gz`, `uv-aarch64-apple-darwin.tar.gz`), not by a
      generic amd64/arm64 pair, so do not route uv through `_release_asset_sha`'s arch table; add uv's own mapping.
- [ ] Add `uv` to the script's accepted tools and usage line; make the test pass. Commit (`caveman:caveman-commit`).

**Interfaces:** Produces `UV_VER`, `UV_SHA256_LINUX_AMD64`, `UV_SHA256_DARWIN_ARM64`, `UV_SHA256_FOR_VER`.

### Task 2: Installer gains targz and mkdir

```yaml-task
id: 2
description: Add the targz kind and a pre-writability mkdir -p to _install_pinned_release_binary, TDD
role: executor
model: sonnet
tdd: required
requirements: [R3, R4, R5]
acceptance:
  - cmd: 'bats tests/setup_env/release_binary.bats tests/setup_env/shellcheck_pin.bats tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ _install_pinned_release_binary: targz installs uv and not uvx'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/release_binary.bats]
depends_on: []
```

- [ ] Failing tests in `tests/setup_env/release_binary.bats` (reuse its seams: `_RELEASE_BIN_DIR`,
      `_RELEASE_TMP_ROOT`, `MOCK_CURL_STDOUT` with a real `.tar.gz` fixture built in the test and its real
      digest): (a) test named `_install_pinned_release_binary: targz installs uv and not uvx`: kind `targz` for an archive holding `pkg/uv` and `pkg/uvx` installs `uv` only; (b) a
      missing `_RELEASE_BIN_DIR` under `BATS_TEST_TMPDIR` is created and the recording `sudo` shim sees no
      call; (c) an unknown kind still errors.
- [ ] In `lib/linux_ubuntu.sh:_install_pinned_release_binary`, add the `targz` arm (`tar -xzf`, then the
      `tarxz` arm's find-by-name step) and `mkdir -p "${_dir}"` before `[[ -w "${_dir}" ]]`, as the invoking
      user, failing with `log_error "${_name}: cannot create ${_dir}"` and the tmp cleanup. The function stays
      in this file; shellcheck/tflint/tfsec callers are not edited.
- [ ] Tests pass; existing cases unchanged. Commit.

**Interfaces:** Produces kind `targz` for `_install_pinned_release_binary <name> <ver> <url> <sha> <kind> <regex>`.

### Task 3: Asset table and resolver

```yaml-task
id: 3
description: Add _uv_pinned_version_regex, _uv_pinned_asset and resolve_pinned_uv to lib/helpers.sh with a new tests/setup_env/pinned_uv.bats, TDD
role: executor
model: sonnet
tdd: required
requirements: [R8, R10, R11, R12]
acceptance:
  - cmd: 'bats tests/setup_env/pinned_uv.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ resolve_pinned_uv: rejects uv 0.13.01'
  - cmd: make check-bats-manifest
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/pinned_uv.bats, tests/bats-files.txt]
depends_on: [1]
```

- [ ] New `tests/setup_env/pinned_uv.bats` (source `lib/constants.sh` and `lib/helpers.sh`; `HOME` at
      `BATS_TEST_TMPDIR`). Stubs are scripts written per test under `BATS_TEST_TMPDIR`, reached only
      through `PINNED_UV_BIN`. One test at a time, RED then GREEN:
  - absent file: rc 2, `pinned uv not found at <path>; run make install-pinned-uv`
  - non-executable: rc 1, `pinned uv at <path> is not executable`
  - `uv 0.13.9`: rc 1, `pinned uv at <path> reports uv 0.13.9, expected uv 0.13.0`
  - test named `resolve_pinned_uv: rejects uv 0.13.01`: rc 1
  - `UV_VER=""`: rc 1, `UV_VER is not set; source lib/constants.sh`
  - `uv 0.13.0 (x86_64-unknown-linux-gnu)`: rc 0, stdout is exactly the path
  - unset `PINNED_UV_BIN`: path is `${HOME}/.local/share/dotfiles/pinned/uv-0.13.0/uv`
  - a stub `uv 0.13.0` first on `PATH` and no file at the pinned path: still rc 2
  - `_uv_pinned_asset Linux x86_64` prints `uv-x86_64-unknown-linux-gnu <sha>`; `Darwin arm64` prints the
    darwin asset and sha; `Linux aarch64` and `Darwin x86_64` return 1 and print nothing.
- [ ] Implement in `lib/helpers.sh`: `_uv_pinned_version_regex` (prints `^uv 0\.13\.0( |$)` from `UV_VER`),
      `_uv_pinned_asset <uname -s> <uname -m>`, `resolve_pinned_uv` (messages on stderr). Before the file's
      sourcing guard. Add the file to `tests/bats-files.txt`. Commit.

**Interfaces:** Produces `resolve_pinned_uv` (rc 0/1/2, path on stdout), `_uv_pinned_asset <os> <machine>`
(`<asset> <sha>`, rc 1 unsupported), `_uv_pinned_version_regex`.

### Task 4: Platform installers and setup call sites

```yaml-task
id: 4
description: Add _install_ubuntu_uv_pinned, install_uv_pinned_macos and the install_uv_pinned dispatcher, called from setup on both platforms, TDD
role: executor
model: sonnet
tdd: required
requirements: [R6, R7, R19]
acceptance:
  - cmd: 'bats tests/setup_env/pinned_uv.bats tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ install_uv_pinned: Linux x86_64 installs the versioned pinned uv'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, lib/linux_ubuntu.sh, lib/macos.sh, lib/workflows.sh, tests/setup_env/pinned_uv.bats]
depends_on: [2, 3]
```

- [ ] Failing tests in `tests/setup_env/pinned_uv.bats`, with `tests/mocks` on `PATH`, `MOCK_CURL_STDOUT` a
      real `.tar.gz` fixture, and the digest override seam the installer exposes
      (`_UV_PINNED_SHA256`, mirroring `_SHELLCHECK_SHA256`) set to that fixture's real digest:
  - test named `install_uv_pinned: Linux x86_64 installs the versioned pinned uv`: `install_uv_pinned` on Linux x86_64 installs to `${HOME}/.local/share/dotfiles/pinned/uv-0.13.0/uv` from
    the `uv-x86_64-unknown-linux-gnu.tar.gz` URL (assert via `MOCK_CURL_*` call log)
  - the same on Darwin arm64 with the darwin URL (`_OVERRIDE_PLATFORM`/`_UNAME_M` seams, whichever the
    libs already honour; read them)
  - unsupported arch: `log_warn`, rc 0, no curl call
  - after the call, `_RELEASE_BIN_DIR` is unset in the test shell
- [ ] Implement: `_install_ubuntu_uv_pinned` (linux_ubuntu.sh), `install_uv_pinned_macos` (macos.sh), both
      calling `_install_pinned_release_binary uv` with `_RELEASE_BIN_DIR=... ` as a command prefix only, URL
      `https://github.com/astral-sh/uv/releases/download/${UV_VER}/<asset>`, kind `targz`, regex from
      `_uv_pinned_version_regex`. `install_uv_pinned` (helpers.sh) dispatches on `uname -s`, like `install_bats`.
- [ ] Call sites: Linux after `_install_ubuntu_shellcheck` in `_install_ubuntu_misc` (`lib/linux_ubuntu.sh:2370`),
      gated `[[ -n ${HAS_DEVTOOLS} ]]`, `|| log_warn "pinned uv install failed; skipping"`; macOS after
      `install_macos_casks` in `lib/workflows.sh:745`, same gate and warn. Commit.

**Interfaces:** Produces `install_uv_pinned` (rc 0 installed/skipped/unsupported, 1 failed).

### Task 5: pinned-uv update section

```yaml-task
id: 5
description: Add the pinned-uv -t update section in full runs, with its section-order entry and skip/FAIL mapping, TDD
role: executor
model: sonnet
tdd: required
requirements: [R9]
acceptance:
  - cmd: 'bats tests/setup_env/update_summary.bats tests/setup_env/workflows.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ run_update: pinned-uv skips without HAS_DEVTOOLS'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, lib/update_summary.sh, tests/setup_env/workflows.bats]
depends_on: [4]
```

- [ ] Failing tests in `tests/setup_env/workflows.bats` (follow the cargo-tools section tests; stub
      `install_uv_pinned` with a recording function): test named `run_update: pinned-uv skips without HAS_DEVTOOLS`: `HAS_DEVTOOLS` unset records skip
      `HAS_DEVTOOLS not set` and makes no call; unsupported platform (`_uv_pinned_asset` rc 1) records skip
      `no pinned uv for <os> <machine>` and makes no call; stub rc 1 records FAIL; stub rc 0 records OK;
      `--brew-only` does not reach the section.
- [ ] Implement in `run_update` after the cargo-tools block, inside `if [[ ${_run_all} -eq 1 ]]`, with
      `_update_record_start "pinned-uv"` / `_update_record_end "pinned-uv" "${rc}"` and the `tee` to
      `err_pinned-uv` used by peers; else `_update_skip "pinned-uv" "flag not set"`. Add `pinned-uv` after
      `cargo-tools` in `_UPDATE_SECTION_ORDER`. Commit.

### Task 6: Sync script uses the pinned uv

```yaml-task
id: 6
description: scripts/sync-requirements-ci.sh sources constants and resolves only the pinned uv; migrate its UV_BIN tests and add the PATH-versus-pinned swap control, TDD
role: executor
model: sonnet
tdd: required
requirements: [R13, R17]
acceptance:
  - cmd: 'bats tests/setup_env/requirements_ci.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ check reads the pinned uv, not PATH'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [scripts/sync-requirements-ci.sh, tests/setup_env/requirements_ci.bats]
depends_on: [3]
```

- [ ] Failing test `check reads the pinned uv, not PATH`: a `PATH` stub `uv` whose `export` output
      renders the `pywinpty ... and sys_platform != 'linux'` marker and a `PINNED_UV_BIN` stub (reporting
      `uv 0.13.0`) that emits the committed rendering's body; `check` prints five `OK:`. A second test swaps
      them and expects `DRIFT: requirements-runtime-ci.txt`. Point the targets at fixtures via
      `REQUIREMENTS_*_TARGET`, never the tracked files.
- [ ] Migrate the existing `UV_BIN` cases (~:459, ~:492) to `PINNED_UV_BIN`; the resolution-failure case now
      expects `pinned uv not found` (absent) or `is not executable`, still distinct from drift.
- [ ] In the script: source `lib/constants.sh` before `lib/helpers.sh`; replace `resolve_uv` with
      `resolve_pinned_uv`. Commit.

### Task 7: Makefile targets

```yaml-task
id: 7
description: check-requirements-ci and check-lock resolve the pinned uv in-recipe and fail closed; add make install-pinned-uv; update makefile_lint_scope.bats, TDD
role: executor
model: sonnet
tdd: required
requirements: [R14, R18]
acceptance:
  - cmd: 'bats tests/scripts/makefile_lint_scope.bats tests/setup_env/pinned_uv.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ make install-pinned-uv: installs without HAS_DEVTOOLS'
  - cmd: 'bash -c "PINNED_UV_BIN=/nonexistent make check-lock 2>&1 | grep -q \"pinned uv not found at /nonexistent; run make install-pinned-uv\""'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [Makefile, tests/scripts/makefile_lint_scope.bats, tests/setup_env/pinned_uv.bats]
depends_on: [4, 6]
```

- [ ] Failing tests: rc 2 and rc 1 stubs each make both targets exit non-zero with the resolver's message,
      with and without `REQUIRE_TOOLS=1`; `make lint` makes no call to a recording `PINNED_UV_BIN` stub while
      `make check-lock` does (positive control); test named `make install-pinned-uv: installs without HAS_DEVTOOLS`: `make install-pinned-uv` with `HAS_DEVTOOLS` unset installs
      from the mocked curl into `${HOME}` (fixture `HOME`, `_RELEASE_TMP_ROOT`, digest seam as Task 4).
- [ ] In `tests/scripts/makefile_lint_scope.bats`: delete the uv rows from the skip loop and refuse loop
      (counts 18 to 12 and 6 to 4 — state the before/after in the commit body); the inert case (~:1423)
      guards on `resolve_pinned_uv` instead of `command -v uv`; drop the `:1300` `ifeq ($(UV),)` assertion
      and replace it with one that `check-lock`'s recipe calls `resolve_pinned_uv`.
- [ ] `Makefile`: remove `UV := $(shell command -v uv ...)`, both `ifeq ($(UV),)` branches and
      `REQUIRE_TOOLS_FROM_UV` if now unused. Measured 2026-11-19: `$(UV)` appears only at `Makefile:350,370,374`,
      all inside these two targets; re-run `git grep -n '$(UV)' Makefile` first and stop if any other user exists. Each recipe runs one `bash -c` sourcing `lib/constants.sh` and
      `lib/helpers.sh`, `uv="$(resolve_pinned_uv)" || exit 1`, then `"$uv" lock --check` /
      `./scripts/sync-requirements-ci.sh check`. Add `install-pinned-uv` (sources constants, helpers,
      linux_ubuntu, plus macos on Darwin; runs `install_uv_pinned`) to `.PHONY` and the help text. Commit.
- [ ] Orchestrator: `make test < /dev/null` after this task (session gate).

### Task 8: CI env and pin-equality test

```yaml-task
id: 8
description: Set PINNED_UV_BIN in the three pinned-uv jobs and add a per-job bats test that their UV_VER/UV_SHA256 equal lib/constants.sh, TDD
role: executor
model: sonnet
tdd: required
requirements: [R15, R16]
acceptance:
  - cmd: 'bats tests/scripts/ci_uv_pin.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ ci_uv_pin: a mismatched fixture workflow fails'
  - cmd: make check-bats-manifest
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [.github/workflows/ci.yml, .github/workflows/uv-lock-refresh.yml, tests/scripts/ci_uv_pin.bats, tests/bats-files.txt]
depends_on: [1]
```

- [ ] New `tests/scripts/ci_uv_pin.bats`: parse each workflow per job (python3 with `yaml.safe_load` if
      available in the suite's python, else the job-block awk pattern existing CI tests use; read
      `tests/scripts/ci_runner_pins.bats` first). Assert exactly three `UV_VER` values in total, each equal to
      `UV_VER`; Linux-asset jobs' `UV_SHA256` equals `UV_SHA256_LINUX_AMD64`, the macOS job's equals
      `UV_SHA256_DARWIN_ARM64`; each of the three jobs has `PINNED_UV_BIN: /usr/local/bin/uv` in its job `env:`.
      Zero matches fails. A fixture workflow with a wrong `UV_VER` fails (test name in the gate).
- [ ] Add `PINNED_UV_BIN: /usr/local/bin/uv` to job `env:` of `test-shard`, `test-macos-shard` and the
      `uv-lock-refresh.yml` job. Add the file to `tests/bats-files.txt`. Commit.

### Task 9: Docs

```yaml-task
id: 9
description: CLAUDE.md seam line, backlog row closed and plan index row (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R20]
acceptance:
  - cmd: 'grep -q "PINNED_UV_BIN" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "uv. ships unpinned.*CLOSED 2026-11-19" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make check-claude-md-budget
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [7, 8]
```

- [ ] `CLAUDE.md` Testing section: one line beside the `UV_BIN` bullet — the requirements renderings and
      `check-lock` use only the pinned uv (`resolve_pinned_uv`, seam `PINNED_UV_BIN`), absent fails closed,
      remedy `make install-pinned-uv` — with a pointer `→ dotfiles-test-seams.md § pinned uv seam`. Keep under
      the budget (`make check-claude-md-budget`).
- [ ] `docs/superpowers/README.md`: mark the backlog row "`uv` ships unpinned ..." `CLOSED 2026-11-19`,
      citing the spec; set the plan index row's plan link and status. Commit.
- [ ] Orchestrator, before Phase 3 (writing-plans item 12): ask the ai-config session to add
      `## pinned uv seam` to `ai-config/docs/knowledge/dotfiles-test-seams.md`, then run `make test < /dev/null`.

## Non-goal check

Reviewer verdicts (2026-11-19): N1 CLEAR, N2 CLEAR, N3 UNCLEAR, N4 CLEAR, N5 CLEAR.

- **N3 UNCLEAR** — quote: "Task 7: `Makefile`: remove `UV := $(shell command -v uv ...)`, both `ifeq ($(UV),)` branches and `REQUIRE_TOOLS_FROM_UV` if now unused." Why: another recipe might use `$(UV)`.
  Resolution: plan revised. Measured `git grep -nE '\$\(UV\)' -- Makefile tests scripts .github`: only `Makefile:350,370,374`, all in `check-requirements-ci` and `check-lock`; the venv `uv sync` callers are in `lib/` and use `resolve_uv`. Task 7 text before: "remove `UV := ...`, both `ifeq ($(UV),)` branches and `REQUIRE_TOOLS_FROM_UV` if now unused." After: the same, plus "Measured 2026-11-19: `$(UV)` appears only at `Makefile:350,370,374` ...; re-run `git grep -n '$(UV)' Makefile` first and stop if any other user exists."
