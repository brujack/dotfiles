# cheat.sh Bounded Atomic Fetch Implementation Plan

> **Status: DONE** — merged in #326 (25ac1308), 2026-10-10.

spec: docs/superpowers/specs/2026-10-09-cheat-sh-bounded-atomic-fetch-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the four cheat.sh fetches through one helper that bounds the transfer at 10 s, checks the first line, and replaces the destination only through a same-directory temp file.

**Architecture:** One new function `_cheat_fetch <url> <dest> <mode> <head>` in `lib/workflows.sh`, called from `run_setup_user` (two sites) and `run_update` (two sites). Tests live in `tests/setup_env/workflows.bats` and use the existing curl/mv mocks.

**Tech Stack:** bash, bats, `tests/mocks/{curl,mv,chmod,rm}`.

## Global Constraints

- curl argument order is fixed: `curl -fsS -o "${tmp}" --max-time 10 "${url}"` — `-o` stays `$3` (function-override stubs write `"$3"`), the URL stays last (stubs match `"${*: -1}"`).
- Temp name: `mktemp "${dest%/*}/.${dest##*/}.XXXXXX"` (dot-prefixed, same directory).
- Return codes: 0 replaced; 1 curl non-zero, empty, or first line not beginning `<head>`; 2 empty `<head>`, `mktemp`, `chmod` or `mv` failure. On 1 and 2 the temp file is removed and `dest` is untouched.
- Read the first line with `IFS= read -r line < "${tmp}" || true` — `read` returns 1 on a file with no trailing newline while still setting `line`, and every fixture is written with `printf "%s"`.
- Modes: binary 750 (`run_setup_user`), 754 (`run_update`); completion 644 at both.
- Heads: `'#!'` for the binary, `'#compdef'` for the completion, at all four sites.
- Messages (stderr, both functions): `cheat.sh <binary|completion> fetch failed` on rc 1, `cheat.sh <binary|completion> install failed` on rc 2.
- Every no-temp-file-left assertion reads the temp path from the recorded `curl ... -o <tmp>` line in `MOCK_CALLS_FILE`, asserts that line exists, then asserts the path does not exist. Never a quoted glob, `*` or `ls`.
- Mode assertions: `stat -c '%a' f 2>/dev/null || stat -f '%OLp' f`.
- Non-goals: no URL/timeout seam, no retry, 750/754 unchanged, `run_setup_user` gains no new non-zero return, no new `tests/mocks/curl` knob, no signal trap.
- `make test` runs ~143 s on `claude` (measured 2026-10-09, 2737 ok). Run it with a 600000 ms timeout and poll in-turn; never end the turn awaiting a background notification.
- Commits: invoke `caveman:caveman-commit` before every `git commit`; stage exact paths.

## Verification (session level)

- `make test` exits 0; every CI job on the PR passes, including `test-macos` (BSD `mktemp`/`stat`).
- Orchestrator mutations after Task 3, each must turn the named tests red and be reverted: V1 curl straight to `dest`; V2 `--max-time 100` in the helper and in `_fetch_github_latest`; V5 delete the helper's `rm -f`; V6 delete the head check; V7 delete the `run_setup_user` binary warning; V8 pass `""` as head at the `run_update` completion site; V9 delete the helper's `chmod`.
- V3: source `lib/workflows.sh`, start a local listener (`tests/helpers/http_listener.bash` or a python socket) that sends 5 of 100 body bytes then stalls, call `_cheat_fetch http://127.0.0.1:<port>/ <scratch>/cht.sh 750 '#!'` over a pre-seeded `PRE-EXISTING`: rc 1 within ~10 s, file unchanged, no `.cht.sh.*` left.

---

### Task 1: `_cheat_fetch` helper

```yaml-task
id: 1
description: Add _cheat_fetch to lib/workflows.sh with direct unit tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R19]
acceptance:
  - cmd: "grep -q '^_cheat_fetch()' lib/workflows.sh"
    exit_code: 0
  - cmd: "bats -f '_cheat_fetch' tests/setup_env/workflows.bats"
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: []
```

**Files:** `lib/workflows.sh` (new function, place it just above `run_setup_user`), `tests/setup_env/workflows.bats` (new `# ── _cheat_fetch` section).

Implementation shape (the code comment states why; keep it):

```bash
# Fetch <url> into <dest> through a dot-prefixed temp file in the same
# directory, so a failed, timed-out or wrong-content transfer never replaces a
# working copy: curl -o truncates its target as soon as the body starts, and
# cheat.sh answers HTTP 200 with an error page, which -f cannot refuse.
# Returns 0 replaced, 1 fetch failed, 2 local failure (or empty <head>).
_cheat_fetch() {
  local _url="$1" _dest="$2" _mode="$3" _head="$4" _tmp _line=""
  [[ -n "${_head}" ]] || return 2
  _tmp="$(mktemp "${_dest%/*}/.${_dest##*/}.XXXXXX")" || return 2
  if ! curl -fsS -o "${_tmp}" --max-time 10 "${_url}" || [[ ! -s "${_tmp}" ]]; then
    rm -f "${_tmp}"
    return 1
  fi
  IFS= read -r _line < "${_tmp}" || true
  if [[ "${_line}" != "${_head}"* ]]; then
    rm -f "${_tmp}"
    return 1
  fi
  if ! chmod "${_mode}" "${_tmp}" || ! mv -f "${_tmp}" "${_dest}"; then
    rm -f "${_tmp}"
    return 2
  fi
}
```

Tests, one RED→GREEN at a time, all named `_cheat_fetch ...`, each pre-seeding `"${HOME}/bin/cht.sh"` with `PRE-EXISTING` and using URL `https://example.test/x`. Add a file-local helper:

```bash
_cheat_tmp_from_calls() {  # $1 = URL; prints the -o path curl was given
  sed -n "s|^curl .* -o \([^ ]*\) --max-time .*${1}\$|\1|p" "${MOCK_CALLS_FILE}" | tail -1
}
```

1. success: `MOCK_CURL_STDOUT=$'#!/bin/bash\necho hi'` → rc 0, dest content equals the body, mode 750, temp path (from calls) non-empty and absent.
2. curl fails: `MOCK_CURL_FAIL_URL=example.test` → rc 1, dest `PRE-EXISTING`, temp absent.
3. empty body (no `MOCK_CURL_STDOUT`) → rc 1, dest unchanged.
4. wrong head: `MOCK_CURL_STDOUT='Unknown topic.'` → rc 1, dest unchanged, temp absent.
5. empty head (R19): `run _cheat_fetch https://example.test/x "${HOME}/bin/cht.sh" 750 ""` → status 2, `refute_grep 'example.test' "${MOCK_CALLS_FILE}"`, dest unchanged.
6. mv fails: good body, `MOCK_MV_FAIL_ARGS=".cht.sh."` → rc 2, dest unchanged, temp absent.
7. bound: `grep -E -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}" | grep -qF 'https://example.test/x'`.

Use `run _cheat_fetch ...` and assert `$status`. Run `make test` before committing.

**Interfaces:** Produces `_cheat_fetch <url> <dest> <mode> <head>` with the rc contract above, and the test helper `_cheat_tmp_from_calls <url>` reused by Tasks 2–3.

### Task 2: `run_update` through the helper

```yaml-task
id: 2
description: Route run_update's two cheat.sh fetches through _cheat_fetch with rc-specific messages
role: executor
model: sonnet
tdd: required
requirements: [R5, R6, R7, R8, R11, R14, R15, R16, R17, R18, R20]
acceptance:
  - cmd: "grep -qF '_cheat_fetch https://cheat.sh/:zsh \"${HOME}/.zsh.d/_cht\" 644' lib/workflows.sh"
    exit_code: 0
  - cmd: "bats -f 'run_update' tests/setup_env/workflows.bats"
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: [1]
```

**Files:** `lib/workflows.sh` — the cheat.sh subshell in `run_update` (search `Updating cheat.sh tab completion`). Keep the subshell, `_rc`, `tee` and `PIPESTATUS[0]` exactly. Replace each `curl … && [[ -s ]]` block with:

```bash
        if [[ -f ${HOME}/bin/cht.sh ]]; then
          _cheat_fetch https://cht.sh/:cht.sh "${HOME}/bin/cht.sh" 754 '#!' || case $? in
            1) printf "cheat.sh binary fetch failed\\n" >&2; _rc=1 ;;
            *) printf "cheat.sh binary install failed\\n" >&2; _rc=1 ;;
          esac
        fi
```

and the same for `_cht` (`https://cheat.sh/:zsh`, mode 644, head `'#compdef'`, word `completion`). The old `cheat.sh chmod failed` message goes away.

Tests in `tests/setup_env/workflows.bats` (run_update cheat.sh block, ~:2252–:2430):

- R17: prefix the four existing success bodies — `"cheat.sh binary body"` → `$'#!/bin/bash\ncheat.sh binary body'`, `"cheat.sh completion body"` → `$'#compdef cht.sh\ncheat.sh completion body'`, `printf "binary-body"` → `printf '#!binary-body'`, `printf "completion-body"` → `printf '#compdef completion-body'`.
- R6/R16: `MOCK_CURL_FAIL_URL=cht.sh/:cht.sh`, pre-seeded `PRE-EXISTING` → FAIL, dest byte-identical, temp from `_cheat_tmp_from_calls 'https://cht.sh/:cht.sh'` non-empty and absent. Same for `_cht` alone with `MOCK_CURL_FAIL_URL=cheat.sh/:zsh`.
- R7: seed both files, `MOCK_CURL_STDOUT=$'#!/bin/bash\nx'` (binary succeeds, completion fails its head check); assert each URL's recorded line matches `--max-time 10( |$)`: `grep -E -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}" | grep -qF <url>`.
- R8: seed `cht.sh` only, `chmod 555 "${HOME}/bin"`, restore with `chmod 755` in the test before asserting (and in `teardown` if a test-scoped flag is set) → FAIL, `cheat.sh binary install failed` in `detail_cheat.sh`, dest unchanged, `refute_grep 'cht.sh/:cht.sh' "${MOCK_CALLS_FILE}"`.
- R11: good body, `MOCK_MV_FAIL_ARGS=".cht.sh."` → FAIL, `cheat.sh binary install failed`, dest unchanged, temp absent.
- R15: seed `cht.sh` only, `MOCK_CURL_STDOUT='Unknown topic.'` → FAIL, `cheat.sh binary fetch failed`, dest unchanged, temp absent.
- R18: seed `_cht` only, `MOCK_CURL_STDOUT=$'#!/bin/bash\nx'` → FAIL, `cheat.sh completion fetch failed`, `_cht` unchanged, temp absent.
- R20: after a successful update the binary mode is 754 and `_cht` 644 (`stat -c '%a' … 2>/dev/null || stat -f '%OLp' …`).

**Interfaces:** Consumes `_cheat_fetch`, `_cheat_tmp_from_calls`.

### Task 3: `run_setup_user` through the helper, and the substring test

```yaml-task
id: 3
description: Route run_setup_user's cheat.sh fetches through _cheat_fetch with warnings, and fix the max-time substring test
role: executor
model: sonnet
tdd: required
requirements: [R3, R4, R6, R7, R9, R12, R13, R14, R16, R20]
acceptance:
  - cmd: "! grep -qE 'curl -fsS -o \"\\$\\{HOME\\}/(bin/cht\\.sh|\\.zsh\\.d/_cht)\"' lib/workflows.sh"
    exit_code: 0
  - cmd: "! grep -qF \"grep -q -- '--max-time 10' \" tests/setup_env/workflows.bats"
    exit_code: 0
  - cmd: "bats -f 'run_setup_user|_fetch_github_latest' tests/setup_env/workflows.bats"
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: [2]
```

**Files:** `lib/workflows.sh` `run_setup_user` cheat.sh block (search `Setting up cheat.sh`). Binary: `_cheat_fetch https://cht.sh/:cht.sh "${HOME}/bin/cht.sh" 750 '#!'`, inside the existing `if [[ -d ${HOME}/bin ]]`; completion: `_cheat_fetch https://cheat.sh/:zsh "${HOME}/.zsh.d/_cht" 644 '#compdef'`, inside the existing `[[ ! -f ]]` guard. Each `|| case $? in 1) printf "cheat.sh <word> fetch failed\\n" >&2 ;; *) printf "cheat.sh <word> install failed\\n" >&2 ;; esac` — no `return`, setup continues.

Tests (`tests/setup_env/workflows.bats`, run_setup_user cheat.sh block ~:267–:327, and `_fetch_github_latest` ~:1488):

- R13: `:309` test → `refute_grep "chmod 750 ${HOME}/bin/.cht.sh." "${MOCK_CALLS_FILE}"`.
- R12: existing `curl()` override returning 22 for `cht.sh/:cht.sh`; `run run_setup_user`; `[[ "$output" == *"cheat.sh binary fetch failed"* ]]`.
- R6/R16: `MOCK_CURL_FAIL_URL=cht.sh/:cht.sh` with no override, pre-seeded `PRE-EXISTING` → status 0, dest unchanged, temp from calls absent.
- R7: both setup_user URLs carry `--max-time 10( |$)` in the calls file.
- R20: a `curl()` override that, for `cht.sh/:cht.sh`, records `curl $*` to `MOCK_CALLS_FILE` and writes `#!/bin/bash` to `"$3"`, and for `cheat.sh/:zsh` writes `#compdef cht.sh` to `"$3"`, else `command curl "$@"` → binary mode 750, `_cht` mode 644.
- R9: `:1492` → `grep -E -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}"`.

**Interfaces:** Consumes `_cheat_fetch`, `_cheat_tmp_from_calls`.

### Task 4: Documentation

```yaml-task
id: 4
description: Remove the two backlog rows and note atomic fetch in CLAUDE.md (docs-only, no behavior change, TDD not applicable)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R10]
acceptance:
  - cmd: "! grep -qF 'cheat.sh curls in `-t update` have no' docs/superpowers/README.md"
    exit_code: 0
  - cmd: "! grep -qF 'passes max-time 10` test matches a substring' docs/superpowers/README.md"
    exit_code: 0
  - cmd: "grep -qF 'never replaces the existing file' CLAUDE.md"
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md, CLAUDE.md]
depends_on: [3]
```

**Files:** `docs/superpowers/README.md` — delete the Backlog rows "cheat.sh curls in `-t update` have no `--max-time`" and "`_fetch_github_latest passes max-time 10` test matches a substring". `CLAUDE.md` — in the Key Conventions bullet beginning "The cheat.sh update section", add one sentence: "Both cheat.sh workflows fetch through `_cheat_fetch` (`--max-time 10`, first-line check, same-directory temp file and `mv`), so a failed, timed-out or wrong-content fetch never replaces the existing file." `make test` is not this task's gate: neither file is read by the suite; the orchestrator runs it after Task 4.

## Orchestrator steps

- [ ] Worktree `../dotfiles-cheat-sh-fetch` on `fix/cheat-sh-bounded-atomic-fetch`.
- [ ] Tasks 1–4 in order.
- [ ] Mutations V1, V2, V5–V9 (Verification above), each confirmed red then reverted; V3 listener probe; record outputs in the PR body.
- [ ] `make test` exit 0 after Task 4.
- [ ] Phase 3 via `finishing-a-development-branch`.

## Non-goal check

Reviewer verdicts (2026-10-09), all CLEAR; no plan revision or amendment needed:

- N1 CLEAR — `<url>` is positional and hardcoded at every call site; V3 uses it for a loopback probe; no environment override; `--max-time 10` is a literal.
- N2 CLEAR.
- N3 CLEAR.
- N4 CLEAR.
- N5 CLEAR — the R20 `curl()` override is test-local, not a change to `tests/mocks/curl`; `MOCK_CURL_FAIL_URL`, `MOCK_MV_FAIL_ARGS` and `MOCK_CURL_STDOUT` already exist.
- N6 CLEAR — R8's chmod restore is bats test cleanup, not a production signal trap.
