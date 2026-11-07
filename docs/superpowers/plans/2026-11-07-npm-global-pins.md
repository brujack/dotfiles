# npm Global Pins Implementation Plan

> **Status: DONE** — merged in dotfiles#433 (256817b3), 2026-11-07.

spec: docs/superpowers/specs/2026-11-07-npm-global-pins-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin `firecrawl-cli` on Windows, pin and install the firecrawl and context7 MCP server binaries, and make the pin-check test helper see scoped package names.

**Architecture:** bash pins stay in `lib/constants.sh` and are read by `_require_npm_pins`, `run_developer_or_ansible` and `run_update`. Windows keeps one PowerShell copy of the `firecrawl-cli` version. A bats drift test keeps that copy equal to the bash pin.

**Tech Stack:** bash, bats, PowerShell 7 and Pester 5 (Pester runs in CI only; `claude` has no Pester).

## Global Constraints

- `FIRECRAWL_MCP_VER="3.38.0"`, `CONTEXT7_MCP_VER="4.4.4"`, `FIRECRAWL_CLI_VER="1.26.3"` (unchanged); package names `firecrawl-mcp` and `@upstash/context7-mcp`.
- No PowerShell code reads `lib/constants.sh`, and no shared pin manifest is introduced (N1). No MCP package is installed on native Windows (N2). No other npm pin changes value (N3).
- Work only in `/home/bruce/git-repos/personal/dotfiles-npm-pins/` (branch `feat/npm-global-pins`).
- Per-task gates are scoped. The orchestrator runs `make test` once after Task 3, and again after Task 4.

## Verification

- `make test` exits 0 with 0 `not ok`.
- Mutation controls, run by the orchestrator after Task 3: changing `$FirecrawlCliVersion` to `'1.26.4'` turns `tests/scripts/windows_npm_pins.bats` red; reverting the helper to `*@?*` turns the scoped-token test red.
- The CI `powershell` job passes, so Pester R2 holds.
- After merge (V3): on `claude`, the workstation and the Studio, run the spec's Rollout command, then `command -v firecrawl-mcp` and `command -v context7-mcp` separately, and record `npm ls -g` in the PR body.

---

### Task 1: The pin-check helper sees scoped names

```yaml-task
id: 1
description: assert_all_npm_globals_pinned rejects an unpinned scoped package and an empty version
role: executor
model: sonnet
tdd: required
requirements: [R7]
acceptance:
  - cmd: bats -f 'judges scoped' tests/setup_env/workflows.bats
    exit_code: 0
    stdout_match: 'ok 1 assert_all_npm_globals_pinned judges scoped'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/workflows.bats]
depends_on: []
```

**Files:** `tests/setup_env/workflows.bats`. The helper is at about line 2640 and its header comment is at about 2635-2639.

- [ ] RED: add `@test "assert_all_npm_globals_pinned judges scoped and unscoped tokens"` right after the helper. For each case, write a one-line mock-calls file under `${BATS_TEST_TMPDIR}` and `run assert_all_npm_globals_pinned <file>`:
  - `npm install -g @upstash/context7-mcp`: status 1
  - `npm install -g @upstash/context7-mcp@4.4.4`: status 0
  - `npm install -g jscpd`: status 1
  - `npm install -g jscpd@`: status 1
  - `npm install -g jscpd@5.4.1`: status 0

  Run `bats -f 'judges scoped' tests/setup_env/workflows.bats`. It must fail on the first case, because the current `*@?*` check accepts the scope's `@`.

- [ ] GREEN: replace the `*@?*` check with a regex on each token: `[[ "${_tok}" =~ ^(@[^/@]+/)?[^@/]+@[^@]+$ ]]`. A token that fails it prints the existing `unpinned npm global:` message and returns 1.
- [ ] Rewrite the header comment's "Does not handle @scope/pkg specs; none are used here" to state the rule: a pinned token is `name@ver` or `@scope/name@ver`, with a non-empty version.
- [ ] Commit (`caveman:caveman-commit`).

**Interfaces:** Produces the corrected `assert_all_npm_globals_pinned <file>`, which Task 2's tests rely on.

### Task 2: Pin and install firecrawl-mcp and context7-mcp

```yaml-task
id: 2
description: Add FIRECRAWL_MCP_VER and CONTEXT7_MCP_VER and install both wherever EXA_MCP_SERVER_VER is installed
role: executor
model: sonnet
tdd: required
requirements: [R4, R5, R6]
acceptance:
  - cmd: bats -f 'npm' tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: 'grep -c "firecrawl-mcp@\${FIRECRAWL_MCP_VER}" lib/workflows.sh'
    exit_code: 0
    stdout_match: '^2$'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: [1]
```

The grep gate is 0 on the base tree and 2 once both install sites are pinned.

- [ ] RED, in `tests/setup_env/workflows.bats`:
  - "run_developer_or_ansible pins every npm global package" (about line 2660): add `grep -q "npm install -g firecrawl-mcp@3.38.0"` and `grep -q "npm install -g @upstash/context7-mcp@4.4.4"`.
  - The `run_update` pinned test (about line 3874): add `grep -qE '^npm install -g .*firecrawl-mcp@3\.38\.0'` and `grep -qE '^npm install -g .*@upstash/context7-mcp@4\.4\.4'`. Rewrite its comment ("installs all three packages in ONE invocation ... the other two") without a count.
  - "_require_npm_pins names every missing pin" (about line 3926): also set `FIRECRAWL_MCP_VER=""` and `CONTEXT7_MCP_VER=""` (each with the existing SC2034 disable-comment shape) and assert both names appear in `$output`.

  Run them and confirm they fail.

- [ ] GREEN:
  - `lib/constants.sh`: insert `CONTEXT7_MCP_VER="4.4.4"` before `EXA_MCP_SERVER_VER` and `FIRECRAWL_MCP_VER="3.38.0"` after `FIRECRAWL_CLI_VER`. Give each the line `# read by lib/workflows.sh:_require_npm_pins and run_developer_or_ansible` above it.
  - `lib/workflows.sh` `_require_npm_pins`: add the two `[[ -z ... ]] && _missing=...` lines.
  - `run_developer_or_ansible`, after the exa block: add `printf "Installing firecrawl-mcp via npm\n"` / `npm install -g "firecrawl-mcp@${FIRECRAWL_MCP_VER}" || return 1`, then `printf "Installing context7-mcp via npm\n"` / `npm install -g "@upstash/context7-mcp@${CONTEXT7_MCP_VER}" || return 1`.
  - `run_update`'s single `npm install -g` call (about line 1127): add `"firecrawl-mcp@${FIRECRAWL_MCP_VER}"` and `"@upstash/context7-mcp@${CONTEXT7_MCP_VER}"` as continuation lines before `2>&1`.
- [ ] Commit.

**Interfaces:** Consumes Task 1's helper. Produces the constants named above.

### Task 3: Pin firecrawl-cli on Windows with a drift test

```yaml-task
id: 3
description: setup_windows.ps1 installs firecrawl-cli@$FirecrawlCliVersion; Pester asserts equality; bats keeps the .ps1 copy equal to FIRECRAWL_CLI_VER
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3]
acceptance:
  - cmd: bats tests/scripts/windows_npm_pins.bats
    exit_code: 0
  - cmd: 'grep -c "firecrawl-cli@\$FirecrawlCliVersion" powershell/setup_windows.ps1'
    exit_code: 0
    stdout_match: '^1$'
  - cmd: 'pwsh -NoProfile -Command "$e=$null; foreach($f in ''powershell/setup_windows.ps1'',''powershell/tests/setup_windows.Tests.ps1''){[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$null,[ref]$e); if($e){$e; exit 1}}"'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [powershell/setup_windows.ps1, powershell/tests/setup_windows.Tests.ps1, tests/scripts/windows_npm_pins.bats, lib/constants.sh]
depends_on: [2]
```

On the base tree the grep gate prints 0 and `bats` exits 1 because the file is missing. That missing-file failure is not a measurement; the RED step below is.

- [ ] RED: create `tests/scripts/windows_npm_pins.bats`. It reads `REPO_ROOT` the way sibling files in `tests/scripts/` do, and defines one helper per file:
  - `_ps1_ver`: lines matching `^\$FirecrawlCliVersion = '([^']*)'$` in `powershell/setup_windows.ps1`.
  - `_sh_ver`: lines matching `^FIRECRAWL_CLI_VER="([^"]*)"$` in `lib/constants.sh`.

  Tests:
  1. Each file has exactly 1 matching line (assert the count, not membership).
  2. Each value matches `^[0-9]+\.[0-9]+\.[0-9]+$`.
  3. The values are equal; on mismatch, `printf` both paths and both values to stderr before failing.
  4. The extraction is pinned: run the helpers on fixture copies under `${BATS_TEST_TMPDIR}` holding `'9.9.9'` and `"1.0.0"` and assert the equality check fails. Run them on zero-definition and two-definition fixtures and assert the count check fails.

  Running it must fail on the base tree, because the `.ps1` has no definition.

- [ ] GREEN:
  - `setup_windows.ps1`: after the `param(...)` block add a plain top-level `$FirecrawlCliVersion = '1.26.3'`, not `$script:`. Its comment names `FIRECRAWL_CLI_VER` in `lib/constants.sh` and `tests/scripts/windows_npm_pins.bats`.
  - In `Set-NpmGlobalPackages`, use `npm install -g "firecrawl-cli@$FirecrawlCliVersion"`.
- [ ] Pester (`setup_windows.Tests.ps1`, about line 728):
  - Rename the It to "installs firecrawl-cli pinned to `$FirecrawlCliVersion` when node is available". Its ParameterFilter requires `$args -contains "firecrawl-cli@$FirecrawlCliVersion"` plus `install` and `-g`, with `-Times 1`.
  - Add `Should -Invoke npm -ParameterFilter { $args -contains 'firecrawl-cli' } -Times 0`.
  - Add `$FirecrawlCliVersion | Should -Match '^\d+\.\d+\.\d+$'`.
- [ ] `lib/constants.sh`: extend the comment above `FIRECRAWL_CLI_VER` to name the `.ps1` copy and the drift test.
- [ ] Commit.

### Task 4: Docs

```yaml-task
id: 4
description: Backlog rows 378/379 and the CLAUDE.md setup_windows line (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R8]
acceptance:
  - cmd: '! grep -q "installs .firecrawl-cli. unpinned" docs/superpowers/README.md'
    exit_code: 0
  - cmd: '! grep -q "The three npm pins" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -qE "Set-NpmGlobalPackages.*firecrawl-cli@.*windows_npm_pins" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md, CLAUDE.md]
depends_on: [3]
```

- [ ] Delete the backlog row starting ``| `powershell/setup_windows.ps1` installs `firecrawl-cli` unpinned``.
- [ ] In the "npm global pin bump path" row, replace the sentence naming "The three npm pins added in PR dotfiles#192 (...)" with a count-free one: the npm pins in `lib/constants.sh` (the block starting `# npm global packages`) are bumped by hand. Add: a `FIRECRAWL_CLI_VER` bump also edits `$FirecrawlCliVersion` in `powershell/setup_windows.ps1`, and `tests/scripts/windows_npm_pins.bats` fails if the two differ. Leave the rest of the row unchanged.
- [ ] CLAUDE.md: change ``(`Set-NpmGlobalPackages` → `firecrawl-cli`)`` to ``(`Set-NpmGlobalPackages` → `firecrawl-cli@$FirecrawlCliVersion`, kept equal to `FIRECRAWL_CLI_VER` by `tests/scripts/windows_npm_pins.bats`)``.
- [ ] Commit.

## Non-goal check

Fresh reviewer, 2026-11-07: 3 CLEAR, 0 CONFLICT, 0 UNCLEAR.

- **N1 CLEAR.** "The cross-file comparison is a bats test that reads both files, and the `.ps1` keeps its own literal copy of the version. The plan adds no shared manifest."
- **N2 CLEAR.** "On Windows, Task 3 touches only the `firecrawl-cli` install. The two MCP installs exist only in the bash `run_developer_or_ansible` and `run_update`."
- **N3 CLEAR.** "The two MCP pins are new constants, not changes to existing values. `FIRECRAWL_CLI_VER` and `EXA_MCP_SERVER_VER` are unchanged."

Resolution: none needed.
