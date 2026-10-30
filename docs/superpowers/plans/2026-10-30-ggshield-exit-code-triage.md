# ggshield Exit-Code Triage Implementation Plan

spec: docs/superpowers/specs/2026-10-30-ggshield-exit-code-triage-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The pre-commit hook warns and continues on ggshield scan rc 3, and blocks on every other non-zero rc, with a cause-specific message.

**Architecture:** One `case` on the scan's exit code replaces `|| exit 1` in `scripts/pre-commit-hook.sh`; the scan pins `--fail-on-server-error`. Tests drive the scanner through the existing `GGSHIELD_BIN` seam and a mock that exits with a chosen code.

**Tech Stack:** bash, bats, ggshield 1.56.1.

## Global Constraints

- Worktree: `/home/bruce/git-repos/personal/dotfiles/.worktrees/ggshield-exit-code-triage`, branch `feat/ggshield-exit-code-triage`.
- No pre-flight `ggshield api-status` probe or any other extra network call (N1).
- No change to ggshield resolution (`GGSHIELD_BIN`, `PATH`, `GGSHIELD_FALLBACK_PATHS`) or to the unresolved-binary branch (N2).
- No edits to the ai-devops or ai-config hooks (N3). The hook does not set `GITGUARDIAN_API_TIMEOUT` (N4), count staged paths, or read ggshield server preferences (N5).
- Drive ggshield only via `GGSHIELD_BIN`, never by editing `PATH` (CLAUDE.md, Test Seams).
- Shell style: `[[ ]]`, `${VAR}`, `printf`, no `set -e`.

---

### Task 1: Triage the scan exit code in the pre-commit hook

```yaml-task
id: 1
description: Replace the hook's `|| exit 1` with a case on the ggshield scan rc, pin --fail-on-server-error, and test rc 0,1,2,3,4,5,128.
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6]
acceptance:
  - cmd: 'grep -q "secret scan pre-commit --fail-on-server-error" scripts/pre-commit-hook.sh'
    exit_code: 0
  - cmd: bats tests/scripts/pre_commit_hook.bats tests/scripts/unit.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-commit-hook.sh, tests/scripts/pre_commit_hook.bats]
depends_on: []
```

**IMPORTANT: All work must happen in `/home/bruce/git-repos/personal/dotfiles/.worktrees/ggshield-exit-code-triage/`. Do not cd anywhere else.**

`make test` takes about 5 min; run it with a 600000 ms Bash timeout, in the foreground.

**Files:** `scripts/pre-commit-hook.sh` (the `if [[ -n "${_ggshield}" ]]` block at the end), `tests/scripts/pre_commit_hook.bats`.

**Existing apparatus (verified):** `_write_makefile <rc>`, `_write_ggshield_mock <rc>` (writes `${BATS_TEST_TMPDIR}/ggshield`, appends `ggshield <args>` to `${MOCK_CALLS_FILE}`, exits `<rc>`), `_run_hook "<exports>;"`. `tests/scripts/unit.bats:593` ("exits 1 when ggshield fails", mock exits 1) and `:604` ("succeeds when ggshield is not installed") stay valid unchanged.

- [ ] Add a helper and one test per rc in `tests/scripts/pre_commit_hook.bats`:

```bash
_run_scan_rc() {
  _write_makefile 0
  _write_ggshield_mock "${1}"
  _run_hook "export GGSHIELD_BIN='${BATS_TEST_TMPDIR}/ggshield';"
}
```

Assertions per rc (each test's name states the rc and the expected exit):

| rc  | status | output must contain                                          | must NOT contain          | mock log                                                                          |
| --- | ------ | ------------------------------------------------------------ | ------------------------- | --------------------------------------------------------------------------------- |
| 0   | 0      | —                                                            | `SECRET SCAN DID NOT RUN` | `grep -q -- 'secret scan pre-commit --fail-on-server-error' "${MOCK_CALLS_FILE}"` |
| 1   | 1      | —                                                            | `SECRET SCAN DID NOT RUN` | —                                                                                 |
| 2   | 1      | `exit 2`, `1.50.0`                                           | `SECRET SCAN DID NOT RUN` | —                                                                                 |
| 3   | 0      | `SECRET SCAN DID NOT RUN`, `(exit 3)`, `ggshield auth login` | —                         | same grep as rc 0                                                                 |
| 4   | 1      | `exit 4`                                                     | `SECRET SCAN DID NOT RUN` | —                                                                                 |
| 5   | 1      | `exit 5`                                                     | `SECRET SCAN DID NOT RUN` | —                                                                                 |
| 128 | 1      | `exit 128`                                                   | `SECRET SCAN DID NOT RUN` | —                                                                                 |

- [ ] Run `bats tests/scripts/pre_commit_hook.bats`; confirm the rc 0 (flag missing), rc 2, 3, 4, 5 and 128 tests fail on the unchanged hook. Record which failed.
- [ ] Replace `"${_ggshield}" secret scan pre-commit "$@" || exit 1` with:

```bash
  # ggshield 1.56.1 ExitCode (ggshield/core/errors.py): 0 clean, 1 found,
  # 2 usage, 3 auth, 4 server unavailable, 128 unexpected. Measured
  # 2026-10-30 on `secret scan pre-commit`: bad or missing key 3, dead
  # proxy 4 (28 s when blackholed).
  #
  # Only 3 continues: a bad, expired or missing credential persists until
  # someone re-authenticates, so blocking on it blocks every commit and
  # invites a bypass that drops `make lint` too. 4 blocks: it is transient,
  # and when one chunk of a multi-chunk scan times out ggshield discards
  # findings from the chunks that finished (verticals/secret/
  # secret_scanner.py, _collect_results). --fail-on-server-error is pinned
  # so a machine-level `fail_on_server_error: false` cannot turn that into
  # a silent 0. 2 is a usage error, and also a 401 during the scan: a key
  # revoked inside the 300 s auth cache gets 2 once, then 3. 128 includes
  # quota exhaustion. Unknown codes fail closed.
  "${_ggshield}" secret scan pre-commit --fail-on-server-error "$@"
  _scan_rc=$?
  case "${_scan_rc}" in
    0) ;;
    1) exit 1 ;;
    3)
      printf 'pre-commit: ggshield could not authenticate (exit 3) — SECRET SCAN DID NOT RUN\n' >&2
      printf 'pre-commit: fix with: ggshield auth login (or check GITGUARDIAN_API_KEY)\n' >&2
      ;;
    4)
      printf 'pre-commit: GitGuardian unreachable (exit 4) — blocking: a partial scan can discard findings\n' >&2
      printf 'pre-commit: retry the commit when the network is back\n' >&2
      exit 1
      ;;
    *)
      printf 'pre-commit: ggshield failed (exit %s) — unknown failure, blocking\n' "${_scan_rc}" >&2
      if [[ "${_scan_rc}" -eq 2 ]]; then
        printf 'pre-commit: --fail-on-server-error needs ggshield 1.50.0 or later\n' >&2
      fi
      exit 1
      ;;
  esac
```

- [ ] Run the bats file; all pass.
- [ ] Mutation controls (V1). Apply each in turn, run `bats tests/scripts/pre_commit_hook.bats`, confirm at least one test fails, revert. Report the failing test name per mutant:
  1. `3)` arm ends with `exit 1`.
  2. `*)` arm's `exit 1` removed.
  3. `4)` arm's `exit 1` removed.
  4. `--fail-on-server-error` removed from the scan line.
  5. `3)` arm's first printf replaced by `printf 'pre-commit: ggshield could not be resolved — SECRET SCAN DID NOT RUN\n' >&2`.
- [ ] Run the acceptance gates. Commit via `caveman:caveman-commit` (type `fix(pre-commit)`).

**Interfaces:** Produces: the hook's stderr strings above, which Task 2 quotes in `CLAUDE.md`.

### Task 2: Document the triage rule and close the backlog row

```yaml-task
id: 2
description: Docs-only (no behaviour change, so no TDD) — state the rc triage rule in CLAUDE.md, delete the closed backlog row, add the ggshield 429 backlog row.
role: executor
model: sonnet
tdd: not-applicable
requirements: [R7]
acceptance:
  - cmd: 'grep -qE "rc 3.*warn.*continue" CLAUDE.md'
    exit_code: 0
  - cmd: '! grep -q "resolves ggshield but never checks it is _usable_" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "handle_scan_chunk_error" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make check-claude-md-budget
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [1]
```

**IMPORTANT: All work must happen in `/home/bruce/git-repos/personal/dotfiles/.worktrees/ggshield-exit-code-triage/`. Do not cd anywhere else.**

No test reads `CLAUDE.md` or `docs/superpowers/README.md` (`tests/scripts/docs_inert_premise.bats`), so this task does not run `make test`.

- [ ] `CLAUDE.md`, the bullet starting "Resolve `ggshield` by explicit override": after "never silently." insert one sentence: "Once resolved, scan rc 3 (credential) warns and continues with `SECRET SCAN DID NOT RUN`; rc 4 (unreachable) and every other non-zero rc block, and the scan pins `--fail-on-server-error`." Keep the trailing `→` pointer unchanged.
- [ ] `docs/superpowers/README.md`: delete the P2 — CI row "The pre-commit hook resolves ggshield but never checks it is _usable_, ...".
- [ ] Same file, P3 — CI and test gaps table (not the "Closed without shipping" table at the end): add `| ggshield drops a scan chunk on a 429 or other unhandled 4xx and still exits 0 | \`handle_scan_chunk_error\` (ggshield 1.56.1 \`verticals/secret/secret_scanner.py\`) logs "Results may be incomplete" and continues, so the pre-commit hook sees rc 0 for a partial scan. Not reachable from the hook. See [spec](specs/2026-10-30-ggshield-exit-code-triage-design.md). |`
- [ ] Run the gates. Commit via `caveman:caveman-commit` (type `docs`).

## Orchestrator steps (after Task 2)

1. `make test` once in the worktree (600000 ms timeout); paste the summary line.
2. V2: in the worktree, stage the branch's own files only if uncommitted work exists; otherwise rely on the Task 1 and Task 2 commits, whose pre-commit output must show ggshield's `No secrets have been found`. Quote that line from the commit output.
3. Phase 3: `finishing-a-development-branch`.
4. Post-merge, cross-repo backlog rows (spec Docs): ai-devops (`scripts/pre-commit` fails open on rc 2, 4 and 128; comment cites unreachable as 3) and ai-config (`scripts/pre-commit-hook.sh` bare `command -v`, silent when absent, no triage). Message the owning sessions before touching either repo (core.md git-workflow-020).

## Non-goal check

Fresh reviewer, 2026-10-30, against N1-N5 from `spec_contract.py`: CLEAR 5, CONFLICT 0, UNCLEAR 0.

- N1 CLEAR: `--fail-on-server-error` is a flag on the existing scan, not a new network call.
- N2 CLEAR: mutant 5 rewords the rc 3 message and is reverted; resolution logic is untouched.
- N3 CLEAR: orchestrator step 4 adds backlog rows in ai-devops and ai-config after merge, not hook edits.
- N4 CLEAR, N5 CLEAR: no timeout export, no path count, no preference read.
