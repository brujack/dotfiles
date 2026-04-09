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
