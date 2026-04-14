# Design: Secrets and Local-State Guardrails

**Date:** 2026-04-08
**Status:** Approved

## Summary

Add a lightweight secret scanning step to CI using `gitleaks` and document which paths hold local-only state that must not be committed. This prevents accidental credential commits without requiring a local pre-commit hook that developers must install.

## Motivation

The dotfiles repo manages paths like `~/.aws`, `~/.ssh`, `~/.tf_creds`, and Cursor/Claude config directories. It also symlinks items from `.claude/` into `~/.claude/`. An accidental paste of an API key or private key into any tracked file would be silently committed. A CI scan provides a catch-all safety net that is always present.

## Changes

### New file: `.gitleaks.toml`

Configuration for the `gitleaks` scanner. The repo uses repo-managed Cursor and Claude files (settings, keybindings) that may contain paths or tokens — these are excluded. Known-safe patterns are allowlisted to suppress false positives.

```toml
title = "dotfiles gitleaks config"

[extend]
useDefault = true

[[rules]]
id = "generic-api-key"
description = "Generic API Key"
regex = '''(?i)(api[_\-\s]?key|apikey|api[_\-\s]?token)\s*[=:]\s*['\"]?[a-zA-Z0-9_\-]{20,}['\"]?'''
tags = ["key", "API"]

[[allowlists]]
description = "Claude/Cursor settings and keybindings are not credentials"
paths = [
  '''.cursor/.*''',
  '''.claude/.*''',
]

[[allowlists]]
description = "Brewfile cask IDs and tap tokens are not secrets"
paths = [
  '''Brewfile.*''',
]
```

### Modified: `.github/workflows/ci.yml`

Add a `secret-scan` job that runs in parallel with `test`:

```yaml
secret-scan:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v5
      with:
        fetch-depth: 0

    - name: Install gitleaks
      run: |
        GITLEAKS_VER="8.21.2"
        wget -qO /tmp/gitleaks.tar.gz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz"
        tar -xzf /tmp/gitleaks.tar.gz -C /tmp
        sudo mv /tmp/gitleaks /usr/local/bin/gitleaks

    - name: Scan for secrets
      run: gitleaks detect --config .gitleaks.toml --source . --log-opts "HEAD~50..HEAD" --verbose
```

The `--log-opts "HEAD~50..HEAD"` limit avoids scanning the full history on every run (full history can be scanned locally when needed with `gitleaks detect --no-git`).

### Modified: `CLAUDE.md` (project)

Add a section documenting which paths are local-only and must not be committed:

```markdown
## Local-Only State

The following paths are machine-local and must never be committed:

- `~/.aws/` — AWS credentials
- `~/.tf_creds/` — Terraform credentials
- `~/.ssh/` — SSH private keys (config and teleport.cfg are tracked in repo)
- `~/.claude/projects/<path>/` — conversation history (memory/ subdirs are tracked)
- `~/.config/gcloud/` — GCloud auth tokens
```

## Constraints

- The secret scan must not block on false positives from Brewfile IDs or Cursor/Claude config files.
- Full history scan is not required in CI (incremental scan on recent commits is sufficient).
- `gitleaks` version is pinned to avoid unexpected behavior changes.
