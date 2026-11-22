# Bats Suite Under a Sentinel HOME Implementation Plan

spec: docs/superpowers/specs/2026-11-21-bats-sentinel-home-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every bats invocation in dotfiles (make, coverage, pre-push, CI, direct `bats tests/x.bats`) runs under a throwaway `HOME`, so no test can write the operator's real home (audit F16-F19).

**Architecture:** One helper, `tests/helpers/suite_isolation.bash`, defines bats' `setup_suite`/`teardown_suite`; each of the four test directories holds a `setup_suite.bash` that sources it, so bats' own hook lookup applies it to every invocation with no Makefile, coverage-script or CI change. `teardown_suite` only guards and removes the sentinel; there is no residue check.

**Tech Stack:** bash, bats-core 1.13.0 (Linux) / 1.14.0 (`macos-latest`), GNU make.

## Global Constraints

- Hook files are regular files, never symlinks (a symlinked hook resolves `lib/constants.sh` from the wrong directory).
- `setup_suite` runs under `set -eET`: every command that may fail on purpose is guarded. `teardown_suite` runs with errexit off: every step checks its own status.
- `_BATS_SENTINEL` is unset as `setup_suite`'s first command and is never exported.
- `teardown_suite` judges removal by `[[ -e <s> ]]`, never by `rm`'s status (`tests/mocks/rm` exits 0 on failure).
- Every hand-made sentinel, canary or fixture tree in tests lives under `BATS_TEST_TMPDIR`.
- `Makefile`, `scripts/run-bash-coverage.sh`, `scripts/ci-suite-report.sh` and `.github/workflows/ci.yml` are not edited (N3). No mock's `MOCK_CALLS_FILE` default changes (N1). No `.bats` file is edited other than `tests/zshrc.d/unit.bats` and the new `tests/suite_isolation.bats` (N2).
- `CLAUDE.md` stays at or under 85000 bytes (`scripts/claude_md_budget.py`, run by `make test` and the pre-push hook); it is 84944 at `4124de9f`.
- `make test` takes about 4 minutes on `claude` (bats phase 2:17 at `--jobs 24`), under the 600 s Bash cap: run it in the foreground with `timeout: 600000` and `< /dev/null`.

## Verification (session level)

After Task 4, the orchestrator runs the spec's V items and records raw output in the PR body:

- V1: `make test < /dev/null` and `make bash-coverage < /dev/null` exit 0 on `claude`; then `R=$(mktemp -d); _BATS_SENTINEL_TMP_ROOT="$R" make test-bats < /dev/null; sleep 60; find "$R" -name 'bats-sentinel.*'; pgrep -f -- "[${R:0:1}]${R:1}"; grep -l "$R" /proc/[0-9]*/environ 2>/dev/null` prints nothing.
- V2: in a throwaway clone of the branch, add `tests/zz_probe.bats` (`@test probe { touch "${HOME}/sentinel-probe-${PROBE_ID}"; }`), run it with `bats` directly and via `BATS_FILES_FROM=<list> make test-bats`; the real `~/sentinel-probe-<id>` is absent after each. The same probe in a clone of `origin/master` creates it (then delete it).
- V3: CI green on all six shard legs; one `test-shard` leg shows `ok` for the top-level `HOME`-under-sentinel test.
- V4: Studio `make test-bats` exits 0 and V2's direct probe leaves the real home untouched.
- V5: decoy run on `claude`, the Studio and `workstation` per the spec's V5 (baseline run first).
- V6: `setsid` + process-group `TERM` run with a private root leaves no sentinel.
- V7: `strace -f -qq -e trace=%file -e status=successful -o <log> make test-bats < /dev/null` from a clone outside `$HOME` on `claude` and `workstation` lists no write-flagged call under the real `$HOME`; the Studio diffs `find -newer` against a no-suite window.

Edge cases the tests must cover: nested bats inheriting an outer sentinel; `setup_suite` failing before the sentinel exists; a removal that fails while `rm` exits 0; an unreadable `lib/constants.sh`; a guard given a non-sentinel directory.

---

### Task 1: Suite isolation helper, hooks and tests

```yaml-task
id: 1
description: Add tests/helpers/suite_isolation.bash, the four setup_suite.bash hooks, tests/suite_isolation.bats and its manifest line
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R9, R11]
acceptance:
  - cmd: bats tests/suite_isolation.bats < /dev/null
    exit_code: 0
    stdout_match: 'ok [0-9]+ HOME of this test lies under a bats-sentinel directory'
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched:
  - tests/helpers/suite_isolation.bash
  - tests/setup_suite.bash
  - tests/scripts/setup_suite.bash
  - tests/setup_env/setup_suite.bash
  - tests/zshrc.d/setup_suite.bash
  - tests/suite_isolation.bats
  - tests/bats-files.txt
depends_on: []
```

**Files:** create the first six; add `tests/suite_isolation.bats` to `tests/bats-files.txt` in `LC_ALL=C` order (`git ls-files '*.bats' | LC_ALL=C sort` after `git add`).

**Interfaces:**

- Produces: `setup_suite` (exports `HOME`, `XDG_{CONFIG,CACHE,DATA,STATE}_HOME`, `PARALLEL_HOME`, `ZDOTDIR`, `TMPPREFIX`, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`, `MOCK_CALLS_FILE`, maybe `PINNED_UV_BIN`; sets non-exported `_BATS_SENTINEL`); `teardown_suite` (returns 0 or 1); seam `_BATS_SENTINEL_TMP_ROOT`.

Helper (write exactly this behaviour; the comments may be reworded):

```bash
#!/usr/bin/env bash
# Suite-level HOME isolation (docs/superpowers/specs/2026-11-21-bats-sentinel-home-design.md).
# Sourced by setup_suite.bash in each test directory. bats calls setup_suite under
# set -eET and teardown_suite with errexit off, both in one shell, so
# _BATS_SENTINEL is a plain, never-exported variable shared between them.

setup_suite() {
    # A nested bats inherits the outer run's environment; never trust its value.
    unset _BATS_SENTINEL
    local _const="${BASH_SOURCE[0]%/*}/../../lib/constants.sh" _uv_ver="" _uv _root
    if [[ -r "${_const}" ]]; then
        _uv_ver="$(sed -n 's/^UV_VER="\(.*\)"$/\1/p' "${_const}")" || _uv_ver=""
    fi
    if [[ -z "${_uv_ver}" ]]; then
        printf '# bats isolation: cannot read UV_VER from %s\n' "${_const}" >&3
    elif [[ -z "${PINNED_UV_BIN:-}" ]]; then
        _uv="${HOME}/.local/share/dotfiles/pinned/uv-${_uv_ver}/uv"
        if [[ -x "${_uv}" ]]; then
            export PINNED_UV_BIN="${_uv}"
        fi
    fi
    # BSD mktemp -d with a template ignores TMPDIR; the seam reaches the failure branch.
    _root="${_BATS_SENTINEL_TMP_ROOT:-${TMPDIR:-/tmp}}"
    if ! _BATS_SENTINEL="$(mktemp -d "${_root}/bats-sentinel.XXXXXX")"; then
        unset _BATS_SENTINEL
        printf 'bats isolation: cannot create sentinel under %s\n' "${_root}"
        return 1
    fi
    export HOME="${_BATS_SENTINEL}/home" ZDOTDIR="${_BATS_SENTINEL}/home"
    export TMPPREFIX="${_BATS_SENTINEL}/zsh" PARALLEL_HOME="${_BATS_SENTINEL}/parallel"
    export XDG_CONFIG_HOME="${_BATS_SENTINEL}/xdg/config" XDG_CACHE_HOME="${_BATS_SENTINEL}/xdg/cache"
    export XDG_DATA_HOME="${_BATS_SENTINEL}/xdg/data" XDG_STATE_HOME="${_BATS_SENTINEL}/xdg/state"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    if [[ -z "${MOCK_CALLS_FILE:-}" ]]; then
        export MOCK_CALLS_FILE="${_BATS_SENTINEL}/mock_calls"
    fi
    mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" \
        "${XDG_STATE_HOME}" "${PARALLEL_HOME}"
}

teardown_suite() {
    local _s="${_BATS_SENTINEL:-}"
    # bats runs teardown_suite even when setup_suite failed.
    if [[ -z "${_s}" || ! -d "${_s}" || "${_s##*/}" != bats-sentinel.* ]]; then
        printf 'bats isolation: no sentinel to check\n'
        return 1
    fi
    rm -rf "${_s}"
    # Judge by existence: tests/mocks/rm exits 0 even when the removal failed.
    if [[ -e "${_s}" ]]; then
        printf 'bats isolation: cannot remove %s; run: chmod -R u+w %s && rm -rf %s\n' "${_s}" "${_s}" "${_s}"
        return 1
    fi
}
```

Hooks: `tests/setup_suite.bash` is the three lines below; in the three subdirectories the path is `../helpers/suite_isolation.bash`.

```bash
#!/usr/bin/env bash
# shellcheck source=tests/helpers/suite_isolation.bash
source "${BASH_SOURCE[0]%/*}/helpers/suite_isolation.bash"
```

`tests/suite_isolation.bats` — write these tests, red first against a helper stub that defines empty functions, then green. `FX` is `${BATS_TEST_TMPDIR}/fx`; `mkfx` writes `${FX}/setup_suite.bash` as `source "${REPO_ROOT}/tests/helpers/suite_isolation.bash"` (or a given helper path) plus the fixture `.bats` named.

1. `every test directory has a setup_suite.bash that sources the helper`: for each `dirname` of `tests/bats-files.txt` (sorted unique), fail with `missing hook: <dir>` unless `<dir>/setup_suite.bash` exists, is not a symlink (`[[ ! -L ]]`) and greps `suite_isolation.bash`.
2. `HOME of this test lies under a bats-sentinel directory`: `[[ "${HOME}" == */bats-sentinel.*/home ]]`.
3. `setup_suite exports the R2 values` — fixture test writes `env` to `${OUT}`; run with `env -u MOCK_CALLS_FILE OUT=... bats "${FX}/a.bats"`; assert `HOME=<s>/home`, `ZDOTDIR=<s>/home`, `TMPPREFIX=<s>/zsh`, `PARALLEL_HOME=<s>/parallel`, the four XDG values, both `GIT_CONFIG_*=/dev/null`, `MOCK_CALLS_FILE=<s>/mock_calls`, and that `_BATS_SENTINEL` is absent from the env dump.
4. `a caller's MOCK_CALLS_FILE survives` (R3).
5. `PINNED_UV_BIN comes from the pre-swap HOME`: fake home with an executable `uv` at `.local/share/dotfiles/pinned/uv-<UV_VER>/uv` (`UV_VER` read with the same `sed` from `lib/constants.sh`); `env -u PINNED_UV_BIN HOME=<fake>`; fixture records `PINNED_UV_BIN`; assert it equals that path. Second case: a caller value is kept.
6. `an unreadable constants file prints the message and still isolates` (R4): copy the helper to `${BATS_TEST_TMPDIR}/t/tests/helpers/`, hook sources the copy, fixture test asserts `HOME` matches `*/bats-sentinel.*/home`; assert status 0 and output contains `cannot read UV_VER from`.
7. `the sentinel exists during the run and is gone after` (R6): fixture writes `${HOME%/home}` to `${REC}` after `[ -d "${HOME%/home}" ]`; assert status 0 and `[ ! -e "$(cat "${REC}")" ]`.
8. `mktemp failure stops the suite` (R7): `_BATS_SENTINEL_TMP_ROOT=${BATS_TEST_TMPDIR}/missing`; status 1; output has `not ok 1 setup_suite` and `bats isolation: cannot create sentinel under`.
9. `guard refuses an empty sentinel` and 10. `guard refuses a non-sentinel directory`: `source` the helper, set `_BATS_SENTINEL` (`""`, or `${BATS_TEST_TMPDIR}/canary` holding a file), `run teardown_suite`; status 1, output `bats isolation: no sentinel to check`, canary file still present.
10. `a nested failing setup never deletes an inherited sentinel`: plant `${BATS_TEST_TMPDIR}/bats-sentinel.keep/home`, `run env _BATS_SENTINEL=<plant> _BATS_SENTINEL_TMP_ROOT=${BATS_TEST_TMPDIR}/missing bats "${FX}/a.bats"`; plant still a directory; output has both `cannot create sentinel under` and `no sentinel to check`.
11. `a failed removal is reported even when rm exits 0`: sentinel `${BATS_TEST_TMPDIR}/bats-sentinel.rmfail/home/x`, shim dir with an `rm` that is `#!/usr/bin/env bash` + `exit 0`, `source` helper, `_BATS_SENTINEL=<it>`, `PATH="<shim>:${PATH}" run teardown_suite`; status 1, output contains `bats isolation: cannot remove` and `chmod -R u+w`; then `/bin/rm -rf` the sentinel.

Steps:

- [ ] Write the tests and a stub helper (empty functions) plus the four hooks; run `bats tests/suite_isolation.bats < /dev/null`, see tests 2-12 fail.
- [ ] Write the helper above; run the file, all green.
- [ ] Add the manifest line; run `make check-bats-manifest`.
- [ ] Run `make test < /dev/null` (timeout 600000).
- [ ] Commit (subject from `caveman:caveman-commit`, e.g. `test: run every bats suite under a sentinel HOME`).

### Task 2: F16 fixture hygiene in tests/zshrc.d/unit.bats

```yaml-task
id: 2
description: tests/zshrc.d/unit.bats setup() redirects HOME, pre-creates the plugin dir, sets ZDOTDIR and stubs rbenv (test-fixture hygiene in a test file; its own 65 tests are the check, so tdd not-applicable)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R10]
acceptance:
  - cmd: 'grep -qF -- "_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv" tests/zshrc.d/unit.bats'
    exit_code: 0
  - cmd: 'grep -qF -- "export ZDOTDIR=\"\${HOME}\"" tests/zshrc.d/unit.bats'
    exit_code: 0
  - cmd: bats tests/zshrc.d/unit.bats < /dev/null
    exit_code: 0
max_retries: 3
files_touched:
  - tests/zshrc.d/unit.bats
depends_on: [1]
```

**Files:** `tests/zshrc.d/unit.bats` `setup()` only. After the `source .../common.bash` line add:

```bash
  # F16: the sourced zsh config self-heals ~/.oh-my-zsh and runs rbenv init;
  # keep both inside this test's own HOME, never the suite's shared one.
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  export ZDOTDIR="${HOME}"
  export _OVERRIDE_RBENV_BINARY=/nonexistent/rbenv
```

Tests that assign their own `_fake_home` keep doing so after `setup()`, unchanged. If any of the 65 tests fails because it read the old `HOME`, stop and report it as a blocker with the test name; do not edit that test (N2 allows this file, but the spec's change is `setup()` only).

- [ ] Edit `setup()`; run the three gates; commit (`test: keep zshrc.d unit tests in their own HOME`).

### Task 3: ADR, CLAUDE.md rule and index rows

```yaml-task
id: 3
description: Write ADR-0060 for suite-level HOME isolation, add one CLAUDE.md Testing line with a pointer, keep CLAUDE.md within budget, update the superpowers index
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0060-bats-suite-hooks-sentinel-home.md
    exit_code: 0
  - cmd: 'grep -qF "0060-bats-suite-hooks-sentinel-home.md" docs/adr/README.md'
    exit_code: 0
  - cmd: 'grep -qF "suite_isolation.bash" CLAUDE.md'
    exit_code: 0
  - cmd: python3 scripts/claude_md_budget.py HEAD
    exit_code: 0
  - cmd: 'grep -qF "plans/2026-11-21-bats-sentinel-home.md" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint < /dev/null
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0060-bats-suite-hooks-sentinel-home.md
  - docs/adr/README.md
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [1, 2]
```

Docs-only (tdd not-applicable): no file the suite reads changes except `CLAUDE.md`, whose only test is the budget check, run above. The orchestrator runs `make test` after this task.

**ADR-0060** (Context, Decision, Consequences, Related; copy the heading shape of `docs/adr/0059-*.md`): F15 leaked through a per-file convention; a wrapper around the Makefile's bats lines was designed and replaced because direct runs escaped it and the recipe-text tests kept breaking; bats' own `setup_suite`/`teardown_suite` hooks cover every invocation; no residue gate (the swap is the protection; spec external review F1.1). Related: the spec, this plan, dotfiles#475. Add its row to `docs/adr/README.md`.

**CLAUDE.md:** under `### Testing Rules`, add one bullet, then commit and run the budget check:

```
- Every bats invocation runs under a throwaway `HOME`, XDG dirs and `/dev/null` git config from `tests/helpers/suite_isolation.bash`, sourced by each test directory's `setup_suite.bash`; a new test directory needs one (`tests/suite_isolation.bats` fails otherwise). → `dotfiles-test-seams.md` § `bats suite sentinel HOME`
```

The file must stay at or under 85000 bytes. Offset by moving reference-only detail (never a gate or safety rule, ADR-0077 rule 5) into the ai-config knowledge section Task 4 writes, or by tightening wording without dropping a fact; list each cut in the commit body. In the Studio repro block, `HOME="$(mktemp -d)"` inside `env -i` is now redundant and may go.

**Index:** in `docs/superpowers/README.md` set the spec row's status to `Approved` and add a plan row (`plans/2026-11-21-bats-sentinel-home.md`, `In progress`).

- [ ] Write ADR and index row; edit CLAUDE.md; commit; run the gates.

### Task 4: ai-config knowledge section for the seam (cross-repo)

```yaml-task
id: 4
description: Add the bats suite sentinel HOME section to ai-config docs/knowledge/dotfiles-test-seams.md so the CLAUDE.md pointer resolves before Phase 3 (docs-only, tdd not-applicable)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qF "## bats suite sentinel HOME" /home/bruce/git-repos/personal/ai-config-wt-seam/docs/knowledge/dotfiles-test-seams.md'
    exit_code: 0
  - cmd: make -C /home/bruce/git-repos/personal/ai-config-wt-seam validate-knowledge
    exit_code: 0
max_retries: 2
files_touched:
  - /home/bruce/git-repos/personal/ai-config-wt-seam/docs/knowledge/dotfiles-test-seams.md
depends_on: [3]
```

Orchestrator, before dispatch: message the ai-config owning session (`ListAgents`, `SendMessage`) naming the file and asking which worktree to use; create `ai-config-wt-seam` only with its agreement. The heading text must equal the pointer in Task 3's `CLAUDE.md` line. Content: what the hooks export, the `_BATS_SENTINEL_TMP_ROOT` seam (why: BSD `mktemp -d` ignores `TMPDIR`), the four hook directories and the R9 guard, the unset-first and `[[ -e ]]` rules with their reasons, and any reference detail Task 3 moved out of `CLAUDE.md`. Push per ai-config's direct-to-master docs rule (`core.md` git-workflow-003), from the worktree, after the owning session agrees.

- [ ] Message the session; write the section; run the gates; commit; push.

## Orchestrator steps after Task 4

- [ ] `make test < /dev/null` on the branch (timeout 600000).
- [ ] Phase 3 (`finishing-a-development-branch`); open the PR as a draft with `gh pr create --draft`; record V1-V7 evidence in the PR body; `gh pr ready` once V3 is green and Phase 3 is done.

## Non-goal check

Fresh reviewer, 2026-11-21: CLEAR 4, CONFLICT 0, UNCLEAR 0.

- N1 CLEAR: the helper sets `MOCK_CALLS_FILE` only in the environment, only when unset; no file under `tests/mocks/` is touched.
- N2 CLEAR: the branch touches only `tests/suite_isolation.bats` and `tests/zshrc.d/unit.bats` among `.bats` files; fixtures live under `BATS_TEST_TMPDIR` and V2's probe in a throwaway clone.
- N3 CLEAR: no task's `files_touched` names `Makefile`, `scripts/run-bash-coverage.sh`, `scripts/ci-suite-report.sh` or `.github/workflows/ci.yml`.
- N4 CLEAR: under the pre-swap `HOME` `setup_suite` only tests the uv binary with `-x`; it reads `lib/constants.sh` (in the repo) and writes only inside the sentinel; `teardown_suite` removes only a guarded sentinel.

No resolution needed.
