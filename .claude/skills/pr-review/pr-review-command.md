# /pr-review

Perform a full pre-push PR review before pushing this branch.

## Instructions for Claude

1. Read the pr-review SKILL.md (install location varies — check `~/.claude/skills/pr-review/SKILL.md` or the path configured in your Superpowers setup)
2. Follow the skill workflow exactly:
   - Detect scope (git diff, languages present)
   - Load only the relevant language reference files
   - Run all six review phases (Security, TDD, Logic, Quality, Docs, IaC)
   - Emit the structured PASS / HOLD report
3. Do not skip any phase even if the diff is small
4. If HOLD: list every CRITICAL finding with a specific suggested fix before stopping

## Flags (optional — user can specify in the prompt)

- `--base <branch>` — override the base branch (default: auto-detected main/master)
- `--skip-tests` — skip running the test suite (report missing coverage as WARNING not blocker)
- `--iac-only` — run only the IaC safety gate (Ansible + Terraform phases)
- `--security-only` — run only Phase 1 (Security)
