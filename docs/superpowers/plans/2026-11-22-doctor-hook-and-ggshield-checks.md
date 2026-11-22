# Doctor checks for installed hooks and ggshield authentication — Implementation Plan

spec: docs/superpowers/specs/2026-11-22-doctor-hook-and-ggshield-checks-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `setup_env.sh -t doctor` reports, per listed repo, whether the three mandated hooks are installed and are that repo's own scripts (or a runnable pre-commit shim), and whether ggshield resolves and holds a working API key.

**Architecture:** One identity helper in `lib/git_hooks.sh` (`_git_hooks_identity`), two doctor arms in `lib/helpers.sh` (`_doctor_check_git_hooks`, `_doctor_check_ggshield`) wired into `run_doctor` after `_doctor_check_hooks_path`. Nothing writes; the hook scripts and the repair sweep are untouched.

**Tech Stack:** bash, bats, git plumbing (`ls-files`, `rev-parse`, `worktree list --porcelain`), `cmp`, `timeout`.

## Global Constraints

- Every message, rc and branch condition is copied verbatim from the spec's R-lines; the spec is authoritative where this plan paraphrases.
- `doctor_fail`/`doctor_warn` take two arguments (`"<subject>" "<message>"`); `doctor_pass` takes one.
- Every git call that builds paths or decides scope uses `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C ...`.
- The shim's `INSTALL_PYTHON` is read as text only: never `source`, `eval`, or unquoted expansion.
- No test reaches the real `ggshield`, the network, or the operator's real repos under `~/git-repos/personal`.
- `scripts/pre-commit-hook.sh` and `_git_hooks_check_complete` are not edited (R15).
- Shell style per `~/.claude/standards/shell.md`: `local`, `${VAR}`, `printf`, `|| return 1`, no `set -e`.
- Adding a `.bats` file needs the same line in `tests/bats-files.txt` (`git ls-files '*.bats' | LC_ALL=C sort`).
- `make test` runs under 10 minutes on `claude` (measured 2026-11-22: about 4 min at `JOBS=12`), so task gates may run it.

## Verification (session level)

- `make test` exit 0 on the branch; CI green including all three `test-macos-shard` legs (V4).
- On `claude`: `./setup_env.sh -t doctor` prints exactly one hook FAIL, for state-ledger's `pre-commit` (`INSTALL_PYTHON /Users/bruce/.pyenv/versions/ansible/bin/python missing`), every other repo PASS, ggshield `authenticated` (V1). After the operator approves `cd ~/git-repos/personal/state-ledger && pre-commit install`, a re-run shows state-ledger PASS.
- `GITGUARDIAN_API_KEY=invalid-fixture-key ./setup_env.sh -t doctor`: ggshield FAIL `rc 128` (V2). `HTTPS_PROXY=http://127.0.0.1:9 ./setup_env.sh -t doctor`: ggshield WARN (V5).
- Studio and `workstation`: hook verdicts match the Step 8 survey, 9 PASS each (V3).
- Edge cases exercised by tests: zero repos found, empty `HOOK_EXPECTED_REPOS`, pinned `core.hooksPath`, cross-hook swap, shim with `$(…)` in `INSTALL_PYTHON`, rc 1/4/124/128.

---

### Task 1: `_git_hooks_identity`

```yaml-task
id: 1
description: Add _git_hooks_identity to lib/git_hooks.sh with name-matched candidates and pre-commit shim judging, plus its bats file
role: executor
model: sonnet
tdd: required
requirements: [R8, R9, R10, R11, R12, R23, R24, R25, R28]
acceptance:
  - cmd: bats tests/setup_env/git_hooks_identity.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*cross-hook swap'
  - cmd: 'bash -c "diff <(git show origin/master:lib/git_hooks.sh | sed -n \"/^_git_hooks_check_complete() {/,/^}/p\") <(sed -n \"/^_git_hooks_check_complete() {/,/^}/p\" lib/git_hooks.sh)"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/git_hooks.sh, tests/setup_env/git_hooks_identity.bats, tests/bats-files.txt]
depends_on: []
```

**Files:** `lib/git_hooks.sh` (new function after `_git_hooks_check_complete`), `tests/setup_env/git_hooks_identity.bats` (new; `load '../helpers/common.bash'`, `setup()` as in `tests/setup_env/git_hooks.bats`: `load_setup_env`, source `lib/git_hooks.sh`, bats git identity, `PERSONAL_GITREPOS` under `BATS_TEST_TMPDIR`), `tests/bats-files.txt`.

Signature `_git_hooks_identity <repo_dir> <hook_name> <hook_path>`; prints one word (plus a reason after a TAB for `generated-broken`, `generated-unverified`, rc 2) per spec Design §1 and R8-R12. Candidates: `git ls-files` paths whose basename is `<hook_name>` or `<hook_name>-hook.sh`. Shim parse: lines between `# start templated` and `# end templated`; last `INSTALL_PYTHON=`; strip one pair of wrapping `'` and turn `'"'"'` into `'`; hook type from `--hook-type=<x>` on the `ARGS=` line. Probe: `<timeout> "${_DOCTOR_PROBE_TIMEOUT:-10}" "${py}" -I -c 'import pre_commit' </dev/null >/dev/null 2>&1`, timeout via `_doctor_resolve_timeout` (`lib/helpers.sh`, already sourced by `load_setup_env`). Worktree paths from `git worktree list --porcelain`. Physical paths via `cd -P`/`pwd -P`.

Tests (fixture repo per test, tracking `scripts/pre-commit-hook.sh`, `scripts/pre-push`, `scripts/commit-msg`): every state in spec Testing "Hook fixtures" and "Generated-shim fixtures" at the identity level, with stub interpreters under `BATS_TEST_TMPDIR` whose exit for `-I -c 'import pre_commit'` is set per test. Name one test `cross-hook swap` (R23). R24 canary must stay absent; R28 uses a real `python3` lacking the module with `pre_commit.py` in cwd and on `PYTHONPATH`. Mutation control: temporarily drop `-I` and confirm R28's test fails, then restore.

**Interfaces:** Produces `_git_hooks_identity` (rc 0 `match`/`generated`, rc 1 `worktree`/`stale`/`foreign`/`generated-broken`/`generated-unverified`, rc 2 unreadable). Consumes `_doctor_resolve_timeout`.

### Task 2: `_doctor_check_git_hooks` and its wiring

```yaml-task
id: 2
description: Add the Git hooks doctor arm over HOOK_EXPECTED_REPOS, wire it after _doctor_check_hooks_path, and stub it in existing end-to-end run_doctor tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R13, R14, R15, R22, R26, R27]
acceptance:
  - cmd: bats tests/setup_env/doctor_git_hooks.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*one-byte edit'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_git_hooks.bats, tests/bats-files.txt, tests/setup_env/unit.bats, tests/setup_env/doctor_brew_links.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [1]
```

**Files:** `lib/helpers.sh` (`_doctor_check_git_hooks`; `run_doctor` gains the call on the line after `_doctor_check_hooks_path`), `tests/setup_env/doctor_git_hooks.bats` (new), `tests/bats-files.txt`, and the three files that call `run_doctor` end to end: `tests/setup_env/unit.bats`, `doctor_brew_links.bats`, `plugin_node_paths.bats`. In each, add `_doctor_check_git_hooks() { :; }` wherever `_doctor_check_login_shell() { :; }` is already stubbed for a `run_doctor` call, so no existing test reads the real `~/git-repos/personal`.

Behaviour: spec Design §1 table, preconditions and post-loop FAIL; R2-R7, R13, R14, R26, R27 strings verbatim. Remedy dir from `_git_hooks_target_dir` (fallback repo dir). Branch from `git symbolic-ref --short -q HEAD`.

Tests: fixture repos under `BATS_TEST_TMPDIR`, `PERSONAL_GITREPOS` and `HOOK_EXPECTED_REPOS` exported per test, `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` neutralised as in `git_hooks.bats` `setup()`. Call the arm without `run` and redirect to a file so `_DOCTOR_PASS`/`_DOCTOR_FAIL`/`_DOCTOR_WARN` can be asserted (pattern: `unit.bats` "Git hooksPath" test). Cover: absent (no counter moves), all absent (R3 FAIL), empty list (R26), pinned hooksPath via fixture `GIT_CONFIG_GLOBAL` (R27, no repo lines), no hooks dir, missing hook, stale on `master` vs branch vs detached, foreign, worktree, shim broken, unverified, PASS; R22 named `one-byte edit`; wiring test asserting `_doctor_check_git_hooks` is on the line after `_doctor_check_hooks_path` in `declare -f run_doctor`.

**Interfaces:** Consumes `_git_hooks_identity`, `_git_hooks_check_complete`, `_git_hooks_dir`, `_git_hooks_target_dir`, `_git_hooks_hookspath_offenders`. Produces `_doctor_check_git_hooks`.

### Task 3: `_doctor_check_ggshield` and its stub

```yaml-task
id: 3
description: Add the ggshield doctor arm with its own resolver and a quota probe, the ggshield stub, and wire it after _doctor_check_git_hooks
role: executor
model: sonnet
tdd: required
requirements: [R1, R15, R16, R17, R18, R19, R20, R21]
acceptance:
  - cmd: bats tests/setup_env/doctor_ggshield.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*fake key'
  - cmd: git diff --quiet origin/master -- scripts/pre-commit-hook.sh
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/stubs/ggshield-stub, tests/setup_env/doctor_ggshield.bats, tests/bats-files.txt, tests/setup_env/unit.bats, tests/setup_env/doctor_brew_links.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [2]
```

**Files:** `lib/helpers.sh` (`_doctor_check_ggshield`, called on the line after `_doctor_check_git_hooks`), `tests/stubs/ggshield-stub` (executable bash; on `quota` sleeps `STUB_GGSHIELD_SLEEP` (default 0), appends a line to `STUB_GGSHIELD_CALLS`, prints `fake-key-AbCdEf123` on stdout and stderr, exits `STUB_GGSHIELD_EXIT` (default 0)), `tests/setup_env/doctor_ggshield.bats` (new), `tests/bats-files.txt`, and `_doctor_check_ggshield() { :; }` beside the Task 2 stubs in the three end-to-end files.

Behaviour: spec Design §2 and R16-R18 verbatim, including `cd /` in a subshell, the `GITGUARDIAN_API_KEY` PASS variant, rc 1/4 WARN, 124 WARN, 3 FAIL, other FAIL. Timeout via `_doctor_resolve_timeout`; when it prints nothing, R17 WARN and no ggshield call.

Tests: every case under spec Testing "ggshield", each with `GGSHIELD_BIN` at the stub or a scoped `PATH="/usr/bin:/bin:<stubdir>"` (R20), one reaching the `command -v` branch; R21 test named `fake key` asserts `STUB_GGSHIELD_CALLS` has a line and the output lacks `fake-key-AbCdEf123`; R19 drift test extracts the `GGSHIELD_FALLBACK_PATHS:-…}` default from both files, asserts three absolute paths each, and equality; wiring test as in Task 2.

**Interfaces:** Consumes `_doctor_resolve_timeout`, `doctor_pass`/`doctor_warn`/`doctor_fail`. Produces `_doctor_check_ggshield`.

### Task 4: ADR and README

```yaml-task
id: 4
description: Record the hook identity rule and the doctor-only ggshield probe as ADR-0061 and update the ADR index and README doctor text (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md
    exit_code: 0
  - cmd: grep -q '0061-doctor-hook-identity-and-ggshield-probe' docs/adr/README.md
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md, docs/adr/README.md, README.md]
depends_on: [3]
```

ADR (Context, Decision, Consequences, Related; format of `docs/adr/0060-*.md`): name-matched candidates over any-tracked-file and over a per-repo map; generated shims judged by the absolute-interpreter `-I` import probe, missing interpreter is FAIL; `quota` over `api-status` (bad key rc 0); duplicated resolver plus drift test over a shared `lib/` file (fail-open); doctor only, no persistent signal. Related: spec, ai-config ADR-0055, ADR-0052. Index row in `docs/adr/README.md`. In `README.md`, extend the `-t doctor` description with the two checks if it lists doctor's checks; otherwise leave it and say so in the report.

The orchestrator runs `make test` after this task (README is outside the suite's inputs).

## Orchestrator steps (not dispatched)

- Before Phase 3: message the ai-config session, then add a `ggshield doctor stub` section to `ai-config/docs/knowledge/dotfiles-test-seams.md` describing `tests/stubs/ggshield-stub` and `STUB_GGSHIELD_EXIT`/`STUB_GGSHIELD_SLEEP`/`STUB_GGSHIELD_CALLS`, and the end-to-end `run_doctor` stubbing rule for the two new arms. No `CLAUDE.md` line is added: it is at 84997 of 85000 bytes.
- V1 (including the operator-approved `pre-commit install`), V2, V3, V5 before the PR leaves draft.

## Non-goal check

Reviewer: fresh reviewer-role subagent, 2026-11-22, inputs `plan.md` (this plan) and the effective N list.

- **N1 — UNCLEAR.** Quote: "session check V1 runs the operator-approved `cd ~/git-repos/personal/state-ledger && pre-commit install`, which replaces state-ledger's installed hook." Resolution: spec amendment N1 (this repository's code only; V1's operator-approved reinstall is verification, not design). Plan unchanged.
- **N2 — CLEAR.** "The doctor arms only probe … and write no files."
- **N3 — CLEAR.** "The arm runs `quota` only and never `secret scan`."
- **N4 — CLEAR.** "`HOOK_EXPECTED_REPOS` is a list of repos, not a map from repo to hook names."
