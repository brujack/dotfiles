---
name: pr-review
description: >
  Perform a thorough pre-push / pre-PR code review covering correctness, security,
  test coverage, IaC safety, and code quality across all languages in the repo.
  Use this skill whenever the user says "review my PR", "review before push",
  "pre-push review", "check my changes", "review this branch", "/pr-review",
  or asks Claude to gate a git push. Also trigger when Superpowers TDD discipline
  checks are appropriate (verifying tests exist and pass before merge). Covers
  Rust, Python, Bash, PowerShell, Ansible, and Terraform. This skill augments
  Superpowers by acting as a final integration gate — apply it even when individual
  language skills have already been used during development.
---

# PR Review Skill

A structured pre-push / pre-PR review gate. Produces a **PASS / HOLD** verdict
with itemised findings before any code leaves the local branch.

---

## Quick Start

When triggered, run this workflow in order:

1. **Detect scope** — gather the diff, identify languages/tools present
2. **Load language references** — read only the relevant reference files below
3. **Run all review phases** — work through the checklist
4. **Emit the report** — structured verdict + findings

---

## Step 1 — Detect Scope

```bash
# Identify the base branch (try common names)
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' \
       || echo "main")

# Full diff stat + diff
git diff "$BASE"...HEAD --stat
git diff "$BASE"...HEAD
```

Also run:
```bash
git log "$BASE"...HEAD --oneline       # commits in this PR
git status                              # any unstaged changes to flag
```

Identify which of these are present in the diff:
- [ ] Rust (`.rs`)
- [ ] Python (`.py`)
- [ ] Bash / Shell (`.sh`, shebangs)
- [ ] PowerShell (`.ps1`, `.psm1`)
- [ ] Ansible (`.yml`/`.yaml` under `roles/`, `playbooks/`, `tasks/`, or containing `hosts:` / `- name:`)
- [ ] Terraform (`.tf`, `.tfvars`)
- [ ] Other (note and apply general review)

---

## Step 2 — Load Language References

Read **only** the reference files relevant to what you found in Step 1.
Do not load all of them — keep context lean.

| Language / Tool | Reference file |
|---|---|
| Rust | `references/rust.md` |
| Python | `references/python.md` |
| Bash / Shell | `references/bash.md` |
| PowerShell | `references/powershell.md` |
| Ansible | `references/ansible.md` |
| Terraform | `references/terraform.md` |

---

## Step 3 — Review Phases

Work through **all** phases regardless of language. Language-specific checks
come from the reference files; the phases below are universal.

### Phase 1 — Security 🔒

Critical — any finding here is an automatic HOLD.

- [ ] No secrets, tokens, passwords, or API keys hardcoded or in diffs
- [ ] No credential files (`.env`, `*.pem`, `*.key`, `id_rsa`) added or modified
- [ ] Input validation present for all external inputs
- [ ] No shell injection risks (`subprocess`, `os.system`, unquoted variables)
- [ ] Permissions not overly broad (files, IAM policies, sudo usage)
- [ ] Dependencies introduced? Check for known-bad versions or typosquatting
- Language/tool-specific security checks → see reference file

### Phase 2 — TDD / Test Coverage 🧪

Superpowers integration point — verify TDD discipline was maintained.

```bash
# Check for test files in the diff
git diff "$BASE"...HEAD --name-only | grep -E '(test_|_test\.|spec\.|\.test\.)'

# Run the test suite
# Rust:
cargo test 2>&1 | tail -20
# Python:
python -m pytest --tb=short 2>&1 | tail -30
# Ansible:
# (molecule test if configured, else ansible-lint)
# Terraform:
# (terratest or terraform validate + plan)
```

- [ ] Every new function/module has a corresponding test
- [ ] No existing tests were deleted without justification
- [ ] All tests pass on the current branch
- [ ] Edge cases and error paths are tested, not just happy paths
- [ ] Test names are descriptive (documents intent, not implementation)

### Phase 3 — Logic & Correctness 🧠

- [ ] Algorithm correctness — trace through key logic paths mentally
- [ ] Off-by-one errors, boundary conditions
- [ ] Null / None / empty handling
- [ ] Error handling is present and meaningful (not bare `except:` or `unwrap()`)
- [ ] No dead code or unreachable branches introduced
- [ ] Concurrency issues (race conditions, shared mutable state) if applicable
- [ ] Return values checked where relevant

### Phase 4 — Code Quality 📐

- [ ] Functions are single-responsibility and appropriately sized
- [ ] No unnecessary complexity introduced
- [ ] Variable/function names are clear and consistent with codebase conventions
- [ ] No copy-paste duplication (DRY principle)
- [ ] Comments explain *why*, not *what*
- [ ] No debug print statements, commented-out code, or TODO bombs left in
- Language-specific style checks → see reference file

### Phase 5 — Documentation & Config 📄

- [ ] README updated if behaviour or setup steps changed
- [ ] CHANGELOG or commit message reflects the change accurately
- [ ] New environment variables documented (`.env.example`, README, or skill notes)
- [ ] Any new dependencies added to `requirements.txt`, `Cargo.toml`, etc.
- [ ] API or interface changes documented

### Phase 6 — IaC Safety Gate ☁️

Only run if Ansible or Terraform are in scope. This phase is treated with
the same severity as Security — findings here are automatic HOLDs.

See `references/ansible.md` and `references/terraform.md` for full checklists.

Summary of critical checks:
- No `terraform plan` output showing unexpected destroys on production resources
- No hardcoded region/account IDs that should be variables
- Ansible plays don't run as root unless explicitly required and justified
- No `ignore_errors: true` masking real failures in Ansible

---

## Step 4 — Emit the Report

Output the report in this exact format:

```
══════════════════════════════════════════════
  PR REVIEW REPORT
  Branch:   <branch-name>
  Base:     <base-branch>
  Commits:  <N>
  Files:    <N changed>
  Languages: <detected list>
══════════════════════════════════════════════

VERDICT: PASS ✅  |  HOLD 🛑

─── FINDINGS ──────────────────────────────────

[CRITICAL 🔴]  <phase>  <file:line if known>
  → <description>
  → Suggested fix: <specific action>

[WARNING  🟡]  <phase>  <file:line if known>
  → <description>
  → Suggested fix: <specific action>

[INFO     🔵]  <phase>
  → <observation — not blocking>

─── TEST SUMMARY ───────────────────────────────
  Tests run:    <N>
  Passed:       <N>
  Failed:       <N>
  Missing coverage: <list areas if any>

─── SIGN-OFF ───────────────────────────────────
  PASS  → Safe to push. Run: git push origin <branch>
  HOLD  → Fix CRITICAL items above before pushing.
══════════════════════════════════════════════
```

**PASS** = zero CRITICAL findings.
**HOLD** = one or more CRITICAL findings (security, test failures, IaC destroys).
WARNING and INFO items are advisory — do not block but should be addressed.

---

## Slash Command Integration

To use this as a Claude Code slash command, create:

**`.claude/commands/pr-review.md`**
```markdown
Run a full pre-push PR review using the pr-review skill.

Steps:
1. Read /path/to/skills/pr-review/SKILL.md
2. Follow the workflow exactly
3. Emit the structured report with PASS/HOLD verdict
```

---

## Superpowers Integration Notes

This skill sits **above** individual Superpowers language skills in the review
hierarchy. The relationship is:

```
Development phase   →  Superpowers language skill (Rust/Python/Bash/etc.)
                        - TDD red/green/refactor
                        - Style enforcement
                        - Per-file quality

PR gate phase       →  This skill (pr-review)
                        - Cross-cutting security sweep
                        - Verifies TDD was actually followed
                        - IaC safety (Ansible + Terraform)
                        - Integration-level logic review
                        - Final sign-off before push
```

If a Superpowers language skill was used during development, the PR review
still runs — it verifies the outcome, not just the process.
