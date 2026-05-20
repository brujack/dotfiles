# ADR-0007: Codify Branch Protection via Script

**Date:** 2026-05-19
**Status:** Accepted

## Context

All personal repos had partial branch protection (linear history, no force-push, no deletion)
but were missing two controls: required CI status checks and required signed commits. These
were set manually per repo, making them easy to skip on new repos and hard to audit.

Terraform_ansible has a special constraint: both CI workflows are path-filtered
(`ansible/**` and `aws-terraform/.../`), and the terraform plan workflow only triggers on
`push`, not `pull_request`. No workflow runs on all PRs, so universal required status checks
would permanently block any PR that doesn't touch the filtered paths.

Alternatives considered:

- Manual per-repo GitHub UI clicks — not repeatable, not auditable
- GitHub Actions workflow (workflow_dispatch) — adds CI complexity, still needs per-repo config
- Terraform/IaC for GitHub provider — heavyweight, requires credential management

## Decision

A single idempotent shell script `scripts/apply-branch-protection.sh` in ai-config is the
canonical source of truth for desired branch protection state across all personal repos.

Per-repo configuration:

- **math, ai-config**: `required_status_checks: [secret-scan]`, signed commits enabled
- **dotfiles**: `required_status_checks: [test, lint-macos, powershell, secret-scan]`, signed commits enabled
- **etch-cli**: `required_status_checks: [test, cargo-audit, secret-scan, snyk-scan, docs-lint, docs-build]`, signed commits enabled, branch is `main` not `master`
- **terraform_ansible**: `required_status_checks: null` (path-filtered CI — see Context), signed commits enabled

Required checks match each repo's auto-merge `needs:` list exactly — same gate that
already controls merges, now also enforced at the branch level.

`enforce_admins: false` on all repos — admin retains ability to push directly to master for
docs, memory, and config-only changes per the git-workflow standard.

## Consequences

- New repos must run Step 9 of the `new-repo-bootstrap` skill (branch protection commands)
  and add them to the repo's auto-merge `needs:` pattern
- Re-running the script is safe and serves as drift detection
- `required_signatures` on master conflicts with CI auto-merge (`gh pr merge --squash`
  creates unsigned commits); workaround is `gh pr merge --squash --admin` when
  `enforce_admins: false`
- terraform_ansible will never have required status checks unless a universal (non-path-filtered)
  CI workflow is added

## Related

- [scripts/apply-branch-protection.sh](../../../ai-config/scripts/apply-branch-protection.sh)
- [ai-config docs/superpowers/specs/2026-05-19-branch-protection-design.md](../../../ai-config/docs/superpowers/specs/2026-05-19-branch-protection-design.md)
- ADR-0005: Require secrets guarding in all personal repos
