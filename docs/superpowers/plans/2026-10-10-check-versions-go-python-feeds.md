# check-versions go/python3 feeds Implementation Plan

spec: docs/superpowers/specs/2026-10-10-check-versions-go-python-feeds-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** go and python3 lines in `-t check-versions` read their latest version from go.dev and python.org, compare the repo pin, and `--update` writes their pins safely.

**Architecture:** Two feed fetchers parse JSON with `python3` (3.9 floor). A pin-based verdict function replaces `_check_one_version` for go and python3 only. `--update` dispatches go and python3 to dedicated writers that read back what they wrote; `Updated` prints only on success.

**Tech Stack:** bash, bats, `python3` stdlib (`json`, `re`), `tests/mocks/curl`, `tests/mocks/pyenv`.

## Global Constraints

- Every change is in `lib/workflows.sh` unless a task says otherwise. Shell standards: `[[ ]]`, `${VAR}`, `printf`, `|| return 1`, no `set -e`.
- Feed URLs, verbatim: `https://go.dev/dl/?mode=json` and `https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false`.
- Feed curls: `curl -sf --max-time 10`, no token, no `-H`.
- Fetcher parsing code is Python 3.9-compatible: `json`, `re`, tuple comparison only.
- No new environment-variable seam (N4). Tests isolate via `MOCK_CURL_STDOUT`, `MOCK_CALLS_FILE`, `MOCK_CURL_STDIN_FILE`, `_OVERRIDE_CONSTANTS_PATH`, PATH shims, and function overrides.
- New tests go in `tests/setup_env/check_versions_feeds.bats`, which loads helpers the way `tests/setup_env/check_versions_cargo.bats` does.
- Five GitHub-backed tools (ruby, yq, shellcheck, vagrant, gitleaks), homebrew-install and cargo checks keep their behaviour (N1).
- Implementation runs in a feature worktree on `claude`. `make test` measured 160s there (2026-10-10, rc 0, 2806 ok), under the 600s Bash cap; run it in the foreground with `timeout: 600000`.

## Verification Planning

- **Proves it works:** `./setup_env.sh -t check-versions` on `claude` and the Studio prints `[OK]` or `[OUTDATED]` for go and python3, never `could not fetch` (V1). Today (2026-10-10, pins go1.27.1 / 3.14.6) the expected lines are `[OUTDATED] go pinned=1.27.1 latest=1.27.2`, `[OUTDATED] python3 pinned=3.14.6 latest=3.14.8`, and `[INFO] python3 3.15 series available …`.
- **Edge cases:** pin newer than feed; pin in an unreleased series; feed down; `python3` absent; go read-back failure; pyenv unable to build; a free-threaded-only pyenv entry.
- **Orchestrator steps after Task 3** (results go in the PR body):
  - V2: `ssh studio` and run both fetchers under `env -i PATH=/usr/bin:/bin bash -c 'source lib/workflows.sh …'` against the live feeds; both must print a version.
  - V3: apply each mutation listed in the spec's V3 to a scratch copy, run `bats tests/setup_env/check_versions_feeds.bats`, record red/green per mutation. All seven must go red.

---

### Task 1: Feed fetchers

```yaml-task
id: 1
description: Add _fetch_go_latest and _fetch_python_latest with exact-value fixture tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R17, R19, R23, R25]
acceptance:
  - cmd: bats tests/setup_env/check_versions_feeds.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_feeds.bats]
depends_on: []
```

**Files:** `lib/workflows.sh` (beside `_fetch_github_latest`), new `tests/setup_env/check_versions_feeds.bats`.

**Behaviour:**

- `_fetch_go_latest`: `curl -sf --max-time 10 'https://go.dev/dl/?mode=json' | python3 -c '<parser>'`. The parser keeps entries with `stable` true whose `files[].filename` include both `<version>.linux-amd64.tar.gz` and `<version>.linux-arm64.tar.gz`, and prints the highest by numeric tuple without the `go` prefix. Prints nothing and exits non-zero on curl failure, a non-JSON body, or no qualifying entry.
- `_fetch_python_latest <series>`: one curl, then a parser that requires a JSON `list` (a dict is a failure), keeps names matching `^Python (\d+)\.(\d+)\.(\d+)$`, and prints `<in-series-highest> <overall-highest>`, or `- <overall-highest>` when no release is in the series. Empty output and non-zero exit when no name qualifies at all.
- Header comment above both: Python 3.9 floor, `json`/`re`/tuple comparison only; parsing must not use 3.10+ syntax.

**Fixtures (put in the bats file as heredocs, assign to `MOCK_CURL_STDOUT`):**

go, in order: `go1.29rc1` (stable false, both files); `go1.26.9` (stable, both); `go1.28.3` (stable, amd64 only); `go1.28.2` (stable, both); `go1.27.5` (stable, both). Expected: `1.28.2`.

python, in order: `Python 3.15.0rc1`, `Python install manager 26.4`, `Python 3.14.9`, `Python 3.15.1`, `Python 3.14.10`, `Python 3.10.20`. `_fetch_python_latest 3.14` → `3.14.10 3.15.1`; `_fetch_python_latest 3.16` → `- 3.15.1`.

**Tests:**

- The two positive controls above (exact `[ "$output" = … ]`).
- Failures, each `[ -z "$output" ]` and `[ "$status" -ne 0 ]`: `MOCK_CURL_EXIT=22`; body `not json`; python body `{"results": []}`; go body with no stable entry; python body with no `Python X.Y.Z` name.
- R25, calling the fetchers directly with `GITHUB_TOKEN=tok` and `MOCK_CURL_STDIN_FILE` set: `MOCK_CALLS_FILE` line contains `--max-time 10`, contains neither `Authorization` nor `-H`; the stdin file is empty or absent; `_fetch_python_latest 3.14` produces exactly one `python.org` line in `MOCK_CALLS_FILE`.

**Interfaces — Produces:** `_fetch_go_latest` (stdout `X.Y.Z`), `_fetch_python_latest <series>` (stdout `<series-latest|-> <overall-latest>`); both rc 0 on success, non-zero with empty stdout on failure.

---

### Task 2: Pin-based verdict, [INFO], token-refused count

```yaml-task
id: 2
description: Route go and python3 through a pin-versus-feed verdict and update existing count assertions
role: executor
model: sonnet
tdd: required
requirements: [R6, R7, R8, R9, R10, R11, R20, R24, R26]
acceptance:
  - cmd: bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats tests/setup_env/check_versions_cargo.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_feeds.bats, tests/setup_env/workflows.bats]
depends_on: [1]
```

**Behaviour:**

- `_check_one_pin_version <tool> <pinned>` for `go` and `python3`. No `[SKIP] not installed`. If `command -v python3` fails: `[WARN] <tool> python3 not found; cannot read the release feed`, return 0. Empty fetch: `[WARN] <tool> could not fetch latest version`.
- go: pinned = version parsed from `GO_DOWNLOAD_FILENAME` (`go1.27.1.linux-amd64.tar.gz` → `1.27.1`). Unparseable: `[WARN] go could not parse pinned version`. Latest = `_fetch_go_latest`.
- python3: pinned = `PYTHON_VER`; `read -r _series_latest _overall < <(_fetch_python_latest "${PYTHON_VER%.*}")`. If `_series_latest` is `-`: `[WARN] python3 no <series> release in the feed yet (pinned=<pin> latest=<overall>)`.
- Comparison is numeric (`sort -V` is not allowed — uutils; compare split integer fields). `pinned >= latest` prints `[OK]       %-12s pinned=%-10s latest=%s`; otherwise `[OUTDATED] … pinned=… latest=…`, return 1.
- python3: when `_overall`'s major.minor is newer than the pin's, add `  [INFO]     python3      <major.minor> series available (series move: requires-python, uv lock)`. The INFO line is never counted.
- `_run_cv_check` sends go/python3 here. With a refused token, only the five GitHub-backed calls are skipped and counted; the message says `the 5 checks that send it were not run`.

**Existing tests to update in `tests/setup_env/workflows.bats`:** these stub `_check_one_version`, so go and python3 no longer pass through the stub. Override `_check_one_pin_version` alongside in each, then assert `7 not checked`→`5`, `-eq 7`→`-eq 5` plus 2 pin-version calls, `7 skipped`→`5 skipped`, `7 OK`→ OK total including the two pin stubs, `7 outdated`→ likewise. Leave `16 warnings` (it still holds: the real pin path WARNs on the empty curl mock), but update its comment.

**New tests** (whole-command ones override `_fetch_go_latest`/`_fetch_python_latest` as functions):

- go OK/OUTDATED against `GO_DOWNLOAD_FILENAME`, with a `go` stub on PATH printing `go version go9.9.9 linux/amd64` to prove installed is ignored; unparseable filename → parse WARN.
- python3 pin 3.14.6, fetch `3.14.8 3.15.1` → `[OUTDATED]` + `[INFO] … 3.15 series available`, outdated 1.
- R20: pin 3.14.8, fetch `3.14.8 3.15.1` → `[OK]` + `[INFO]`, summary `0 outdated`, `run_check_versions` rc 0 (stub every other check OK).
- pin equals overall → no `[INFO]`.
- R24: go pin 1.28.0 vs latest 1.27.2 → `[OK]`; python pin 3.14.9 vs `3.14.8 3.15.1` → `[OK]`.
- R26: pin 3.16.0, fetch `- 3.15.1` → the `no 3.16 release` WARN, counted, no `could not fetch`.
- python3 not resolvable (PATH shim with no `python3`) → `python3 not found` text, no `could not fetch`.
- Token refused: go and python3 lines still print; `5 not checked`.

**Interfaces — Consumes:** Task 1 fetchers. **Produces:** `_check_one_pin_version <tool> <pinned>` (rc 0 OK/WARN, 1 OUTDATED); OUTDATED line format unchanged so `_run_cv_check`'s `latest=` parse still works.

---

### Task 3: `--update` writers, guard, next steps

```yaml-task
id: 3
description: Add go and python3 pin writers with read-back, pyenv guard, Updated gating and next-step lines
role: executor
model: sonnet
tdd: required
requirements: [R12, R13, R14, R15, R16, R21, R22]
acceptance:
  - cmd: bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_feeds.bats, tests/mocks/pyenv, tests/setup_env/workflows.bats]
depends_on: [2]
```

**Behaviour:**

- `_prompt_version_update` dispatches on tool: `go` → `_update_go_pin <latest>`, `python3` → `_update_python_pin <old> <new>`; in those two branches only, `Updated <var> → <new>` prints only when the writer returned 0. The `else` branch keeps today's code byte-for-byte: `_update_version_pin` then an unconditional `Updated` (N1).
- `_update_go_pin <latest>`: sets `GO_VER="<major.minor>"`, then the `GO_DOWNLOAD_FILENAME` version via `_update_url_pins go`. Read back with `grep -Fqx` against the literal lines `GO_VER="1.28"` and `GO_DOWNLOAD_FILENAME="go1.28.0.linux-${_LINUX_ARCH}.tar.gz"` (single-quoted in source so `${_LINUX_ARCH}` stays literal). Mismatch: `go: pin update failed: <CONSTANT> is not <expected>`, return 1. Success prints `go: after this change merges and each machine pulls: on macOS run brew upgrade go; on Linux run ./setup_env.sh -t developer`; if `command -v go` resolves and its version's major.minor differs from the new `GO_VER`, print `go: this machine runs <installed>, outside the new <GO_VER> series; doctor fails here until go is upgraded`.
- `_update_python_pin <old> <new>`: guard first. No `pyenv`, or `pyenv install --list | grep -Eq "^[[:space:]]*${new//./\\.}\$"` fails: `python3: pyenv on this machine cannot build <new>; run brew upgrade pyenv`, return 1, file untouched. Otherwise sed `PYTHON_VER`, read back `grep -Fqx "PYTHON_VER=\"<new>\""`, mismatch → `pin update failed`, return 1. Success prints `python3: after this change merges and each machine pulls: run brew upgrade pyenv, then on macOS pyenv install <new> && ./setup_env.sh -t ansible; on Linux ./setup_env.sh -t ansible`.
- `tests/mocks/pyenv`: `install --list` prints `MOCK_PYENV_INSTALL_LIST` (newline-separated) and exits 0.
- `tests/setup_env/workflows.bats`: the three `_prompt_version_update … y/n/empty reply` tests call it with `go` to exercise the generic `_update_version_pin` path. Go now routes to `_update_go_pin`, so switch those three to `yq` (`YQ_VER`, seeded the same way) so they keep testing the generic branch; go's own behaviour is covered by the new tests below.

**Tests** (constants copy via the `setup_constants_copy` pattern and `_OVERRIDE_CONSTANTS_PATH`; reply via `<<< "y"`):

- go in series (seed `GO_VER="1.27"`, filename `go1.27.1`): update to 1.27.2 → `GO_VER="1.27"`, filename `go1.27.2.linux-${_LINUX_ARCH}`, `Updated`, next-step line.
- go across a minor → both move.
- go read-back failure (delete the `GO_VER=` line from the copy) → rc 1, `pin update failed`, no `Updated`.
- go local-series warning: stub `go` reporting 1.27.1 → warning; 1.28.0 → none; no `go` on PATH → none and no empty version.
- python ok (`MOCK_PYENV_INSTALL_LIST=$'  3.14.8\n  3.14.8t'`): `PYTHON_VER="3.14.8"`, `Updated`, next-step contains `after this change merges and each machine pulls`, `pyenv install 3.14.8 && ./setup_env.sh -t ansible`, `on Linux ./setup_env.sh -t ansible`, not `recreate-venv`.
- python `3.14.8t` only: file byte-identical (`cmp`), `cannot build` printed, no `Updated`, `MOCK_CALLS_FILE` has `pyenv install --list`.
- python no `pyenv` (PATH shim): byte-identical, `cannot build`, no `Updated`.
- python read-back failure (remove `PYTHON_VER=` line, pyenv lists it) → rc 1, `pin update failed`, no `Updated`.
- Pin ahead (R24/N6): `run_check_versions` with `UPDATE_VERSIONS=1`, go pin 1.28.0 vs 1.27.2 and python pin 3.14.9 vs `3.14.8 3.15.1` → both `[OK]`, no prompt, constants byte-identical.

**Interfaces — Consumes:** Task 2's OUTDATED line. **Produces:** `_update_go_pin`, `_update_python_pin` (rc 0 written and verified, 1 refused or failed).

---

### Task 4: Docs

```yaml-task
id: 4
description: Update CLAUDE.md check-versions bullet and constants.sh comment (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R18]
acceptance:
  - cmd: grep -qE '(five|5) GitHub' CLAUDE.md
    exit_code: 0
  - cmd: grep -qE 'go\.dev.*python\.org|python\.org.*go\.dev' CLAUDE.md
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, lib/constants.sh]
depends_on: [3]
```

**Changes:**

- `CLAUDE.md`, `check-versions` bullet under Entry Points: replace `the seven GitHub-release checks are not run` wording with five; add one sentence: go compares the pin in `GO_DOWNLOAD_FILENAME` with go.dev's latest stable; python3 compares `PYTHON_VER` with python.org's latest in its series and prints a newer series as an uncounted `[INFO]` line; `--update` writes both through read-back writers and prints the next steps to run after the PR merges.
- `lib/constants.sh`: reword the comment above `GO_DOWNLOAD_FILENAME` so it states what must hold (both Linux tarballs published, checked by `_fetch_go_latest`) instead of naming the version that was checked.

`lib/constants.sh` comment edits cannot change the suite; the orchestrator runs `make test` once after this task.

## Non-goal check

Reviewer run 2026-10-10 against N1–N6: 5 CLEAR, 1 UNCLEAR, 0 CONFLICT.

- **N1 — UNCLEAR.** Quote: "`_prompt_version_update` dispatches on tool: ... else `_update_version_pin` as today. `Updated <var> → <new>` prints only when the writer returned 0." Why: the gating sat in the shared function and so governed the five GitHub-backed tools too. Resolution (plan revision): before — "`Updated <var> → <new>` prints only when the writer returned 0."; after — "in those two branches only, `Updated <var> → <new>` prints only when the writer returned 0. The `else` branch keeps today's code byte-for-byte: `_update_version_pin` then an unconditional `Updated` (N1)."
- **N2–N6 — CLEAR.**
