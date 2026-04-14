# GitHub MCP Server — Design Spec

**Date:** 2026-04-14
**Status:** Accepted

## Context

Claude Code supports MCP (Model Context Protocol) servers that extend its
capabilities. The GitHub MCP server (`https://api.githubcopilot.com/mcp`) provides
native GitHub operations — PR review, issue management, repo browsing, diff access
— without copy-pasting content into chat.

The dotfiles repo manages Claude Code config via symlinks into `~/.claude/`. The
current `mcp.json` is symlinked from `.claude/mcp.json` and contains only
`sequential-thinking`. The GitHub MCP requires a Personal Access Token (PAT) that
must not be committed to git.

## Decision

Use a **template-based generation** approach:

- `.claude/mcp.json.template` (tracked) — defines all MCP servers with
  `${GITHUB_PAT}` as a literal placeholder in the GitHub MCP header
- `~/.claude/mcp.json` (generated, not symlinked) — produced by `setup_claude_mcp`
  via `envsubst`; token lives here at runtime, never in git
- `setup_user` workflow gains a `setup_claude_mcp` step (non-blocking if PAT missing)
- `doctor` workflow gains a `check_github_mcp` step (token live, expiry warning)

This avoids relying on Claude Code env var interpolation in HTTP headers (not
confirmed supported) and keeps the token out of all tracked files.

## Components

### `.claude/mcp.json.template` (new, tracked)

Replaces `.claude/mcp.json`. The symlink loop will create
`~/.claude/mcp.json.template` (Claude Code ignores files with non-standard
extensions). The generated `~/.claude/mcp.json` is a separate plain file.

```json
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_PAT}"
      }
    }
  }
}
```

### `setup_claude_mcp` (new function in `lib/workflows.sh`)

Called from `run_setup_user`. Sources `config/local.sh`, substitutes `GITHUB_PAT`
into the template, writes `~/.claude/mcp.json`.

```
setup_claude_mcp
  ├── source config/local.sh
  ├── if GITHUB_PAT unset or empty:
  │     log_warn "GITHUB_PAT not set — GitHub MCP not configured"
  │     log_warn "Add GITHUB_PAT to config/local.sh and re-run setup_user"
  │     return 0   ← non-blocking
  └── envsubst < .claude/mcp.json.template > ~/.claude/mcp.json
        log_info "GitHub MCP configured"
```

Error handling:

- Missing PAT → `log_warn`, return 0 (offline machines / fresh clones don't break)
- `envsubst` fails → `log_error`, return 1 (propagate — unexpected)
- Generated file with literal `${GITHUB_PAT}` (empty PAT) → caught by doctor

### `check_github_mcp` (new doctor check in `lib/workflows.sh`)

Added to `run_doctor`. Checks in order:

| Check                                                                    | Result                                                                                                  |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `~/.claude/mcp.json` exists                                              | FAIL if missing — "Run: setup_env.sh -t setup_user"                                                     |
| `GITHUB_PAT` non-empty                                                   | FAIL if unset — link to GitHub token settings                                                           |
| `curl --max-time 5 --silent --fail` to `api.github.com/user` returns 200 | FAIL if curl exits 22 (HTTP 4xx/5xx — bad/revoked token); WARN if exits 28 (timeout) or 6 (DNS failure) |
| `GITHUB_PAT_EXPIRY` within 30 days                                       | WARN with expiry date and rotation link                                                                 |
| `GITHUB_PAT_EXPIRY` not set                                              | INFO — "Set GITHUB_PAT_EXPIRY in config/local.sh to enable expiry checks"                               |

Network unreachable (curl exit 6 or 28) is WARN not FAIL — you may be offline.
HTTP auth failure (curl exit 22) is always FAIL — the token is invalid or revoked.

### `config/local.sh.example` additions

```bash
# GitHub PAT for Claude Code GitHub MCP server
# Create at: https://github.com/settings/tokens?type=beta (fine-grained)
# Permissions: contents:read, issues:read+write, pull-requests:read+write, metadata:read
# Scope: all repos (or specific repos if preferred)
export GITHUB_PAT=""
export GITHUB_PAT_EXPIRY=""  # ISO date e.g. 2027-04-14 — doctor warns 30 days before expiry
```

## PAT Best Practices

- **Fine-grained PAT** — not classic. Auditable, scoped, revocable per repo.
- **Minimum permissions**: `metadata:read` (required by GitHub), `contents:read`,
  `issues:read+write`, `pull-requests:read+write`
- **Expiry**: set maximum 1-year expiry. Store the date in `GITHUB_PAT_EXPIRY` so
  doctor can warn before it expires.
- **No org-level admin permissions** — do not grant org administration, repo admin,
  member management, etc.
- **Do not use for direct pushes to main/master** — normal PR workflow enforced by
  CLAUDE.md rules still applies.
- **Rate limiting**: 5,000 API requests/hour for authenticated tokens — not a
  concern for interactive Claude Code use.

## Documentation Changes

### `README.md`

New "Claude Code Integration" section with a "GitHub MCP" subsection:

- How to create the fine-grained PAT (link to GitHub settings)
- Required permissions
- Add to `config/local.sh`
- Run `setup_env.sh -t setup_user`
- Verify with `setup_env.sh -t doctor`

### `CLAUDE.md` (project — dotfiles repo)

- Symlink section: note that `mcp.json` is generated from `mcp.json.template` and
  is not a symlink target
- Mock vars table: add `MOCK_CURL_STDOUT` (already exists) usage note for
  `check_github_mcp` tests; no new mock vars needed beyond existing `MOCK_CURL_EXIT`

### `~/.claude/CLAUDE.md` (global — enforces across all repos)

New `## GitHub MCP` section:

```markdown
## GitHub MCP

The GitHub MCP server is configured globally (user scope) via `~/.claude/mcp.json`.
It provides native GitHub operations — PR review, issue management, repo browsing,
diff access — across all projects without copy-pasting into chat.

Requires `GITHUB_PAT` to be set in `~/git-repos/personal/dotfiles/config/local.sh`.
If it isn't set, run `setup_env.sh -t setup_user` after adding the token.
Verify with `setup_env.sh -t doctor`.

Use it for:

- Fetching PR diffs and changed files
- Reading and creating issues
- Posting structured review comments
- Browsing repo contents

Do not use it to push directly to main/master — normal PR workflow still applies.
```

## Testing

New BATS tests in `tests/setup_env/install_functions.bats` (or a new
`tests/setup_env/github_mcp.bats`):

**`setup_claude_mcp` tests:**

- PAT set → file generated, no literal `${GITHUB_PAT}` in output
- PAT unset → logs warning, returns 0, no file written
- `envsubst` fails → returns 1

**`check_github_mcp` tests:**

- Generated file missing → FAIL
- PAT unset → FAIL
- `MOCK_CURL_EXIT=1` (simulates 401/error) → FAIL
- `MOCK_CURL_EXIT=0` but network timeout path → WARN (use `MOCK_CURL_EXIT=28` for timeout)
- `GITHUB_PAT_EXPIRY` within 30 days → WARN
- `GITHUB_PAT_EXPIRY` not set → INFO
- All checks pass → OK

## Migration

The existing `.claude/mcp.json` symlink must be removed and replaced:

1. Delete `.claude/mcp.json` from the repo (git rm)
2. Create `.claude/mcp.json.template` with the new content
3. `setup_user` will now generate `~/.claude/mcp.json` instead of symlinking it
4. Any machine that runs `setup_user` after pulling gets the generated file

Machines that don't re-run `setup_user` will keep the old symlink pointing at
the now-deleted `.claude/mcp.json` — doctor will catch this (file missing check).

## Implementation Scope

1. Git-remove `.claude/mcp.json`, create `.claude/mcp.json.template`
2. Add `setup_claude_mcp` to `lib/workflows.sh`; call from `run_setup_user`
3. Add `check_github_mcp` to `lib/workflows.sh`; call from `run_doctor`
4. Update `config/local.sh.example` with PAT vars
5. Add BATS tests
6. Update `README.md`
7. Update `CLAUDE.md` (project)
8. Update `~/.claude/CLAUDE.md` (global)
