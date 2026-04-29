## Repository Structure

Every git repository must have a `README.md` at the top level.

Every git repository must have secrets guarding in place:

- A `gitleaks` secret scan in CI (`.github/workflows/ci.yml`) scanning recent commits
- A `.gitleaks.toml` allowlist config at the repo root
- Credential files and secret paths listed in `.gitignore`
- A pre-commit hook that runs `ggshield secret scan pre-commit` locally — this catches secrets before they leave the machine. CI gitleaks is a backstop, not a substitute. Run `make install-hooks` once per checkout to activate it.

## .gitignore

Every git repository must have a `.gitignore` that includes the common macOS and Linux noise entries. At minimum:

```gitignore
# macOS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
.AppleDouble
.LSOverride

# Linux
*~
.fuse_hidden*
.directory
.Trash-*
.nfs*
```

Add these when creating a new repo or when a repo is missing them. Language- and framework-specific entries (e.g. `__pycache__/`, `target/`, `node_modules/`) belong here too but are repo-dependent.

## Architectural Decision Records

**ADRs are required** for all significant architectural choices in every personal repo under `~/git-repos/personal/`. Write the ADR before or alongside the implementation — not after.

- **Cross-cutting decisions** (testing frameworks, CI patterns, tooling standards that apply across repos) → `dotfiles/docs/adr/`
- **Repo-specific decisions** → that repo's own `docs/adr/`
- **Numbering:** Sequential four-digit numbers (`0001`, `0002`, …); each repo's `docs/adr/` starts from `0001` independently
- **Template:** Context → Decision → Consequences → Related (Nygard-style; see any `dotfiles/docs/adr/` file for the full format)
- **Index:** Every `docs/adr/` directory must have a `README.md` with a status table listing all ADRs
- **Status lifecycle:** `Proposed` → `Accepted` → `Deprecated` / `Superseded by ADR-NNNN`

What counts as significant: choice of testing framework, CI tooling, major library adoption, data storage approach, authentication strategy, structural patterns (modularization, lib layout), security guardrails. Routine bug fixes and small features do not need ADRs.

## Superpowers Plans and Specs

Every repo must have a `docs/superpowers/` directory with a `README.md` that indexes all specs and plans. Every repo must also have a `docs/cursor/` directory for Cursor-specific documentation, rules, specs, and plans. Create both when initializing a new repo, even if empty at first.

Every repo that uses the superpowers brainstorming → writing-plans workflow must have a `docs/superpowers/README.md` that indexes all specs and plans with their status.

**Required format** (see `dotfiles/docs/superpowers/README.md` as the canonical example):

```markdown
# Superpowers Specs and Plans

Master status index for all specs and implementation plans in this directory.

## Status Key

| Status      | Meaning                          |
| ----------- | -------------------------------- |
| Done        | Implemented and merged to master |
| In Progress | Currently being implemented      |
| Pending     | Not yet started                  |

---

## All Plans

| Date       | Plan                  | Spec                  | Status |
| ---------- | --------------------- | --------------------- | ------ |
| YYYY-MM-DD | [name](plans/file.md) | [spec](specs/file.md) | Done   |

---

## Backlog

Ideas approved for future specs, in no particular order:

| Feature      | Notes             |
| ------------ | ----------------- |
| feature name | brief description |

---

## Adding a new entry

When a new spec or plan is created, add a row to the All Plans table. Set status to **In Progress** when implementation starts, **Done** when the PR merges. Also add a `> **Status: DONE**` banner at the top of the plan file once complete. Move backlog items to the All Plans table when their spec is written (remove the backlog row).
```

**Status values:** `In Progress` while implementation is active; `Done` once the PR merges.

**Maintenance rules:**

- All Plans is a single combined table — no separate Specs/Plans split.
- Spec column uses `—` when no spec was written.
- Add a row to All Plans when a new spec or plan is created.
- Set status to `Done` and add a `> **Status: DONE**` banner at the top of the plan file once the feature PR merges.
- Move backlog items to All Plans when their spec is written — delete the backlog row, don't use strikethrough.
- Keep this index current — a stale index causes future agents to treat completed plans as pending work.

## Cursor Specs and Plans

Specs and plans created for Cursor workflows must live under `docs/cursor/`:

- Specs: `docs/cursor/specs/`
- Plans: `docs/cursor/plans/`

Every repo must have `docs/cursor/README.md` that:

1. Lists specs and plans with status (single index table)
2. Includes a backlog section at the bottom
3. Is updated when a new spec/plan is created or completed

When both `docs/superpowers/` and `docs/cursor/` exist, default to `docs/cursor/` for newly created specs/plans unless the repo explicitly requires otherwise.
