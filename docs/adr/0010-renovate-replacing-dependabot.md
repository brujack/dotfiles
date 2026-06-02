# ADR-0010: Renovate Replacing Dependabot for Dependency Updates

**Date:** 2026-05-18
**Status:** Accepted

## Context

All personal repos used GitHub Dependabot for automated dependency PRs. Problems with
Dependabot at this scale:

- No PR grouping: each dependency gets its own PR, producing high churn for repos with many
  Rust crates or GitHub Actions pins
- No shared configuration across repos: each repo's `.github/dependabot.yml` is independent
  with no preset inheritance
- No cross-repo consistency: schedule, auto-merge behaviour, and grouping must be duplicated
  per repo and drift over time
- Minor/patch PRs accumulate faster than they can be merged when running across four repos

Renovate provides grouping, shared preset inheritance, and richer scheduling — directly
addressing all four problems.

Alternatives considered:

- Dependabot with per-repo grouping config — grouping support was added in 2023 but requires
  per-repo YAML; still no shared preset mechanism
- Manual dependency updates — not automated, not auditable
- Dependabot + a separate automation layer — adds complexity without eliminating the per-repo
  config duplication problem

## Decision

Replace Dependabot with Renovate in all personal repos (dotfiles, math, etch-cli, etch-config,
ai-config). Each repo gets a `renovate.json` that extends a shared preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>brujack/ai-config//renovate-presets/default.json"]
}
```

The shared preset (`ai-config/renovate-presets/default.json`) is the single source of truth
and defines:

- GitHub Actions updates grouped weekly (minor/patch auto-merge, major manual review)
- Rust crate updates grouped weekly
- Python dependency updates grouped weekly
- Renovate's self-update PR suppressed (would be circular given the preset lives in ai-config)

Per-repo overrides are allowed in each repo's `renovate.json` for package-specific rules.

**Rollout order constraint:** the shared preset must be merged to ai-config `master` BEFORE
adding `renovate.json` to any other repo. Renovate resolves `github>org/repo//path` preset
references against the default branch at run time — if the preset file does not exist on
master when Renovate first runs, all repos extending it receive a config error and no
dependency PRs are created.

Dependabot config files (`.github/dependabot.yml`) are removed from all repos as part of
the migration.

This ADR lives in dotfiles because dotfiles is the canonical location for cross-repo
architectural decisions.

## Consequences

- One PR per grouped category per week (Actions, Rust, Python) instead of one PR per package
- Shared configuration: updating the preset in ai-config propagates to all repos at next run
- `.github/dependabot.yml` files removed from all personal repos
- Renovate runs on the GitHub Renovate App (no self-hosted runner required)
- The rollout order constraint (preset on master first) must be followed for any new repo
  that extends the shared preset — documented in `ai-config` CLAUDE.md and CI standards

## Related

- [ai-config/renovate-presets/default.json](../../../ai-config/renovate-presets/default.json)
- [ai-config CLAUDE.md — Renovate Shared Preset Ordering](../../../ai-config/CLAUDE.md)
- ADR-0005: Require secrets guarding in all personal repos
- ADR-0007: Codify branch protection via script
