# ADR-0033: The git-hooks sweep resolves the install-hooks target one level down, and its threat model excludes your own checkout

**Date:** 2026-09-18
**Status:** Accepted. Amends [ADR-0016](0016-auto-install-git-hooks.md) §1 (discovery).

## Context

ADR-0016 has the weekly sweep (`install_git_hooks_all_repos`, `lib/git_hooks.sh`) discover
repos by reading each one's **root** Makefile for `^install-hooks:`. terraform_ansible keeps
its target in `ansible/Makefile`; its root Makefile carries none. The sweep therefore:

- never discovered it, so never re-ran its recipe;
- reported it as `:no-target` ("Makefile has no install-hooks target"), a false cause;
- left its `cp`-installed hooks to go stale. Measured 2026-09-18: its installed `pre-push` was
  a May copy (2940 bytes against 4891 tracked) on both the Mac Studio and `claude`, while
  every other repo refreshed weekly.

The completeness check only tests that each mandated hook exists and is executable, so a
stale copy passes it. Only re-running the recipe refreshes the hook, which is why being
undiscovered left the stale copy in place with nothing reporting it.

Alternatives considered:

- **A root-level delegating target in terraform_ansible** (`install-hooks: ; $(MAKE) -C ansible
install-hooks`). This would fix the one repo, but it needs a change in a repo another session
  owns, and dotfiles would still misreport the next repo shaped this way.
- **A per-repo target path in `config/hook_repos.sh`.** A hand-maintained list that goes stale
  silently, the denominator failure `tdd.md` warns about.
- **Search at depth one, derived from the tracked set** (chosen).

## Decision

**Resolution.** `_git_hooks_target_dir REPO` decides where `make install-hooks` runs:

| exit | meaning                                                                                 | sweep                                                                     | gap label     |
| ---- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| 0    | root Makefile has the target, else exactly one tracked `*/Makefile` one level down does | runs make there                                                           | —             |
| 1    | a usable Makefile exists, none has the target                                           | —                                                                         | `:no-target`  |
| 2    | two or more subdirectory Makefiles have the target                                      | never run: hooks are repo-wide and the recipes would overwrite each other | `:ambiguous`  |
| 3    | `git ls-files` failed (e.g. a corrupt index)                                            | —                                                                         | `:unreadable` |
| 4    | no usable Makefile at the root or one level down                                        | —                                                                         | bare name     |

Discovery and the gap report both call it, so they agree on what counts as a target.
Subdirectory candidates come from `git ls-files -- ':(glob)*/Makefile'`, so an untracked
Makefile is never a candidate.

**Correctness guards.** The discover records are tab-separated and newline-framed. A repo or
subdirectory name containing a newline or tab is skipped, because a split record names a
different directory to run `make` in. A candidate that is not a regular file is skipped,
because `grep` on a FIFO blocks forever and would hang every `-t update`.

**Threat model** (operator decision, 2026-09-18, during Phase 3 of PR #286). Write access to
the operator's own checkout is **out of scope**. Anyone holding it can edit the tracked
Makefile directly, so symlinked candidates, swapped directories and races between resolving
and running `make` give them nothing new. Symlinked candidates therefore resolve. The guards
above exist for correctness, not to contain that writer.

## Consequences

- terraform_ansible is discovered at `ansible/` and its hooks refresh on every sweep. Verified
  end to end on a temp clone of the real repo.
- **The next review should not re-raise same-writer findings.** Without this boundary stated,
  Phase 3 for PR #286 ran eight gate cycles. Each hardening against that writer produced the
  next round's defect: a symlink skip added in cycle 2 bought no protection and rejected a
  legitimate in-repo symlinked Makefile. The boundary is also written into the resolver's
  header comment, the place a reviewer reads first.
- Only depth one is searched. A repo that nests its target deeper needs a root target that
  delegates to it.
- A repo with install-hooks targets in two subdirectory Makefiles must choose one. It is
  reported, never guessed.
- A skipped candidate (odd name, non-regular file) counts as missing, so the gap line can say
  "no Makefile" for a repo that has a tracked but unusable one. This is accepted as rare.

## Related

- [ADR-0016](0016-auto-install-git-hooks.md) — the sweep this amends
- PR #286 — the fix, with the dated measurements and review history
- `CLAUDE.md` — Key Conventions, "`git-hooks` section coupling"
- `lib/git_hooks.sh` — `_git_hooks_target_dir` header
