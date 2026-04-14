# pr-review — Installation Guide

A pre-push PR review gate for Claude Code. Covers Rust, Python, Bash,
PowerShell, Ansible, and Terraform. Integrates with Superpowers.

---

## Install the Skill

### Option A — Claude Code marketplace

If this skill is published, install via:

```bash
claude skill install pr-review
```

### Option B — Manual install (from this directory)

```bash
# Copy skill to your Claude skills directory
cp -r pr-review/ ~/.claude/skills/pr-review/
```

---

## Install the Slash Command

```bash
# Create the commands directory if it doesn't exist
mkdir -p ~/.claude/commands

# Copy the command file
cp pr-review-command.md ~/.claude/commands/pr-review.md
```

---

## Update SKILL.md with your install path

Edit `~/.claude/skills/pr-review/SKILL.md` and verify the slash command
section points to the correct skill install path.

---

## Usage

In any Claude Code session, on any branch:

```
/pr-review
```

Or naturally:

```
Review my PR before I push
Check my changes on this branch
Run a pre-push review
```

### With flags:

```
/pr-review --base develop
/pr-review --security-only
/pr-review --iac-only
```

---

## Superpowers Integration

This skill is designed to work **alongside** your existing Superpowers
language skills, not replace them.

Recommended workflow:

1. **During development** — use Superpowers language skills (Rust, Python, etc.)
   for TDD, style enforcement, and per-file quality
2. **Before push** — run `/pr-review` as a final integration gate

The pr-review skill verifies that Superpowers TDD discipline was actually
followed across the whole diff, adds cross-cutting security and IaC checks,
and produces a formal PASS/HOLD sign-off.

---

## Linter / Tool Dependencies (optional but recommended)

These tools enhance the review when installed:

| Tool               | Install                           | Used by            |
| ------------------ | --------------------------------- | ------------------ |
| `cargo clippy`     | Rust toolchain                    | Rust phase         |
| `cargo audit`      | `cargo install cargo-audit`       | Rust security      |
| `ruff`             | `pip install ruff`                | Python             |
| `mypy`             | `pip install mypy`                | Python             |
| `bandit`           | `pip install bandit`              | Python security    |
| `shellcheck`       | `brew install shellcheck`         | Bash               |
| `bats`             | `brew install bats-core`          | Bash tests         |
| `PSScriptAnalyzer` | `Install-Module PSScriptAnalyzer` | PowerShell         |
| `ansible-lint`     | `pip install ansible-lint`        | Ansible            |
| `yamllint`         | `pip install yamllint`            | Ansible            |
| `molecule`         | `pip install molecule`            | Ansible tests      |
| `tflint`           | `brew install tflint`             | Terraform          |
| `tfsec`            | `brew install tfsec`              | Terraform security |
| `checkov`          | `pip install checkov`             | Terraform security |

The skill degrades gracefully if tools are not installed — it will note
which checks were skipped.
