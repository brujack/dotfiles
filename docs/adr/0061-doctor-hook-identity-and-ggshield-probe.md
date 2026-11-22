# ADR-0061: Doctor judges hook identity by name-matched source and probes ggshield with `quota`

**Date:** 2026-11-22
**Status:** Accepted

## Context

Security audit findings F5, F6 and F10 showed `-t doctor` passing on machines whose commit and push
gates were not working. Doctor checked that tools existed but not that the installed git hooks in
the personal repos were present, were the repo's own script, or could run, and it never checked
that `ggshield` could authenticate. A missing or foreign hook, or a rejected API key, left the
secret scan silently off.

The spec (Problem and Premise measurements) records what was measured on 2026-11-22. Two results
drive this decision: `ggshield api-status` exits 0 for a rejected key, and `ggshield quota` exits
0 only for an accepted key.

## Decision

Add `_doctor_check_git_hooks` and `_doctor_check_ggshield` to `-t doctor`.

- **Hook identity by name-matched source.** An installed hook passes when it matches a candidate
  source in the repo named `<hook>` or `<hook>-hook.sh`. Rejected: any tracked file (a cross-hook
  swap, such as a `pre-push` copy installed as `pre-commit`, would pass) and a per-repo map (one
  more table to keep in step with every repo).
- **Generated pre-commit shims** are judged by the absolute `INSTALL_PYTHON` they name, which must
  be absolute (amended R10), using `-I -c 'import pre_commit'` as the probe. A missing interpreter
  is a FAIL, because the `PATH` fallback depends on the committer's environment, not the file.
- **A `.git` directory that `git rev-parse` rejects is a FAIL** (amended R4). A worktree or
  submodule checkout, where `.git` is not a directory, is the only silent skip.
- **ggshield is probed with `ggshield quota`**, not `api-status`. Exit codes: 0 PASS, 3 FAIL
  (credential rejected), 1 or 4 WARN (unreachable; measured 2026-11-22 that a refused connection,
  DNS failure and a dead proxy all give rc 1), 124 WARN (probe timed out), any other code FAIL.
- **The ggshield resolver is duplicated in doctor**, with a drift test against the pre-commit
  hook's copy. Sharing it through a lib file was rejected: the hook would source that file from
  the working tree under scan, so a commit could replace the resolver that guards it (fail-open).
- **Doctor only.** No persistent signal (marker file, ntfy message) is written on failure; the
  operator decided this on 2026-11-22.

## Consequences

- state-ledger's dev-checkout pre-commit shim names the Mac `INSTALL_PYTHON` on `claude`, so doctor
  FAILs there until `pre-commit install` is run in that checkout.
- Doctor subprocess tests could reach the real `ggshield` and its network. A scanner test in
  `tests/setup_env/doctor_ggshield.bats` guards against that; its known gaps are in the
  superpowers Backlog.
- The resolver exists in two places. The drift test fails when they diverge, and nothing else
  keeps them equal.
- A hook edit that renames a source file breaks the name match until the candidate list is
  updated.

## Related

- Spec: [doctor-hook-and-ggshield-checks](../superpowers/specs/2026-11-22-doctor-hook-and-ggshield-checks-design.md)
- Plan: [doctor-hook-and-ggshield-checks](../superpowers/plans/2026-11-22-doctor-hook-and-ggshield-checks.md)
- ai-config ADR-0055 (Claude plugin install records), ADR-0052
- [ADR-0060](0060-bats-suite-hooks-sentinel-home.md)
