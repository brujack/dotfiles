# Stop managing MCP configuration

- **Date:** 2026-10-24
- **Backlog rows closed:** "`setup_claude_mcp`'s template generation is unreachable on every machine" and "`doctor` reports `mcp.json (generated)` for a file it only tested for existence" (both P2 bugs and security).

## Problem

dotfiles generates, links and checks `~/.claude/mcp.json`, and Claude Code does not read that file. Measured on `claude`, 2026-10-24:

- `~/.claude/mcp.json` is a symlink to `ai-config/.claude/mcp.json`, which declares one server, `exa`.
- `claude mcp get exa` prints `No MCP server named "exa"`; `claude mcp list` lists only the claude.ai connectors and the plugin servers (`context-mode`, `context7`, `firecrawl`).
- `~/.claude.json`, where Claude Code keeps user-scope MCP servers, has an empty `mcpServers`; neither `~/.claude/settings.json` nor `settings.local.json` declares any.

So the mechanism is dead twice over. `setup_claude_mcp` never writes the file, because `setup_dotfile_symlinks` links it first and the function's own symlink guard returns 0; and a generated file would be ignored anyway. `_doctor_check_github_mcp` prints `[PASS] ~/.claude/mcp.json (generated)` for a file that was neither generated nor read, and `CLAUDE.md`'s "GitHub MCP" section states a GitHub MCP server is configured when none is.

`GITHUB_PAT` exists only for this. In dotfiles its readers are `setup_claude_mcp`, `_doctor_check_github_mcp` (file check, live `/user` call, `GITHUB_PAT_EXPIRY` check) and `powershell/setup_windows.ps1`'s `Set-ClaudeConfig`; the only other reader in the fleet is etch-config's `etch-cli-test/dev.yaml` "Claude MCP setup" step. The operator decided on 2026-10-24 that dotfiles stops managing MCP configuration.

## Design

Delete the generation, the check and the documentation of both. Nothing replaces them.

1. `lib/workflows.sh`: delete `setup_claude_mcp` and its call `setup_claude_mcp || return 1` in `run_setup_user`, and update the comment that cites that call as a style precedent.
2. `lib/helpers.sh`: delete `_doctor_check_github_mcp` and its call in `run_doctor`. `_github_auth_header` and `_github_api_base` stay, because `_fetch_github_latest` uses them.
3. `lib/constants.sh`: drop `setup_claude_mcp` from the comment naming the readers of `AI_CONFIG_DIR`.
4. Tests: delete the 35 tests whose name names either function (15 in `tests/setup_env/workflows.bats`, 2 in `tests/setup_env/install_guards.bats`, 18 in `tests/setup_env/unit.bats`). Delete each remaining no-op stub of a deleted function. Where a surviving test uses one as more than a stub, give it a surviving function instead:
   - `workflows.bats` "run_setup_user calls install_bats on macOS, and aborts when it returns non-zero" uses `setup_claude_mcp` as the "a later step did not run" sentinel; it takes the next step `run_setup_user` calls after `install_bats`.
   - `unit.bats` has a `run_doctor` test whose `_doctor_check_github_mcp` stub emits the one `doctor_warn`; that warning moves to another stubbed check in the same test.
5. `powershell/setup_windows.ps1` `Set-ClaudeConfig`: stop linking `mcp.json.template` and delete the block that writes `mcp.json` from it; delete the two Pester tests for that block.
6. `manifests/dotfiles/ai-config.yaml`: delete the `mcp.json.template` link entry.
7. Docs: delete `CLAUDE.md`'s "GitHub MCP" section, its `~/.claude/mcp.json` symlink bullet, and the `GITHUB_PAT` mentions in its Windows section; delete `README.md`'s GitHub MCP section and its line-97 `GITHUB_PAT` pointer; delete the `GITHUB_PAT`/`GITHUB_PAT_EXPIRY` lines from `config/local.sh.example`.
8. `docs/superpowers/README.md`: delete the two Backlog rows above.

Left as they are:

- `ai-config/.claude/mcp.json` and its symlink: the generic `.claude/*` loop in `setup_dotfile_symlinks` still links it, and ai-config owns the file (told 2026-10-24).
- `brew "gettext"` in `Brewfile`: `envsubst` was dotfiles' reason, but gettext is a common dependency; dropping it is a separate change.
- Dated records: `docs/adr/` (ADR-0042 cites `_doctor_check_github_mcp`), dated specs and plans, `docs/knowledge/retrospectives/`, `docs/claude-code-new-features/`, `CHANGELOG.md`.
- A machine's existing `GITHUB_PAT` in its git-ignored `config/local.sh`: no longer read; removing it is the operator's choice.

## Testing

The change removes behaviour and adds none; there is no RED test. Evidence:

- `git grep -e setup_claude_mcp -e _doctor_check_github_mcp -e mcp.json.template` hits only the dated records above, this spec and its plan.
- `make test` passes with a plan count of master's minus 35.
- `setup_env.sh -t doctor` output has no "GitHub MCP:" heading.
- CI `bash-coverage` stays at or above 91%, and the CI `powershell` job stays at or above its 90% floor (95.09% on master, run 40050513754, 65 tests).

## Requirements

- **R1.** `[PR1]` `lib/workflows.sh` defines no `setup_claude_mcp` and `run_setup_user` does not call it.
- **R2.** `[PR1]` `lib/helpers.sh` defines no `_doctor_check_github_mcp` and `run_doctor` does not call it; `_github_auth_header` and `_github_api_base` are still defined.
- **R3.** `[PR1]` No file under `tests/` defines, stubs or names `setup_claude_mcp` or `_doctor_check_github_mcp`, and the `run_setup_user` abort-ordering test and the `run_doctor` warning test each still assert their original behaviour through a surviving function.
- **R4.** `[PR1]` `powershell/setup_windows.ps1` neither links `mcp.json.template` nor writes `mcp.json`, and `powershell/tests/setup_windows.Tests.ps1` has no test for either.
- **R5.** `[PR1]` `manifests/dotfiles/ai-config.yaml` has no `mcp.json.template` entry.
- **R6.** `[PR1]` `CLAUDE.md`, `README.md` and `config/local.sh.example` contain neither `GITHUB_PAT` nor a claim that dotfiles configures an MCP server, and `lib/constants.sh` does not name `setup_claude_mcp`.
- **R7.** `[PR1]` `docs/superpowers/README.md` no longer has the two Backlog rows this spec closes.
- **V1.** `make test` on the branch passes with a plan count equal to master's minus 35.
- **V2.** `setup_env.sh -t doctor` on the branch prints no "GitHub MCP:" heading.
- **V3.** CI `bash-coverage` reads at least 91% and CI `powershell` coverage at least 90%.
- **V4.** Post-merge, the plan index carries a Done row and etch-config's session has been told its `dev.yaml` MCP step has no dotfiles counterpart.
- **N1.** No change to ai-config, etch-config or any other repo.
- **N2.** No change to `setup_dotfile_symlinks` or to which `ai-config/.claude/` items it links.
- **N3.** No edit to dated records: `docs/adr/`, dated specs or plans other than this spec and its plan, `docs/knowledge/retrospectives/`, `docs/claude-code-new-features/`, `CHANGELOG.md`.
- **N4.** No change to `_github_auth_header`, `_github_api_base`, `_fetch_github_latest` or `Brewfile`.
