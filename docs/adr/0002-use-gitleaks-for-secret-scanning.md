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
