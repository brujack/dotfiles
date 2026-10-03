# ADR-0038: The direct-to-master guard is default-deny

**Date:** 2026-10-02
**Status:** Accepted.

## Context

`ci.yml` runs on `pull_request` only, so a commit pushed straight to `master` is tested by
nothing except the pre-push hook on the pushing machine, which since 2026-09-19 is the Linux
`claude` box. dotfiles#306 (ADR-0037) made every PR run the suite on macOS; a direct push
still bypassed it.

The guard in `scripts/pre-push` refused only an "executable-class" deny list (`*.sh`,
`*.bash`, `*.bats`, `*.zsh`, `Makefile`, two extensionless hooks) and recorded that narrow
scope as a deliberate choice. It let through `tests/mocks/*` (extensionless shell), Python,
`.zshrc`, `.zprofile`, `pyproject.toml`, `uv.lock`, the requirements renderings and workflow
files. The operator reversed that on 2026-10-02: no code reaches `master` except through a
PR; docs may still go direct, untested.

Two defects in the old hook were found while specifying this. The guard only ran when
`git diff` produced output, so a range that could not be resolved (a force-push over an
unfetched remote) ran the suite, refused nothing and exited 0. And two scripts push to
`master` every week, one of them writing a non-`.md` state file.

Measured on a deep clone, first-parent commits on `master` since 2026-06-01: 561 of 750 had
no PR suffix. The old list refused 18 of them, this design refuses 28, 10 newly: `.warp/settings.toml`
(4), `renovate.json` (3), `ubuntu_common_packages.txt` (1), `scripts/phrase_check.py` with its
test (1) and `.github/workflows/ci.yml` (1). That is about three a month.

## Decision

1. **One predicate, `_path_is_inert`, decides both the suite trigger and the master guard.**
   This amends ADR-0017's inert set, which listed inert classes by pattern, and supersedes
   the guard's deliberately narrow executable-class scope. The two can no longer drift.
2. **A path is inert only if** it is a `.md` outside the root `tests/`, or the root
   `LICENSE`, **and** its blob at the pushed tip does not start with `#!`. `make lint`
   selects shell files by first line whatever their name, so a name alone is not enough. A
   path deleted at the tip is judged by name. Everything else is not inert, including any
   file type added in future.
3. **A push to `refs/heads/master` is refused if its range carries any non-inert path.**
   The range is the whole push, not the tip commit.
4. **An unresolvable range on `master` is refused**, with a message to `git fetch` and retry.
   On any other ref it still runs the suite.
5. **Recovery is printed from each ref line's `local_ref`**, not from the current branch.
   Measured: `git push origin HEAD:master` hands the hook `local_ref=HEAD`, which the hook
   resolves with `git symbolic-ref`.
6. **Emergency route:** open the PR and merge it with `gh pr merge --admin`. This works
   because `enforce_admins` is off, and it stays off. The hook is never bypassed for this;
   `hotfix-cycle` and `rollback-cycle` use the same route.
7. **`tests/scripts/docs_inert_premise.bats` pins the premise** that makes an inert `.md`
   safe to push untested: no `make test` step and no test reads a tracked `.md` outside
   `tests/`. A new reader fails the test rather than silently invalidating the guard.
8. **The weekly digest state file is renamed** `.platform-state.txt` to `.platform-state.md`
   with `git mv`, so the scripts that push it stay inside the inert set and its content
   carries over.
9. **Hook-defect recovery.** `.git/hooks/pre-push` symlinks the main checkout's copy, so a
   broken hook blocks every push from every worktree. The one sanctioned recovery is a fix
   branch pushed with `--no-verify`, then a PR. A defective guard is never fixed by a
   direct push to `master`.

## Consequences

- **About three pushes a month that used to go direct now need a PR**, mostly config
  (`.warp/settings.toml`, `renovate.json`, package lists).
- **The digest state file is now `.md`**, and the premise test must keep passing with it
  in place.
- **A push carrying a branch and `master` is refused whole**; push the branch on its own.
- **The inert set is stricter than `make lint` needs**, since any `#!` is refused. No
  tracked `.md` or `LICENSE` starts with one, so this costs nothing today.
- **Branch protection is unchanged.** Adding `test-macos` and `bash-coverage` to required
  checks is a repository setting left to the operator.

## Related

- ADR-0017 (the pre-push trigger fails closed; its inert set is amended here)
- ADR-0037 (the macOS test suite gates merge)
- `docs/superpowers/specs/2026-10-02-master-guard-default-deny-design.md`
- `docs/superpowers/plans/2026-10-02-master-guard-default-deny.md`
