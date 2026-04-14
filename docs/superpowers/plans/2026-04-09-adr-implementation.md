# ADR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `docs/adr/` directory with five seed ADRs capturing decisions already in effect, and update the CLAUDE.md and README.md to document the new structure.

**Architecture:** All files are plain markdown. No code changes. Three commits: (1) ADR files, (2) CLAUDE.md layout update, (3) README.md layout + stale text fixes. `~/.claude/CLAUDE.md` (`.claude/CLAUDE.md` in the repo) was already updated in a prior session — skip it.

**Tech Stack:** Markdown, git.

---

## File Structure

| Action | File                                                              | Purpose                                                              |
| ------ | ----------------------------------------------------------------- | -------------------------------------------------------------------- |
| Create | `docs/adr/README.md`                                              | ADR index table                                                      |
| Create | `docs/adr/0001-use-bats-for-shell-testing.md`                     | ADR: BATS testing framework                                          |
| Create | `docs/adr/0002-use-gitleaks-for-secret-scanning.md`               | ADR: gitleaks in CI                                                  |
| Create | `docs/adr/0003-profile-capability-model-for-machine-detection.md` | ADR: profile/capability model                                        |
| Create | `docs/adr/0004-lib-modular-structure-for-setup-env.md`            | ADR: lib/ split                                                      |
| Create | `docs/adr/0005-require-secrets-guarding-in-all-personal-repos.md` | ADR: cross-repo secrets policy                                       |
| Modify | `CLAUDE.md`                                                       | Add `docs/` subtree to Layout section                                |
| Modify | `README.md`                                                       | Add `docs/` subtree to Repository Layout + fix stale auto-merge text |

---

### Task 1: Create docs/adr/ directory with index and five seed ADRs

**Files:**

- Create: `docs/adr/README.md`
- Create: `docs/adr/0001-use-bats-for-shell-testing.md`
- Create: `docs/adr/0002-use-gitleaks-for-secret-scanning.md`
- Create: `docs/adr/0003-profile-capability-model-for-machine-detection.md`
- Create: `docs/adr/0004-lib-modular-structure-for-setup-env.md`
- Create: `docs/adr/0005-require-secrets-guarding-in-all-personal-repos.md`

No tests — these are documentation files.

- [ ] **Step 1: Create `docs/adr/README.md`**

```markdown
# Architectural Decision Records

Cross-cutting decisions that apply across personal repos. Repo-specific decisions live in that repo's own `docs/adr/`.

| ADR                                                            | Title                                          | Date       | Status   |
| -------------------------------------------------------------- | ---------------------------------------------- | ---------- | -------- |
| [0001](0001-use-bats-for-shell-testing.md)                     | Use BATS for shell testing                     | 2026-03-27 | Accepted |
| [0002](0002-use-gitleaks-for-secret-scanning.md)               | Use gitleaks for secret scanning               | 2026-04-08 | Accepted |
| [0003](0003-profile-capability-model-for-machine-detection.md) | Profile/capability model for machine detection | 2026-03-31 | Accepted |
| [0004](0004-lib-modular-structure-for-setup-env.md)            | Modular lib/ structure for setup_env.sh        | 2026-03-31 | Accepted |
| [0005](0005-require-secrets-guarding-in-all-personal-repos.md) | Require secrets guarding in all personal repos | 2026-04-09 | Accepted |
```

- [ ] **Step 2: Create `docs/adr/0001-use-bats-for-shell-testing.md`**

```markdown
# ADR-0001: Use BATS for Shell Testing

**Date:** 2026-03-27
**Status:** Accepted

## Context

`setup_env.sh` was untested. Changes risked silently breaking machine setup. A testing framework was needed that could test bash scripts natively without a heavy runtime or translation layer. Options considered: BATS, shunit2, custom test harness.

## Decision

Use BATS (Bash Automated Testing System) for all shell script tests. Tests live in `tests/`, organized by script. Mocking is done via PATH injection — mock executables in `tests/mocks/` are prepended to `$PATH` in test setup, intercepting calls to `brew`, `apt-get`, `curl`, etc. Mock behavior is controlled via `MOCK_*` environment variables.

## Consequences

- Tests run in a real bash environment — no translation layer, no surprises from shell-to-language conversion.
- Lightweight: single executable, no runtime dependencies beyond bash.
- PATH-injected mocks allow simulating external tools without network or system access.
- Limited assertion vocabulary compared to xUnit frameworks (`run` + `$status` + `$output`).
- Mock management requires discipline: `MOCK_*` env vars and mock executables must be kept in sync with what real tools actually output.

## Related

- [Spec: bats-testing](../superpowers/specs/2026-03-27-bats-testing-design.md)
```

- [ ] **Step 3: Create `docs/adr/0002-use-gitleaks-for-secret-scanning.md`**

```markdown
# ADR-0002: Use gitleaks for Secret Scanning in CI

**Date:** 2026-04-08
**Status:** Accepted

## Context

Dotfiles contain credential directory paths, SSH config, and cloud provider configuration. An accidental commit of an actual key or token could be pushed to a repo before being noticed. Manual review of diffs is unreliable for detecting secrets.

## Decision

Add a `secret-scan` CI job using gitleaks that scans the most recent 50 commits on every push and PR to master. A `.gitleaks.toml` allowlist config at the repo root suppresses false positives from legitimate patterns (e.g., example credential paths in documentation).

## Consequences

- Automatic detection of accidental credential commits before they land on master.
- Allowlist config makes false positive suppression explicit and reviewable in code review.
- Gitleaks version is pinned in the CI job — must be updated when bumping.
- The 50-commit scan window means very old history is not re-scanned on every push (intentional: avoids penalizing repos that pre-date the guardrail).

## Related

- [Spec: secrets-guardrails](../superpowers/specs/2026-04-08-secrets-guardrails-design.md)
- [ADR-0005: Require secrets guarding in all personal repos](0005-require-secrets-guarding-in-all-personal-repos.md)
```

- [ ] **Step 4: Create `docs/adr/0003-profile-capability-model-for-machine-detection.md`**

```markdown
# ADR-0003: Profile/Capability Model for Machine Detection

**Date:** 2026-03-31
**Status:** Accepted

## Context

`setup_env.sh` used raw hostname comparisons (`[[ "${HOSTNAME}" == "laptop" ]]`) scattered throughout the file. Adding a new machine required searching for and modifying many conditional blocks. Hostname-based logic was not unit-testable without mocking the hostname itself.

## Decision

Introduce a two-layer model:

1. **Profile** — `config/profiles.sh` maps hostnames to named profiles (`personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `wsl2_workstation`, `server`).
2. **Capabilities** — `detect_env()` in `lib/detect_env.sh` reads the profile and sets `HAS_*` boolean vars (`HAS_GUI`, `HAS_DEVTOOLS`, `HAS_AWS`, `HAS_K8S`, `HAS_DOCKER`, `HAS_RUST`, `HAS_SNAP`, `HAS_PRINTING`).

All capability-gated code checks `HAS_*` vars, never raw hostnames.

## Consequences

- Adding a new machine requires editing one line in `config/profiles.sh` — no logic changes.
- `HAS_*` vars are testable by setting them directly in BATS tests without mocking hostname.
- Profile names are human-readable and stable across hostname changes.
- Legacy hostname vars (`LAPTOP`, `STUDIO`, etc.) are preserved as readonly aliases in `detect_env.sh` for backwards compatibility.
- Profile and capability maps must be kept in sync when new capabilities are introduced.

## Related

- [Spec: dotfiles-modularization](../superpowers/specs/2026-03-31-dotfiles-modularization-design.md)
- [ADR-0004: Modular lib/ structure](0004-lib-modular-structure-for-setup-env.md)
```

- [ ] **Step 5: Create `docs/adr/0004-lib-modular-structure-for-setup-env.md`**

```markdown
# ADR-0004: Modular lib/ Structure for setup_env.sh

**Date:** 2026-03-31
**Status:** Accepted

## Context

`setup_env.sh` was a single file exceeding 2000 lines. Finding any function required grep. Tests were impossible because sourcing the entire file triggered side effects (installs, symlinks, etc.). All platforms, all tools, and all workflows were interleaved.

## Decision

Split `setup_env.sh` into a thin dispatcher that sources seven purpose-specific library files in dependency order:

| File                | Responsibility                                                             |
| ------------------- | -------------------------------------------------------------------------- |
| `lib/constants.sh`  | Version pins, download URLs, directory variables                           |
| `lib/helpers.sh`    | Logging (`log_info/warn/error`), `safe_link`, install guards, brew helpers |
| `lib/detect_env.sh` | OS/version detection + profile/capability resolution                       |
| `lib/macos.sh`      | macOS-specific install functions                                           |
| `lib/linux.sh`      | Linux-specific install functions                                           |
| `lib/developer.sh`  | Cross-platform dev tooling (Ruby, Python, Ansible, etc.)                   |
| `lib/workflows.sh`  | Top-level workflow functions dispatched by `setup_env.sh`                  |

`setup_env.sh` itself only parses args and dispatches to `run_*` functions in `lib/workflows.sh`.

## Consequences

- Each lib file has a single responsibility and can be sourced independently in BATS tests without triggering side effects from other files.
- macOS- and Linux-specific code is cleanly separated — no platform sprawl in shared files.
- New platform support can be added as a new `lib/<platform>.sh` file.
- `setup_env.sh` must source all lib files in dependency order at startup (`constants` → `helpers` → `detect_env` → platform libs → `workflows`).

## Related

- [Spec: dotfiles-modularization](../superpowers/specs/2026-03-31-dotfiles-modularization-design.md)
- [ADR-0003: Profile/capability model](0003-profile-capability-model-for-machine-detection.md)
```

- [ ] **Step 6: Create `docs/adr/0005-require-secrets-guarding-in-all-personal-repos.md`**

```markdown
# ADR-0005: Require Secrets Guarding in All Personal Repos

**Date:** 2026-04-09
**Status:** Accepted

## Context

After implementing gitleaks in dotfiles (ADR-0002), it became clear that every personal repo faces the same credential leak risk — SSH keys, API tokens, cloud credentials, and session tokens can appear in any repo's history. Without a cross-repo policy, each repo would need to independently discover and implement the guardrail pattern.

## Decision

All personal repos under `~/git-repos/personal/` must have three guardrails in place:

1. A `secret-scan` CI job using gitleaks (`.github/workflows/ci.yml`) scanning the most recent 50 commits.
2. A `.gitleaks.toml` allowlist config at the repo root to suppress false positives.
3. Credential file paths (`.aws/`, `.ssh/` private keys, `.tf_creds/`, `.azure_creds/`, `.gcloud_creds/`, `.tsh/`) listed in `.gitignore`.

This requirement is documented in `~/.claude/CLAUDE.md` so it applies in all Claude Code sessions across all personal repos.

## Consequences

- Consistent security posture across all personal repos — no repo is a weak link.
- New repos get guardrails as part of initial setup, not as a retrofit.
- Each new repo requires initial setup effort for the three guardrails.
- `.gitleaks.toml` must be maintained per-repo to suppress legitimate patterns that look like secrets.

## Related

- [ADR-0002: Use gitleaks for secret scanning](0002-use-gitleaks-for-secret-scanning.md)
- [Spec: secrets-guardrails](../superpowers/specs/2026-04-08-secrets-guardrails-design.md)
```

- [ ] **Step 7: Commit all ADR files**

```bash
git add docs/adr/
git commit -m "docs: add docs/adr/ with five seed ADRs

Captures five architectural decisions already in effect:
0001 BATS testing, 0002 gitleaks CI, 0003 profile/capability model,
0004 lib/ modular structure, 0005 cross-repo secrets guardrails.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Update CLAUDE.md Layout section

**Files:**

- Modify: `CLAUDE.md` (repo-level, at `dotfiles/CLAUDE.md`)

The Layout section's directory tree has no `docs/` entry. Add it after the `config/` block.

- [ ] **Step 1: Add `docs/` to the Layout tree in `CLAUDE.md`**

Find this block in the `## Layout` section:

```
├── config/
│   └── profiles.sh           # hostname → profile map; edit here to add a new machine
├── lib/
```

Replace with:

```
├── config/
│   └── profiles.sh           # hostname → profile map; edit here to add a new machine
├── docs/
│   ├── adr/                  # Architectural Decision Records (cross-cutting decisions)
│   │   ├── README.md         # ADR index table
│   │   └── NNNN-title.md     # Individual ADRs (0001, 0002, …)
│   └── superpowers/          # Design specs and implementation plans
│       ├── specs/            # Design documents (YYYY-MM-DD-*-design.md)
│       └── plans/            # Implementation plans (YYYY-MM-DD-*.md)
├── lib/
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add docs/ subtree to CLAUDE.md layout

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Update README.md Repository Layout and fix stale text

**Files:**

- Modify: `README.md`

Two changes needed:

1. Add `docs/` to the Repository Layout directory tree (currently missing entirely).
2. Fix stale Branch Workflow text: line currently says "Dependabot PRs are auto-merged when all three pass; feature PRs require manual merge." — CI now auto-merges **all** PRs when CI passes (changed when the `auto-merge` job was restored for all PRs).

- [ ] **Step 1: Add `docs/` entry to Repository Layout tree in `README.md`**

Find this block in the `## Repository Layout` section:

```
├── .github/
│   └── workflows/
│       └── ci.yml            # lint + test + lint-macos + secret-scan + auto-merge
├── kubernetes_stuff/         # Kubernetes install/init scripts
```

Replace with:

```
├── docs/
│   ├── adr/                  # Architectural Decision Records (cross-cutting decisions)
│   └── superpowers/          # Design specs and implementation plans
├── .github/
│   └── workflows/
│       └── ci.yml            # lint + test + lint-macos + secret-scan + auto-merge
├── kubernetes_stuff/         # Kubernetes install/init scripts
```

- [ ] **Step 2: Fix stale auto-merge text in Branch Workflow section**

Find:

```
All changes go on feature branches. GitHub Actions CI runs `make test`, `lint-macos`, and `secret-scan` on every push. Dependabot PRs are auto-merged when all three pass; feature PRs require manual merge.
```

Replace with:

```
All changes go on feature branches. GitHub Actions CI runs `make test`, `lint-macos`, and `secret-scan` on every push. All PRs are auto-merged when all three pass.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add docs/ to README layout, fix stale auto-merge text

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Update docs/superpowers/README.md plan index

**Files:**

- Modify: `docs/superpowers/README.md`

Add the ADR implementation plan to the master status index.

- [ ] **Step 1: Add row to the plan index**

In `docs/superpowers/README.md`, add this row to the table after the last `2026-04-08` entry and before the `check-versions` row:

```
| 2026-04-09 | [adr-implementation](plans/2026-04-09-adr-implementation.md) | [spec](specs/2026-04-09-adr-design.md) | Done |
```

Also update `check-versions` status from `In Progress` to `Done`.

The updated bottom of the table should look like:

```
| 2026-04-08 | [workflow-test-coverage](plans/2026-04-08-workflow-test-coverage.md) | [spec](specs/2026-04-08-workflow-test-coverage-design.md) | Pending |
| 2026-04-08 | [check-versions](plans/2026-04-08-check-versions.md) | [spec](specs/2026-04-08-check-versions-design.md) | Done |
| 2026-04-09 | [adr-implementation](plans/2026-04-09-adr-implementation.md) | [spec](specs/2026-04-09-adr-design.md) | Done |
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/README.md docs/superpowers/plans/2026-04-09-adr-implementation.md
git commit -m "docs: add ADR implementation plan to superpowers index

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
