# Architectural Decision Records Design

**Status:** Draft
**Date:** 2026-04-09

## Goal

Introduce a formal ADR (Architectural Decision Record) practice across all personal repos. Cross-cutting decisions live in `dotfiles/docs/adr/`; repo-specific decisions live in that repo's own `docs/adr/`. The template and convention are defined once in dotfiles and referenced from `~/.claude/CLAUDE.md` so they apply everywhere.

## Directory Structure

```
docs/adr/
├── README.md          # index table of all ADRs with status
├── 0001-use-bats-for-shell-testing.md
├── 0002-use-gitleaks-for-secret-scanning.md
├── 0003-profile-capability-model-for-machine-detection.md
├── 0004-lib-modular-structure-for-setup-env.md
└── 0005-require-secrets-guarding-in-all-personal-repos.md
```

Sequential four-digit numbers are used rather than dates. ADRs are referenced by number (e.g. "see ADR-0003"), which is unambiguous. Dates appear in the index and in each ADR's frontmatter.

Individual personal repos that have repo-specific architectural decisions get their own `docs/adr/` directory with the same format, starting from `0001`. They do not need to reference or replicate cross-cutting ADRs from dotfiles.

## ADR Template

Every ADR file follows this structure:

```markdown
# ADR-NNNN: Title

**Date:** YYYY-MM-DD
**Status:** Accepted | Proposed | Deprecated | Superseded by [ADR-NNNN](NNNN-title.md)

## Context

Why this decision was needed. What problem or constraint prompted it.

## Decision

What was decided, stated clearly and directly.

## Consequences

What results from this decision — both positive and negative trade-offs.

## Related

- [Spec: relevant-spec](../../superpowers/specs/YYYY-MM-DD-relevant-spec.md)
- [ADR-NNNN: related decision](NNNN-related.md)
```

### Status Lifecycle

- `Proposed` — written, not yet in effect
- `Accepted` — decision is in effect
- `Deprecated` — no longer applies, no replacement
- `Superseded by ADR-NNNN` — replaced by a newer decision; link to the new one

## Index README

`docs/adr/README.md` uses the same table pattern as `docs/superpowers/README.md`:

```markdown
# Architectural Decision Records

| ADR | Title | Date | Status |
|-----|-------|------|--------|
| [0001](0001-use-bats-for-shell-testing.md) | Use BATS for shell testing | 2026-03-27 | Accepted |
| [0002](0002-use-gitleaks-for-secret-scanning.md) | Use gitleaks for secret scanning | 2026-04-08 | Accepted |
| [0003](0003-profile-capability-model-for-machine-detection.md) | Profile/capability model for machine detection | 2026-03-31 | Accepted |
| [0004](0004-lib-modular-structure-for-setup-env.md) | Modular lib/ structure for setup_env.sh | 2026-03-31 | Accepted |
| [0005](0005-require-secrets-guarding-in-all-personal-repos.md) | Require secrets guarding in all personal repos | 2026-04-09 | Accepted |
```

## Seed ADRs

Five ADRs are created immediately to capture decisions already in effect. Dates reflect when the decision was made (from git history and spec dates), not the date of ADR creation.

| ADR | Decision | Date |
|-----|----------|------|
| 0001 | Use BATS for shell script testing | 2026-03-27 |
| 0002 | Use gitleaks for secret scanning in CI | 2026-04-08 |
| 0003 | Profile/capability model (`HAS_*` vars + `PROFILE`) for machine detection | 2026-03-31 |
| 0004 | Modular `lib/` structure — split `setup_env.sh` into `lib/constants.sh`, `helpers.sh`, `detect_env.sh`, `macos.sh`, `linux.sh`, `developer.sh`, `workflows.sh` | 2026-03-31 |
| 0005 | Require secrets guarding (gitleaks CI job + `.gitleaks.toml` + `.gitignore` credential paths) in all personal repos | 2026-04-09 |

## Convention Propagation

`~/.claude/CLAUDE.md` gains a new `## Architectural Decision Records` section:

- Cross-cutting decisions (testing frameworks, CI patterns, tooling standards) → `dotfiles/docs/adr/`
- Repo-specific decisions → that repo's `docs/adr/`
- Template: Context → Decision → Consequences → Related (Nygard-style; see any `dotfiles/docs/adr/` file for the full format)
- When making a significant architectural choice, write an ADR before or alongside implementation

## Files Created/Modified

| Action | File |
|--------|------|
| Create | `docs/adr/README.md` |
| Create | `docs/adr/0001-use-bats-for-shell-testing.md` |
| Create | `docs/adr/0002-use-gitleaks-for-secret-scanning.md` |
| Create | `docs/adr/0003-profile-capability-model-for-machine-detection.md` |
| Create | `docs/adr/0004-lib-modular-structure-for-setup-env.md` |
| Create | `docs/adr/0005-require-secrets-guarding-in-all-personal-repos.md` |
| Modify | `~/.claude/CLAUDE.md` — add ADR convention section |
| Modify | `dotfiles/CLAUDE.md` — note docs/adr/ in Layout section |
| Modify | `dotfiles/README.md` — mention docs/adr/ in Repository Layout |
