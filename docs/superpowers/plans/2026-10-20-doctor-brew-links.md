# doctor brew links Implementation Plan

spec: docs/superpowers/specs/2026-10-20-doctor-brew-links-design.md

> **Status: DONE** — merged as dotfiles#358 (6d7cfb31), 2026-10-21.

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-t doctor` reports dangling Homebrew links and unlinked kegs as one-line WARNs, using Homebrew's own two named `brew doctor` checks.

**Architecture:** One new function, `_doctor_check_brew_links` in `lib/helpers.sh`, called from `run_doctor` after `_doctor_check_gnu_coreutils`. It resolves brew and timeout through seams with fixed fallback paths, runs `brew doctor --quiet <two checks>`, and parses the output in pure bash. `load_mocks` gains two default exports so that no existing test can reach a real brew.

**Tech Stack:** bash, bats, Homebrew 7.0.10 `brew doctor`.

## Global Constraints

- Probe argv exactly: `doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only`, with `HOMEBREW_NO_AUTO_UPDATE=1` and `</dev/null`. Never set `HOMEBREW_NO_INSTALL_FROM_API`.
- `_BREW_FALLBACK_PATHS` default: `/opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew`.
- `_TIMEOUT_FALLBACK_PATHS` default: `/opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout`.
- `_DOCTOR_BREW_TIMEOUT` default 60. Never reuse `_DOCTOR_PROBE_TIMEOUT`.
- WARN only, never `doctor_fail`. Every verdict is one line. Names are capped at 10, then `… <M> more`.
- The check never runs `brew cleanup`, `brew link`, `brew unlink`, `ln` or `rm` (N2). `brew_update` and `-t update` are unchanged (N1, N3).
- Parse in bash (`while IFS= read -r`), not a multi-line single-quoted awk or python body. Those count as coverable lines (CLAUDE.md, Bash coverage).
- Declare `local _out _rc` before assigning. Never write `local _out="$(…)"`.
- Shell style: `[[ ]]`, `${VAR}`, `printf`, functions return through `|| return 1`.

## Verification

- **Session gate.** `make test` exits 0 in the worktree. Baseline 3290 ok, measured 2026-10-20 at `618e8fd2`, 262 s. CI then runs `test`, `test-macos`, `bash-coverage` (≥91%) and `lint-macos`.
- **Feature.** On `claude`, `./setup_env.sh -t doctor` prints `Homebrew links:` followed by `[PASS] brew links` (V2). `env -i HOME="${HOME}" PATH=/usr/bin:/bin bash ./setup_env.sh -t doctor` prints the same PASS, not the skip line (V3).
- **Edge.** With a planted dangling link on the Studio, doctor shows the single-line WARN with the path and `brew cleanup --prune-prefix` (V1(c)). The bats file covers the rest: absence, a non-executable override, timeout, no timeout, rc 3, unrecognised output, progress lines, and the 10-name cap.

## Orchestrator steps

- [ ] **O1. Worktree.**
      `git -C /home/bruce/git-repos/personal/dotfiles worktree add -b feat/doctor-brew-links ../dotfiles-brew-links origin/master`.
      Every task runs in `/home/bruce/git-repos/personal/dotfiles-brew-links/`.
- [ ] **O2. Capture fixtures (V1(a), V1(b)).** This needs the operator's "yes" before each prefix change. On the Studio:
  1. `find -L /opt/homebrew/opt -maxdepth 1 -type l` must print nothing.
  2. `ln -s /nonexistent /opt/homebrew/opt/zz-doctor-probe`.
  3. `HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only </dev/null > /tmp/bl.txt 2>&1; echo rc=$?` must print rc=1.
  4. `rm /opt/homebrew/opt/zz-doctor-probe`, then re-run the `find` and confirm it prints nothing.

  Then pick a `<keg>` that is not keg-only and for which `brew uses --installed <keg>` prints nothing:
  1. `brew unlink <keg>`.
  2. Run the same probe into `/tmp/uk.txt` (rc 1).
  3. `brew link <keg>` must exit 0, and `/opt/homebrew/var/homebrew/linked/<keg>` must exist.

  `scp` both files into the worktree as `tests/fixtures/brew/doctor-broken-symlinks.txt` and `tests/fixtures/brew/doctor-unlinked-kegs.txt`. Commit them in the worktree before Task 2.

- [ ] **O3. After Task 3.** Message the `ai-config` session first (`ListAgents`, `SendMessage`). Then add the four seams to `ai-config/docs/knowledge/dotfiles-test-seams.md` in an ai-config worktree, run `make validate-knowledge`, and push the docs commit direct to ai-config master (R14, knowledge half).
- [ ] **O4.** Run `make test` once more, then Phase 3 (`finishing-a-development-branch`). After merge, run V1(c), V2 and V3.

No ADR: a doctor WARN check is not on `repo-structure.md`'s significance list. It adds no gate, HOLD, schema or guardrail.

---

### Task 1: load_mocks brew defaults

```yaml-task
id: 1
description: load_mocks exports a recording _BREW_BIN stub and a missing _BREW_FALLBACK_PATHS so no test reaches a real brew
role: executor
model: sonnet
tdd: required
requirements: [R12]
acceptance:
  - cmd: bats tests/setup_env/doctor_brew_links.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/helpers/common.bash
  - tests/setup_env/doctor_brew_links.bats
depends_on: []
```

**Files:** `tests/helpers/common.bash` (`load_mocks`, directly after the `_BREW_AZ_BIN` block at `:39-47`) and the new `tests/setup_env/doctor_brew_links.bats`.

**Steps:**

- [ ] Create `doctor_brew_links.bats`. Its `setup()` sets `REPO_ROOT`, sources `tests/helpers/common.bash`, then calls `load_setup_env` and `load_mocks`. It exports `MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"` and points `HOME` at `${BATS_TEST_TMPDIR}/home`. Write the RED tests:
  - `load_mocks: _BREW_BIN is an executable stub under BATS_TEST_TMPDIR`: assert `[[ -x "${_BREW_BIN}" && "${_BREW_BIN}" == "${BATS_TEST_TMPDIR}"/* ]]`.
  - `load_mocks: the _BREW_BIN stub exits 0, prints nothing, logs argv under BATS_TEST_TMPDIR`: run the stub with `doctor x`, then assert status 0, empty output, and that `${BATS_TEST_TMPDIR}/brew-calls` contains `doctor x`.
  - `load_mocks: _BREW_FALLBACK_PATHS names only a missing path under BATS_TEST_TMPDIR`.
  - `load_mocks: both are exported`: `bash -c 'printf "%s|%s" "${_BREW_BIN}" "${_BREW_FALLBACK_PATHS}"'` prints both values non-empty.
- [ ] Run the file and confirm RED.
- [ ] Add to `load_mocks`:
  - `export _BREW_BIN="${BATS_TEST_TMPDIR:-/nonexistent}/brew-stub"`. When `BATS_TEST_TMPDIR` is non-empty, write a `#!/usr/bin/env bash` stub there that runs `printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/brew-calls"` and `exit 0`. Hard-code the log path at heredoc-write time (unquoted heredoc, or `printf` the path in), never `${MOCK_CALLS_FILE:-/tmp/...}`. Then `chmod +x`.
  - `export _BREW_FALLBACK_PATHS="${BATS_TEST_TMPDIR:-/nonexistent}/no-brew"`.
  - A why-comment in the style of the `_BREW_AZ_BIN` block: every CI and fleet machine has a real brew at a default fallback path (`claude`, the ubuntu image off `PATH`, the macOS runner), and `unit.bats:555`, `:1472` and `:1960` reach the check through a subprocess, so both must be `export`.
- [ ] GREEN on the file, then `make test`. The baseline is 3290 ok, so expect 3294.
- [ ] Commit (`caveman:caveman-commit`).

**Interfaces:** Produces `_BREW_BIN` (stub path; log at `${BATS_TEST_TMPDIR}/brew-calls`) and `_BREW_FALLBACK_PATHS`. Task 2's tests override both per test.

---

### Task 2: _doctor_check_brew_links

```yaml-task
id: 2
description: Add _doctor_check_brew_links (resolution, bounded quiet probe, one-line WARN parsing) and call it from run_doctor
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R13]
acceptance:
  - cmd: bats tests/setup_env/doctor_brew_links.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/doctor_brew_links.bats
depends_on: [1]
```

**Files:** `lib/helpers.sh`. Put the new function after `_doctor_check_gnu_coreutils` (`:1240`), and add the call to `run_doctor`'s list after `_doctor_check_gnu_coreutils` (`:522`). Tests go in `doctor_brew_links.bats`. Fixtures in `tests/fixtures/brew/` come from O2. Do not edit them.

Read spec § Unit, § Probe, § Parsing, § Verdicts and § Tests in full. They are the contract.

**Steps.** Run one behaviour at a time: RED, then GREEN.

- [ ] For stubs, add a `_write_brew_stub <rc> <fixture-or-text> [sleep]` helper. It writes `${BATS_TEST_TMPDIR}/brew` that logs argv to `${BATS_TEST_TMPDIR}/brew-calls`, cats the fixture, optionally sleeps, and exits rc. Export `_BREW_BIN` to it.
- [ ] Build the scoped-`PATH` tests the way `doctor_dev_tools.bats:12-60` does: a `_BIN_DIR` of symlinks to the real tools the function calls, and `PATH="${_BIN_DIR}"` prefixed on the single call. Locate the real `timeout` with `command -v`, with an explicit `skip` when it is absent.
- [ ] Write these cases in order:
  - Absent everywhere: skip line, counters unchanged.
  - `command -v` wins over the fallback list.
  - Fallback used.
  - Non-executable `_BREW_BIN`: WARN, empty call log.
  - rc 0: one PASS, and the call log is exactly `doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only`.
  - Broken-symlinks fixture: one WARN line with the planted path and `brew cleanup --prune-prefix`.
  - Unlinked-kegs fixture: one WARN line with the keg and `brew link <keg>`.
  - Both fixtures: exactly 2 WARN lines.
  - Progress-prefixed fixture: same WARN.
  - Unrecognised output: detail is `brew doctor rc 1: Warning: Something new`.
  - Timeout: `_DOCTOR_BREW_TIMEOUT=1`, sleeping stub, `did not finish`.
  - No timeout, with `_TIMEOUT_FALLBACK_PATHS` missing: PASS and no `rc 127`.
  - Timeout via fallback: a recording wrapper logs the bound `60`.
  - rc 3.
  - 12 paths: 10 shown and `… 2 more`.
  - 12 kegs: 10 shown, `… 2 more`, and the `brew link` command names all 12.
  - `run_doctor` calls the check. Stub `_doctor_check_brew_links` to touch a file.
  - Every verdict: assert `"${output}"` has no line starting `[WARN]` that is followed by a line without the two-space indent, and no `doctor_fail`, by checking that `_DOCTOR_FAIL` stays 0.
- [ ] Mutation control. Delete `--quiet` from the argv, confirm the rc-0 test goes red, then restore it. Separately, swap the keg anchor to the header line, confirm the unlinked-kegs test goes red, then restore it. Report both.
- [ ] `make test`. Commit.

**Interfaces:** Consumes Task 1's exports. Produces `_doctor_check_brew_links` (no arguments; calls `doctor_pass` or `doctor_warn`; returns 0) and the seams `_BREW_BIN`, `_BREW_FALLBACK_PATHS`, `_TIMEOUT_FALLBACK_PATHS` and `_DOCTOR_BREW_TIMEOUT`.

---

### Task 3: CLAUDE.md seam rule and backlog close

```yaml-task
id: 3
description: Docs-only (no behaviour change, so no TDD) - one-line CLAUDE.md Test Seams rule for the four brew seams, close the P1 backlog row, mark the plan index row
role: executor
model: sonnet
tdd: not-applicable
requirements: [R14]
acceptance:
  - cmd: 'grep -qE "_BREW_BIN.*_BREW_FALLBACK_PATHS.*_TIMEOUT_FALLBACK_PATHS.*_DOCTOR_BREW_TIMEOUT" CLAUDE.md'
    exit_code: 0
  - cmd: '! command grep -q "^| nothing reports dangling Homebrew links or unlinked kegs |" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [2]
```

**Files:**

- `CLAUDE.md` § Test Seams: add one bullet after the `_DOCTOR_PROBE_TIMEOUT` bullet. The bullet says: drive brew absence and resolution only through `_BREW_BIN` and `_BREW_FALLBACK_PATHS` (`load_mocks` stubs both), and the timeout only through `_TIMEOUT_FALLBACK_PATHS` and `_DOCTOR_BREW_TIMEOUT`; never edit `PATH`. It ends `→ \`dotfiles-test-seams.md\` § \`doctor brew links seams\``.
- `docs/superpowers/README.md`:
  - Delete the backlog row `nothing reports dangling Homebrew links or unlinked kegs`.
  - In the All Plans table, set the 2026-10-20 row's plan cell to `[doctor brew links](plans/2026-10-20-doctor-brew-links.md)` and its status to `Done — merged as dotfiles#<n>`. `<n>` comes from the orchestrator.

The `make test` gate stays because the suite reads `CLAUDE.md` (relocation and phrase manifests).

## Non-goal check

Reviewer: one fresh subagent run on 2026-10-20 against N1-N4. Inputs were `nongoal-check.md`, this plan and the spec's N list.

- N1: CLEAR.
- N2: CLEAR. The reviewer noted that O2's `ln -s`, `rm`, `brew unlink` and `brew link` are manual orchestrator steps gated by the operator, not the shipped check.
- N3: CLEAR.
- N4: CLEAR.

Resolution: none needed. No plan revision and no amendment.
