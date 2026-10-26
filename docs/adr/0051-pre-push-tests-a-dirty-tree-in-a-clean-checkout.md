# ADR-0051: pre-push tests a dirty tree's pushed commit in a clean checkout

**Date:** 2026-10-25
**Status:** Accepted

## Context

ADR-0049 made `scripts/pre-push` refuse a push whose refs are not at `HEAD` of the tested
tree, but the suite still ran on the working tree as it was on disk. An uncommitted edit or an
untracked, non-ignored file (the bats list is a `find tests` walk) could therefore change the
verdict in either direction: a fix made after the commit turned a failing commit green, and a
half-finished edit turned a correct push red. CI tests the pushed commit from a clean checkout,
so a false green cost a CI round trip rather than a bad merge.

ADR-0049's spec recorded its N1 as "no `git archive`, no switching, no temporary checkout",
with no reason given. Three designs were weighed in
`docs/superpowers/specs/2026-10-25-pre-push-dirty-tree-refusal-design.md`:

- **Refuse a dirty tree.** Simplest, but it widens the false red: any dirty push is blocked,
  pass or fail. Two Step 8 review rounds found every defect in the printed remedy: a
  `git stash` route through the stack every worktree shares, three lines sharing shell state
  that an agent's per-call Bash does not keep, dropped `-u`/`--force-with-lease`, unquoted
  refs pasted into a shell.
- **Always test in a temporary checkout**, retiring ADR-0049's refusal. Removes more code but
  deletes a refusal merged three days earlier; the operator kept dirty-only.
- **Test a dirty tree's pushed commit in a temporary checkout** (chosen).

## Decision

After the wrong-tree refusal, the hook reads
`git --no-optional-locks status --porcelain --untracked-files=all` of `REPO_ROOT` with the four
`GIT_*` stripped. An empty status runs `make -C "${REPO_ROOT}" test` exactly as before. A
non-empty or unreadable status runs the suite in a detached worktree of `HEAD` named
`pre-push-<sha7>` under `mktemp -d "${TMPDIR:-/tmp}/pre-push.XXXXXX"`, locked with reason
`pre-push pid <pid> testing <sha7>`, and removes it from a single-quoted `EXIT` trap
(`worktree remove -f -f`, `rm -rf` of the root, `worktree remove -f -f` again, each `|| :`).
The hook's own shell traps TERM so it waits for that cleanup. A dirty tree alone never refuses
a push; only a failure to create the temporary checkout does.

## Consequences

- When the suite runs, its verdict is always the pushed commit's, in both directions.
- A dirty push costs one `git worktree add` (seconds) on top of the suite. The real suite
  passes from a detached `/tmp` worktree (measured on `claude` and the Studio).
- During the run, every session's `git worktree list` shows the locked temporary worktree.
  The lock and its reason stop a peer's worktree sweep from removing it mid-suite.
- `kill -9` of the hook leaves one locked worktree; `git worktree remove -f -f <path>` clears
  it, including after the directory is gone. The hook never runs `git worktree prune`, which
  would clear other sessions' registrations.
- `mktemp` takes an explicit template because BSD `mktemp -d` without one ignores `TMPDIR`
  (measured on the Studio).
- ADR-0049's wrong-tree refusal and its printed remedy are unchanged; that remedy's own
  defects (unquoted refs, `-u` lost for a `HEAD` source) are a P3 Backlog row.

## Related

- Spec: [2026-10-25 pre-push dirty tree tested in a clean checkout](../superpowers/specs/2026-10-25-pre-push-dirty-tree-refusal-design.md)
- Plan: [2026-10-25 pre-push dirty-tree clean checkout](../superpowers/plans/2026-10-25-pre-push-dirty-tree.md)
- [ADR-0049](0049-pre-push-refuses-a-push-not-at-the-tested-tree.md): the wrong-tree refusal this extends
- [ADR-0017](0017-pre-push-trigger-fail-closed.md): the fail-closed trigger set
