# Stop managing MCP configuration

- **Date:** 2026-10-24
- **Approved:** 2026-10-24
- **Backlog rows closed:** "`setup_claude_mcp`'s template generation is unreachable on every machine" and "`doctor` reports `mcp.json (generated)` for a file it only tested for existence" (both P2 bugs and security).

## Problem

dotfiles generates, links and checks `~/.claude/mcp.json`, and Claude Code does not read that file. Measured on `claude`, 2026-10-24:

- `~/.claude/mcp.json` is a symlink to `ai-config/.claude/mcp.json`, which declares one server, `exa`.
- `claude mcp get exa` prints `No MCP server named "exa"`; `claude mcp list` lists only the claude.ai connectors and the plugin servers (`context-mode`, `context7`, `firecrawl`).
- `~/.claude.json`, where Claude Code keeps user-scope MCP servers, has an empty `mcpServers`; neither `~/.claude/settings.json` nor `settings.local.json` declares any.

So the mechanism is dead twice over. `setup_claude_mcp` never writes the file, because `setup_dotfile_symlinks` links it first and the function's own symlink guard returns 0; and a generated file would be ignored anyway. `_doctor_check_github_mcp` prints `[PASS] ~/.claude/mcp.json (generated)` for a file that was neither generated nor read, and `CLAUDE.md`'s "GitHub MCP" section states a GitHub MCP server is configured when none is.

`GITHUB_PAT` exists only for this. In dotfiles its readers are `setup_claude_mcp`, `_doctor_check_github_mcp` (file check, live `/user` call, `GITHUB_PAT_EXPIRY` check) and `powershell/setup_windows.ps1`'s `Set-ClaudeConfig`. Outside dotfiles, etch-config's `workstation/dev.yaml` and `etch-cli-test/dev.yaml` (plus a copy in its `tests/fixtures/history/`) each have a "Claude MCP setup" step that sources dotfiles' `config/local.sh` and runs `envsubst … > ~/.claude/mcp.json`. That step's guard removes only a dangling symlink, so on a machine with `GITHUB_PAT` set it writes the token through the live symlink into the tracked `ai-config/.claude/mcp.json`. Checked 2026-10-24 on `claude`: `config/local.sh` sets `GITHUB_PAT`, and `ai-config/.claude/mcp.json` holds no token and is clean in `git status`, so the exposure is latent. The operator decided on 2026-10-24 that dotfiles stops managing MCP configuration.

## Design

Delete the generation, the check and the documentation of both. Nothing replaces them.

1. `lib/workflows.sh`: delete `setup_claude_mcp` and its call `setup_claude_mcp || return 1` in `run_setup_user`, and update the comment that cites that call as a style precedent.
2. `lib/helpers.sh`: delete `_doctor_check_github_mcp` and its call in `run_doctor`. `_github_auth_header` and `_github_api_base` stay, because `_fetch_github_latest` uses them. Reword the `_doctor_check_aws_key_expiry` header comment that compares its 90 days to "GITHUB_PAT_EXPIRY's 30" so it names no removed check.
3. `lib/constants.sh`: drop `setup_claude_mcp` from the comment naming the readers of `AI_CONFIG_DIR`.
4. Tests: delete the 35 tests whose name names either function (15 in `tests/setup_env/workflows.bats`, 2 in `tests/setup_env/install_guards.bats`, 18 in `tests/setup_env/unit.bats`). Delete each remaining no-op stub of a deleted function, in `unit.bats`, `workflows.bats`, `install_guards.bats` and `tests/setup_env/plugin_node_paths.bats`. Where a surviving test uses one as more than a stub, give it a surviving function instead:
   - `workflows.bats` "run_setup_user calls install_bats on macOS, and aborts when it returns non-zero" uses `setup_claude_mcp` as the "a later step did not run" sentinel; it takes the next step `run_setup_user` calls after `install_bats`.
   - `unit.bats` has a `run_doctor` test whose `_doctor_check_github_mcp` stub emits the one `doctor_warn`; that warning moves to another stubbed check in the same test.
5. `powershell/setup_windows.ps1` `Set-ClaudeConfig`: stop linking `mcp.json.template` and delete the block that writes `mcp.json` from it; delete the two Pester tests for that block.
6. `manifests/dotfiles/ai-config.yaml`: delete the `mcp.json.template` link entry.
7. Docs: delete `CLAUDE.md`'s "GitHub MCP" section, its `~/.claude/mcp.json` symlink bullet, and the `GITHUB_PAT` mentions in its Windows section; delete `README.md`'s GitHub MCP section and its line-97 `GITHUB_PAT` pointer; delete the `GITHUB_PAT`/`GITHUB_PAT_EXPIRY` lines from `config/local.sh.example`.
8. `docs/superpowers/README.md`: delete the two Backlog rows above, and add one P2 test-gaps row: `tests/setup_env/unit.bats` "run_doctor summary includes warnings count" asserts the substring `*"1 warnings"*`, which also matches "11 warnings" (pre-existing; this change moves its warning, not its assertion).

Left as they are:

- `ai-config/.claude/mcp.json` and its symlink: the generic `.claude/*` loop in `setup_dotfile_symlinks` still links it, and ai-config owns the file (told 2026-10-24).
- `brew "gettext"` in `Brewfile`: `envsubst` was dotfiles' reason, but gettext is a common dependency; dropping it is a separate change.
- Dated records: `docs/adr/` (ADR-0042 cites `_doctor_check_github_mcp`), dated specs and plans, `docs/knowledge/retrospectives/`, `docs/claude-code-new-features/`, `CHANGELOG.md`.
- A machine's existing `GITHUB_PAT` in its git-ignored `config/local.sh`. It is not inert after this change: etch-config's step above still reads it and can write it into a tracked file. The PR body recommends, as operator steps: revoke the PAT at GitHub, delete `GITHUB_PAT`/`GITHUB_PAT_EXPIRY` from `config/local.sh` on every machine, and on the Windows box delete `~/.claude/mcp.json`, which `Set-ClaudeConfig` wrote as a regular file holding the token.

## Testing

The change removes behaviour and adds none; there is no RED test. Evidence:

- `git grep -e setup_claude_mcp -e _doctor_check_github_mcp -e mcp.json.template` hits only the dated records above, this spec and its plan.
- `make test` passes with a plan count of master's minus 35.
- `setup_env.sh -t doctor` output has no "GitHub MCP:" heading.
- CI `bash-coverage` stays at or above 91%, and the CI `powershell` job stays at or above its 90% floor (95.09% on master, run 40050513754, 65 tests). The bash figure is a real check: CI truncates it to an integer and it read 91% against the 91% gate, and removing about 130 well-covered lines lowers the ratio by an estimated 0.05 percentage points.

## Requirements

- **R1.** `[PR1]` `lib/workflows.sh` defines no `setup_claude_mcp` and `run_setup_user` does not call it.
- **R2.** `[PR1]` `lib/helpers.sh` defines no `_doctor_check_github_mcp` and `run_doctor` does not call it; `_github_auth_header` and `_github_api_base` are still defined.
- **R3.** `[PR1]` No file under `tests/` defines, stubs or names `setup_claude_mcp` or `_doctor_check_github_mcp`, and the `run_setup_user` abort-ordering test and the `run_doctor` warning test each still assert their original behaviour through a surviving function.
- **R4.** `[PR1]` `powershell/setup_windows.ps1` neither links `mcp.json.template` nor writes `mcp.json`, and `powershell/tests/setup_windows.Tests.ps1` has no test for either.
- **R5.** `[PR1]` `manifests/dotfiles/ai-config.yaml` has no `mcp.json.template` entry.
- **R6.** `[PR1]` `CLAUDE.md`, `README.md` and `config/local.sh.example` contain neither `GITHUB_PAT` nor a claim that dotfiles configures an MCP server, `lib/constants.sh` does not name `setup_claude_mcp`, and `lib/helpers.sh` does not mention `GITHUB_PAT_EXPIRY`.
- **R7.** `[PR1]` `docs/superpowers/README.md` no longer has the two Backlog rows this spec closes, and has a Backlog row naming `unit.bats` "run_doctor summary includes warnings count" and its `*"1 warnings"*` substring assertion.
- **V1.** `make test` on the branch passes with a plan count equal to master's minus 35.
- **V2.** `setup_env.sh -t doctor` on the branch prints no "GitHub MCP:" heading.
- **V3.** CI `bash-coverage` reads at least 91% and CI `powershell` coverage at least 90%.
- **V4.** Post-merge, the plan index carries a Done row; etch-config's session has been told about both `dev.yaml` MCP steps and their write-through (told 2026-10-24); and ai-config's session has been told that `core.md` claude-012, `docs/knowledge/ai-config-standards-core.md` § claude-012, `docs/knowledge/dotfiles-conventions.md` (its `setup_claude_mcp` and Windows `GITHUB_PAT` text) and the `web-research` skill's Exa fallback describe the removed mechanism. claude-012 is operator-approved text, so its edit is the operator's.
- **N1.** No change to ai-config, etch-config or any other repo.
- **N2.** No change to `setup_dotfile_symlinks` or to which `ai-config/.claude/` items it links.
- **N3.** No edit to dated records: `docs/adr/`, dated specs or plans other than this spec and its plan, `docs/knowledge/retrospectives/`, `docs/claude-code-new-features/`, `CHANGELOG.md`.
- **N4.** No change to `_github_auth_header`, `_github_api_base`, `_fetch_github_latest` or `Brewfile`.

## Multi-Lens Review

Reviewed at commit: `b6378d90` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth doing; deletion is the simplest path. Premise verified (no `exa`, empty `~/.claude.json` `mcpServers`, no `claude` wrapper or `--mcp-config` anywhere in dotfiles or the zsh startup files). The always-loaded `core.md` claude-012 ("Do not run `setup_user` with `GITHUB_PAT` set: `setup_claude_mcp` then overwrites tracked `mcp.json`") goes stale with this change and V4 notified only etch-config.
Assumption: that no fleet machine's Claude Code reads `~/.claude/mcp.json`. Checked by the orchestrator 2026-10-24: Claude Code 2.1.309 on `claude`, the Studio and the workstation all print `No MCP server named "exa"`, and the binary references `mcp.json` only as a project `.mcp.json` or `managed-mcp.json`.
Disposition: Addressed — V4 now also notifies ai-config, naming claude-012 and the other stale ai-config text.

### Ergonomics

Finding: ai-config text still describes the removed mechanism (`core.md` claude-012 and its knowledge entry, `docs/knowledge/dotfiles-conventions.md` lines 208/246/317); on Windows, `Set-ClaudeConfig` left `~/.claude/mcp.json` as a regular file holding the PAT, which the spec stops writing but never removes; leaving the live PAT should mean revoking it. The PAT expiry reminder is not relied on (`GITHUB_PAT_EXPIRY` is commented out in `config/local.sh`).
Assumption: that nothing on the Windows box reads `GITHUB_PAT` or `~/.claude/mcp.json`; not measured there.
Disposition: Addressed — V4 lists the ai-config text; the left-as-is section recommends revoking the PAT, deleting it from `config/local.sh`, and deleting the Windows plaintext `mcp.json`, as PR-body operator steps.

### Risk

Finding: (1) the spec missed etch-config `workstation/dev.yaml` as a `GITHUB_PAT` reader, and that step writes the PAT through the live symlink into tracked `ai-config/.claude/mcp.json` (latent: 0 token hits today), so "no longer read" was false; (2) `plugin_node_paths.bats:422` stub missing from step 4's file list; (3) the `run_doctor` warning test asserts `*"1 warnings"*`, which matches "11 warnings" (pre-existing); (4) CI bash coverage reads 91% against a 91% integer-truncated gate, so V3 is a real check. Test counts (15/2/18), doctor ordering tests, CLAUDE.md gates, Pester parameter filters and manifest consumers are clean.
Assumption: that a leftover `GITHUB_PAT` is inert once dotfiles stops reading it; false while etch-config's step can run.
Disposition: Addressed — Problem names both etch-config readers and the write-through; operator steps added; step 4 lists `plugin_node_paths.bats`; step 8 and R7 add a Backlog row for the weak assertion; Testing states the coverage margin. etch-config's session was told 2026-10-24.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Risk (round 2, scoped re-review at `c8a27f4c`)

Finding: no load-bearing issue; every new factual claim verified (etch-config readers and lines, write-through guard, ai-config `dotfiles-conventions.md` lines 208/246/317/321, the `plugin_node_paths.bats:422` stub, the coverage estimate). Minor: R7's row should name the test (`unit.bats:1055` is unanchored, `:2969` is anchored); `lib/helpers.sh:831` keeps a `GITHUB_PAT_EXPIRY` comparison no step removed.
Assumption: the etch-config exposure is latent on every machine. Checked by the orchestrator 2026-10-24 on `claude`, the Studio and the workstation: `ai-config/.claude/mcp.json` has empty `git status`, 0 token-shaped strings, and 0 in `git log -p --all`.
Disposition: Addressed — R7 and step 8 name the test; step 2 and R6 cover the `helpers.sh` comment (wording-level, no further round).
