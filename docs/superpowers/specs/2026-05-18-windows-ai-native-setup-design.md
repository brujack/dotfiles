# Windows AI-Native Dev Environment Setup

**Date:** 2026-05-18
**Status:** Approved

## Problem

`setup_windows.ps1` installs Claude Code and Cursor via Chocolatey but leaves `~/.claude/` and `~/.cursor/` empty on native Windows. Skills, settings, hooks, Cursor rules, and MCP config from ai-config are not replicated. WSL2 already gets the full Linux setup via `setup_env.sh` — the gap is native Windows.

## Goals

1. Clone/update ai-config on Windows during setup and update
2. Symlink Claude Code config (settings, skills, commands, standards) from ai-config into `~/.claude/`
3. Generate `~/.claude/mcp.json` from template using `$env:GITHUB_PAT`
4. Symlink Cursor config (rules, plugins, skills-cursor, User settings) from ai-config
5. Install Node.js and `firecrawl-cli` npm global (missing from current setup)
6. All new functions are idempotent and covered by Pester tests

## Non-Goals

- Hooks (`.claude/hooks/` bash scripts): not linked on native Windows; WSL2 path handles them. Documented gap.
- `settings.local.json`: machine-local, not in ai-config, not touched
- `projects/`: per-repo memories, not symlinked anywhere

## Design

### Symlink Strategy

Scripts run in an admin terminal, so `New-Item -ItemType SymbolicLink` works for both files and directories. Use symlinks for files and junctions (`-ItemType Junction`) for directories — junctions are slightly more robust for directory links on Windows and don't require the `SeCreateSymbolicLink` privilege separately from admin.

`New-SafeLink` helper handles both cases:

- If the link already exists and points to the correct target: skip (idempotent)
- If the link exists but points elsewhere: remove and recreate
- If a regular file/dir exists at the link path: remove and recreate (setup wins)
- Then create the symlink or junction

### New Functions

#### `New-SafeLink`

```
New-SafeLink -Target <string> -Link <string> [-Junction]
```

- `-Junction`: create a directory junction instead of a file symlink
- Checks `(Get-Item $Link -ErrorAction SilentlyContinue).Target -eq $Target`; skips if already correct
- Removes existing item with `Remove-Item -Force -Recurse`
- Creates with `New-Item -ItemType SymbolicLink` or `New-Item -ItemType Junction`
- Used by both `Set-ClaudeConfig` and `Set-CursorConfig`

#### `Install-AiConfig`

Clones ai-config if `~/git-repos/personal/ai-config` is absent; pulls with `--rebase --autostash` if present.

```powershell
git clone git@github.com:brujack/ai-config ~/git-repos/personal/ai-config
# or
git -C ~/git-repos/personal/ai-config pull --rebase --autostash
```

Called from both `Invoke-DotfilesSetup` and `Invoke-DotfilesUpdate`.

#### `Set-ClaudeConfig`

Creates `~/.claude/` if absent, then links:

| Source (ai-config/.claude/) | Destination (~/.claude/) | Type     |
| --------------------------- | ------------------------ | -------- |
| `settings.json`             | `settings.json`          | symlink  |
| `skills/`                   | `skills/`                | junction |
| `commands/`                 | `commands/`              | junction |
| `standards/`                | `standards/`             | junction |
| `CLAUDE.md`                 | `CLAUDE.md`              | symlink  |
| `mcp.json.template`         | `mcp.json.template`      | symlink  |

Then generates `~/.claude/mcp.json`:

- Reads `mcp.json.template`
- Replaces `${GITHUB_PAT}` with `$env:GITHUB_PAT`
- Writes to `~/.claude/mcp.json` (overwrites; not a symlink — same as macOS)
- If `$env:GITHUB_PAT` is unset: writes the template as-is and emits a warning

Called from `Invoke-DotfilesSetup` only (symlinks don't need re-applying on update; ai-config pull handles content changes).

#### `Set-CursorConfig`

Creates `~/.cursor/` if absent, then links ai-config cursor dirs:

| Source (ai-config/.cursor/) | Destination (~/.cursor/) | Type     |
| --------------------------- | ------------------------ | -------- |
| `plugins/`                  | `plugins/`               | junction |
| `rules/`                    | `rules/`                 | junction |
| `skills-cursor/`            | `skills-cursor/`         | junction |

Then links User settings into `$env:APPDATA\Cursor\User\`:

| Source (ai-config/.cursor/User/) | Destination                                 |
| -------------------------------- | ------------------------------------------- |
| `settings.json`                  | `$env:APPDATA\Cursor\User\settings.json`    |
| `keybindings.json`               | `$env:APPDATA\Cursor\User\keybindings.json` |
| `snippets/`                      | `$env:APPDATA\Cursor\User\snippets\`        |

Creates `$env:APPDATA\Cursor\User\` if absent (Cursor may not be installed yet when setup runs; create it anyway so it's ready).

Called from `Invoke-DotfilesSetup` only.

#### `Set-NpmGlobalPackages`

Installs or updates `firecrawl-cli` globally:

```powershell
npm install -g firecrawl-cli
```

Idempotent: `npm install -g` upgrades if already installed. Node.js must be installed first (via Chocolatey `nodejs`); guard with `Get-Command node`.

Called from both `Invoke-DotfilesSetup` and `Invoke-DotfilesUpdate`.

### Chocolatey Package Addition

Add `nodejs` to `$ChocoPackagesToBeInstalled`. Required for Claude Code runtime and npm globals. The existing `claude-code` choco package may pull it as a dependency, but explicit inclusion is clearer and ensures it's tracked.

### Orchestrator Changes

```powershell
function Invoke-DotfilesSetup {
  Set-WindowsOption
  Install-ChocolateyPackage      # now includes nodejs
  Enable-RequiredWindowsOptionalFeature
  Install-WSL
  Set-ExecutionPolicy Unrestricted -Scope CurrentUser
  New-DirectoryStructure
  Copy-GitConfig
  Install-AiConfig               # new
  Set-ClaudeConfig               # new
  Set-CursorConfig               # new
  Set-NpmGlobalPackages          # new
}

function Invoke-DotfilesUpdate {
  choco upgrade all -y
  Install-AiConfig               # new — pull latest ai-config
  Set-NpmGlobalPackages          # new — update firecrawl-cli
  Install-WindowsUpdate
  # (optional: update_powershell_modules.ps1 if present)
}
```

## Testing

Pester tests for each new function:

**`New-SafeLink`**

- Creates symlink when link does not exist
- Creates junction when `-Junction` flag passed
- Skips when link already points to correct target
- Replaces symlink when target has changed
- Removes regular file before creating symlink

**`Install-AiConfig`**

- Calls `git clone` when ai-config dir absent
- Calls `git pull` when ai-config dir present
- Returns error when clone fails
- Returns error when pull fails

**`Set-ClaudeConfig`**

- Creates `~/.claude/` when absent
- Calls `New-SafeLink` for each expected file (settings.json, CLAUDE.md, mcp.json.template)
- Calls `New-SafeLink -Junction` for each dir (skills, commands, standards)
- Writes mcp.json with GITHUB_PAT substituted
- Warns and writes unsubstituted template when GITHUB_PAT unset

**`Set-CursorConfig`**

- Creates `~/.cursor/` and `$env:APPDATA\Cursor\User\` when absent
- Calls `New-SafeLink -Junction` for cursor dirs (plugins, rules, skills-cursor)
- Calls `New-SafeLink` for User files (settings.json, keybindings.json)
- Calls `New-SafeLink -Junction` for snippets dir

**`Set-NpmGlobalPackages`**

- Calls `npm install -g firecrawl-cli`
- Skips and warns when `node` is not in PATH

**`Invoke-DotfilesSetup` updates**

- Calls `Install-AiConfig`
- Calls `Set-ClaudeConfig`
- Calls `Set-CursorConfig`
- Calls `Set-NpmGlobalPackages`

**`Invoke-DotfilesUpdate` updates**

- Calls `Install-AiConfig`
- Calls `Set-NpmGlobalPackages`

## Files Changed

| File                                       | Change                                                                |
| ------------------------------------------ | --------------------------------------------------------------------- |
| `powershell/setup_windows.ps1`             | Add `nodejs` to choco list; add 4 new functions; update orchestrators |
| `powershell/tests/setup_windows.Tests.ps1` | Pester tests for all new functions + orchestrator updates             |
| `powershell/Makefile`                      | Update coverage floor after new tests                                 |
| `CLAUDE.md`                                | Document Windows ai-config setup and hooks gap                        |

## Known Gap

`.claude/hooks/` contains bash scripts. These are not linked or executed on native Windows. The WSL2 environment (via `setup_env.sh`) handles hooks for that execution context. This is documented, not worked around.
