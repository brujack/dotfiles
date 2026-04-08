# Secrets and Local-State Guardrails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `gitleaks` secret-scanning step to CI and document which paths are local-only machine state that must never be committed.

**Architecture:** Create `.gitleaks.toml` with allowlists for known-safe patterns. Add a `secret-scan` job to `.github/workflows/ci.yml` that runs `gitleaks detect` on recent commits. Add a local-only state section to `CLAUDE.md`.

**Tech Stack:** Bash, YAML (GitHub Actions), gitleaks v8

---

## File Map

| Action | File |
|---|---|
| Create | `.gitleaks.toml` |
| Modify | `.github/workflows/ci.yml` |
| Modify | `CLAUDE.md` |

---

### Task 1: Create `.gitleaks.toml`

**Files:**
- Create: `.gitleaks.toml`

- [ ] **Step 1: Create `.gitleaks.toml`**

```toml
title = "dotfiles gitleaks config"

[extend]
useDefault = true

[[allowlists]]
description = "Cursor and Claude settings/keybindings are not credentials"
paths = [
  '''.cursor/.*''',
  '''.claude/.*''',
]

[[allowlists]]
description = "Brewfile tap/cask/formula identifiers are not secrets"
paths = [
  '''Brewfile.*''',
]

[[allowlists]]
description = "ubuntu package list files contain no secrets"
paths = [
  '''ubuntu_.*_packages\.txt''',
]
```

- [ ] **Step 2: Test the config locally (requires gitleaks installed)**

If `gitleaks` is available locally (`brew install gitleaks` if not):

```bash
gitleaks detect --config .gitleaks.toml --source . --log-opts "HEAD~10..HEAD" --verbose
```

Expected: `No leaks found` or only allowlisted findings. If unexpected findings appear, add them to the allowlist or fix the actual secret.

If `gitleaks` is not installed locally, skip this step — CI will catch issues.

- [ ] **Step 3: Commit**

```bash
git add .gitleaks.toml
git commit -m "ci: add gitleaks configuration for secret scanning

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add `secret-scan` job to CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Read current CI file to verify structure**

Read `.github/workflows/ci.yml` to confirm the current jobs and their structure before editing.

- [ ] **Step 2: Add `secret-scan` job**

Add the following job to `.github/workflows/ci.yml` at the same indentation level as the `test` job (after the closing of the `test` job):

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
          tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
          sudo mv /tmp/gitleaks /usr/local/bin/gitleaks

      - name: Scan for secrets
        run: |
          gitleaks detect \
            --config .gitleaks.toml \
            --source . \
            --log-opts "HEAD~50..HEAD" \
            --verbose
```

The `secret-scan` job runs in parallel with `test` and does not block `auto-merge` (it is not listed in `auto-merge`'s `needs`). This is intentional: secret scanning is advisory until confidence in the allowlist is established.

- [ ] **Step 3: Verify the CI YAML is valid**

```bash
# Check YAML syntax (requires python or yq)
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML valid"
```

Or if `yq` is installed:

```bash
yq eval . .github/workflows/ci.yml > /dev/null && echo "YAML valid"
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add gitleaks secret-scan job to CI workflow

Scans the last 50 commits on each push/PR. Runs in parallel with tests,
advisory only (not blocking auto-merge).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Document local-only state in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add local-only state section to `CLAUDE.md`**

Add a new section after the "Key Conventions" section in `CLAUDE.md`:

```markdown
## Local-Only State

The following paths are machine-local and must **never** be committed to this repo:

- `~/.aws/` — AWS credentials and config
- `~/.tf_creds/` — Terraform cloud credentials
- `~/.ssh/` private keys — only `config` and `teleport.cfg` are tracked in `.ssh/` in the repo
- `~/.azure_creds/` — Azure credentials
- `~/.gcloud_creds/` — GCloud credentials
- `~/.tsh/` — Teleport session tokens
- `~/.claude/projects/<path>/` conversation history jsonl files — only `memory/` subdirs are tracked

The `secret-scan` CI job (`gitleaks`) scans recent commits for credential patterns. If it fires on a legitimate file, add an allowlist entry to `.gitleaks.toml`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add local-only state section to CLAUDE.md

Documents which paths must never be committed and how to extend
the gitleaks allowlist.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
