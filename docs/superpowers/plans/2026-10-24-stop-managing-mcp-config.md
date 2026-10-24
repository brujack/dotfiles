# Stop managing MCP configuration Implementation Plan

> **Status: DONE** — merged as dotfiles#371 (18baf396) on 2026-10-24.

spec: docs/superpowers/specs/2026-10-24-stop-managing-mcp-config-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete dotfiles' generation and doctor check of `~/.claude/mcp.json` (bash and Windows), their tests and docs, since Claude Code does not read that file.

**Architecture:** Pure deletion in three disjoint slices: bash code and tests, the PowerShell function and its Pester tests, then docs and Backlog. Two surviving tests that used a deleted function as a sentinel are re-pointed at a surviving one.

**Tech Stack:** bash, bats, PowerShell/Pester (CI only; Pester is not installed on `claude`).

## Global Constraints

- No change to any other repo (spec N1), to `setup_dotfile_symlinks` (N2), to dated records (N3), or to `_github_auth_header`, `_github_api_base`, `_fetch_github_latest`, `Brewfile` (N4).
- Shell session is zsh with `grep` a function: write gates and probes with `command grep`.
- Commit messages are given verbatim per task; do not invoke `caveman:caveman-commit`.

## Verification

- Orchestrator, once after Task 3: `make test` passes with `1..<master minus 35>` (master `1..3371`, so `1..3336`).
- `setup_env.sh -t doctor` output has no `GitHub MCP:` heading.
- CI: `bash-coverage` at least 91%, `powershell` coverage at least 90% (95.09% on master).

---

### Task 1: Delete the bash generation, the doctor check and their tests

```yaml-task
id: 1
description: Delete setup_claude_mcp and _doctor_check_github_mcp, their calls, tests and stubs, and the manifest link (deletion; no new behaviour, so no RED test)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R1, R2, R3, R5]
acceptance:
  - cmd: '! git grep -q -e setup_claude_mcp -e _doctor_check_github_mcp -- lib tests setup_env.sh scripts'
    exit_code: 0
  - cmd: 'command grep -q "^_github_auth_header()" lib/helpers.sh && command grep -q "^_github_api_base()" lib/helpers.sh'
    exit_code: 0
  - cmd: '! command grep -q GITHUB_PAT_EXPIRY lib/helpers.sh'
    exit_code: 0
  - cmd: '! command grep -q mcp.json.template manifests/dotfiles/ai-config.yaml'
    exit_code: 0
  - cmd: 'make lint'
    exit_code: 0
  - cmd: 'bats --jobs 8 tests/setup_env/unit.bats tests/setup_env/workflows.bats tests/setup_env/install_guards.bats tests/setup_env/plugin_node_paths.bats < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, lib/helpers.sh, lib/constants.sh, manifests/dotfiles/ai-config.yaml, tests/setup_env/unit.bats, tests/setup_env/workflows.bats, tests/setup_env/install_guards.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: []
```

**Steps:**

- [ ] `lib/workflows.sh`: delete the whole `setup_claude_mcp()` function (top of file, through its closing `}` and the blank line after it). Delete the line `  setup_claude_mcp || return 1` in `run_setup_user`. In the comment block a few lines below that ends "matching the / pre-existing `setup_claude_mcp || return 1` style used everywhere else / in this function.", replace the cited call with `setup_ai_config || return 1`.
- [ ] `lib/helpers.sh`: delete `_doctor_check_github_mcp()` (heading `printf "\nGitHub MCP:\n"` through its closing `}`) and its call line in `run_doctor`. In the `_doctor_check_aws_key_expiry` header, replace the sentence starting "90 days, not GITHUB_PAT_EXPIRY's 30:" with "90 days: refreshing this key means AWS publishing a new one, verifying its fingerprint out of band, updating AWSCLI_GPG_FPR in lib/constants.sh, and shipping that through review -- a slow process needs a long lead time." Keep `_github_auth_header` and `_github_api_base`.
- [ ] `lib/constants.sh`: in the `AI_CONFIG_DIR` comment, change `lib/workflows.sh:setup_claude_mcp/setup_ai_config` to `lib/workflows.sh:setup_ai_config`.
- [ ] `manifests/dotfiles/ai-config.yaml`: delete the `file.link` item whose `source` is `.../.claude/mcp.json.template` (its `- action:` line, `source:`, `target:` and one adjacent blank line).
- [ ] Delete the 35 tests whose `@test` name contains `setup_claude_mcp` or `_doctor_check_github_mcp` (15 in `tests/setup_env/workflows.bats`, 2 in `install_guards.bats`, 18 in `unit.bats`), each from `@test` through its closing `}`, plus any section-header comment left with no tests under it (`# ── setup_claude_mcp ...`, `# ── _doctor_check_github_mcp ...`, `# ── setup_claude_mcp: envsubst not installed ...`). Delete any helper that only those tests used (check with `command grep -n` before deleting).
- [ ] Delete every remaining stub line `_doctor_check_github_mcp() ...` / `setup_claude_mcp() ...` in `unit.bats`, `workflows.bats`, `install_guards.bats`, `plugin_node_paths.bats`, except the two below.
- [ ] `unit.bats` "run_doctor summary includes warnings count": delete the `_doctor_check_github_mcp` stub and change `_doctor_check_aws_key_expiry() { :; }` to `_doctor_check_aws_key_expiry() { doctor_warn "test" "a warning"; }`. Leave the assertion as is.
- [ ] `workflows.bats` "run_setup_user calls install_bats on macOS, and aborts when it returns non-zero": replace `setup_claude_mcp() { printf 'MCP_CALLED\n'; return 0; }` with `clone_or_update_dotfiles() { printf 'LATER_STEP_CALLED\n'; return 0; }` and `MCP_CALLED` in the assertion with `LATER_STEP_CALLED`.
- [ ] Prove the two re-pointed tests still discriminate: temporarily make `run_doctor` skip `_doctor_check_aws_key_expiry` (or make `run_setup_user` ignore `install_bats`' return), confirm the test goes red, revert. Report both results.
- [ ] Run the gates (each with `< /dev/null`, synchronously). Do not run `make test`.
- [ ] Commit exact paths with this message:

```
chore: stop generating and checking ~/.claude/mcp.json

Claude Code does not read ~/.claude/mcp.json, so setup_claude_mcp
(always stopped by its own symlink guard) and the doctor GitHub MCP
check guarded a file nothing consumes. Remove both, their tests and
stubs, and the manifest link for the template.
```

**Interfaces:** Produces: no `setup_claude_mcp`, no `_doctor_check_github_mcp`. Consumes nothing.

### Task 2: Delete the Windows mcp.json generation

```yaml-task
id: 2
description: Remove Set-ClaudeConfig's mcp.json.template link and mcp.json generation and their two Pester tests (deletion only; Pester runs in CI)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R4]
acceptance:
  - cmd: '! command grep -qE "mcp\.json|GITHUB_PAT" powershell/setup_windows.ps1'
    exit_code: 0
  - cmd: '! command grep -qE "mcp\.json|GITHUB_PAT" powershell/tests/setup_windows.Tests.ps1'
    exit_code: 0
  - cmd: 'pwsh -NoProfile -Command "foreach ($f in @(''powershell/setup_windows.ps1'',''powershell/tests/setup_windows.Tests.ps1'')) { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$e); if ($e.Count) { $e; exit 1 } }"'
    exit_code: 0
max_retries: 3
files_touched: [powershell/setup_windows.ps1, powershell/tests/setup_windows.Tests.ps1]
depends_on: [1]
```

**Steps:**

- [ ] `powershell/setup_windows.ps1` `Set-ClaudeConfig`: change `@("settings.json", "CLAUDE.md", "mcp.json.template")` to `@("settings.json", "CLAUDE.md")`, and delete the block from `$templatePath = "$claudeDir/mcp.json.template"` through the closing `}` of its `if (Test-Path $templatePath)`.
- [ ] `powershell/tests/setup_windows.Tests.ps1`: delete the `It "writes mcp.json with GITHUB_PAT substituted"` and `It "warns and writes template unchanged when GITHUB_PAT is unset"` blocks, plus any `BeforeEach`/`AfterEach`/mock lines in that `Describe "Set-ClaudeConfig"` that exist only for them (the `savedPAT` save/restore and the `Get-Content` mock returning `${GITHUB_PAT}`). Keep every other `It` in that `Describe` and check none of them relies on what you removed.
- [ ] Run the gates. Pester is not installed on this machine; the CI `powershell` job is the real test.
- [ ] Commit with: `chore(windows): stop generating mcp.json` (body: `Claude Code does not read ~/.claude/mcp.json on any platform; drop the template link and the PAT substitution.`).

### Task 3: Docs and Backlog

```yaml-task
id: 3
description: Remove the GitHub MCP and GITHUB_PAT text from CLAUDE.md, README.md and config/local.sh.example, close two Backlog rows and add one (docs-only, no behaviour)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R6, R7]
acceptance:
  - cmd: '! command grep -qE "GITHUB_PAT|GitHub MCP|setup_claude_mcp|mcp\.json\.template" CLAUDE.md README.md config/local.sh.example'
    exit_code: 0
  - cmd: '! command grep -qE "^\| (`setup_claude_mcp`.s template generation is unreachable|`doctor` reports `mcp\.json \(generated\)`)" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'command grep -q "run_doctor summary includes warnings count" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, README.md, config/local.sh.example, docs/superpowers/README.md]
depends_on: [2]
```

**Steps:**

- [ ] `CLAUDE.md`: delete the `## GitHub MCP` section (heading through the line before the next `## `); delete the Symlink Strategy bullet starting "- `~/.claude/mcp.json` is a symlink into"; in "Windows AI Config Setup", remove the clause about setting `GITHUB_PAT` (it fills `mcp.json`) from the `setup_windows.ps1 -setup` bullet and `, \`GITHUB_PAT\` env var for MCP config` from the "Requires:" line. Touch nothing else.
- [ ] `README.md`: delete the `### GitHub MCP` section (through the line before the next heading of the same or higher level) and the line-97 sentence starting "At minimum, set `GITHUB_PAT`". Fix any table-of-contents link to the removed section.
- [ ] `config/local.sh.example`: delete the GitHub PAT comment block and its `# export GITHUB_PAT=""` and `# export GITHUB_PAT_EXPIRY=""` lines.
- [ ] `docs/superpowers/README.md`: delete the two Backlog rows starting "| `setup_claude_mcp`'s template generation is unreachable" and "| `doctor` reports `mcp.json (generated)`"; add to the P2 test-gaps table: ``| `run_doctor summary includes warnings count` matches 11 warnings | `tests/setup_env/unit.bats` "run_doctor summary includes warnings count" asserts `*"1 warnings"*`, a substring that also matches "11 warnings", and leaves `_doctor_check_brew_links`, `_doctor_check_renovate_cadence` and `_doctor_check_ledger_drift_cadence` unstubbed; anchor it as `*", 0 failed, 1 warnings"*` (the form at the later summary test) and stub every check. Found by the MCP-removal spec review. |``
- [ ] Run the gates, then commit with: `docs: drop GitHub MCP and GITHUB_PAT setup text`.

## Non-goal check

Fresh reviewer, 2026-10-24: 3 CLEAR (N1, N3, N4), 1 UNCLEAR (N2), 0 CONFLICT.

- **N2** UNCLEAR: "Task 1 step: `manifests/dotfiles/ai-config.yaml`: delete the `file.link` item whose `source` is `.../.claude/mcp.json.template`" — falls inside N2 only if `setup_dotfile_symlinks` reads that manifest. Resolution: checked, it does not. `setup_dotfile_symlinks` (`lib/helpers.sh`) iterates `ai-config/.claude/*` directly; the manifest's only consumer is `etch.yaml`'s `manifest_paths` (etch-cli). The deletion is R5's change and leaves `setup_dotfile_symlinks` untouched. No plan text changed.
- **N1, N3, N4** CLEAR. Resolution: none needed.
