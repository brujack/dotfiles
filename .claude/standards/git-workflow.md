## Feature Branches

**Never commit implementation work directly to `main`/`master`.** Always work on a feature branch:

1. Create a worktree on a feature branch before starting implementation (use `superpowers:using-git-worktrees`)
2. Commit work to the feature branch
3. Open a PR — CI runs and auto-merges on pass
4. Before pushing or force-pushing to a branch that has an open PR, verify the PR and branch still exist on remote — if the PR already auto-merged the branch may be gone, and pushing would silently recreate it:
   ```bash
   gh pr view <number> --json state,headRefName
   git ls-remote --heads origin <branch-name>
   ```
5. After the PR merges, delete the feature branch locally and remotely:
   ```bash
   git branch -d feature/branch-name
   git push origin --delete feature/branch-name
   ```

This applies to all repos. Committing directly to master bypasses CI and the review workflow.

Exception: documentation-only fixes (typos, README updates, memory commits) may go directly to master.

After every PR merge, run a full stale branch sweep (not just the current branch):

```bash
# Remote: prune tracking refs, then delete any with merged PRs
git fetch --prune
for branch in $(git branch -r | grep -v master | sed 's|origin/||'); do
  if gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null | grep -q .; then
    git push origin --delete "$branch"
  fi
done

# Local (squash-merged): git branch --merged misses these, check via gh
for branch in $(git branch | grep -v '^\*' | grep -v master); do
  if gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null | grep -q .; then
    git branch -D "$branch"
  fi
done

# Local (regular merged): standard check
git branch --merged master | grep -v master | xargs -r git branch -d
```

Also run this sweep at session start and session end to catch accumulated stale branches.

### PR Monitoring

After opening a PR, monitor it until it is resolved — either merged or failed. Do not consider the work done at push time.

**After every `gh pr create`:**

1. Run the `code-review:code-review` skill on the new PR — pass the PR number so the agent reviews the actual diff
2. Poll CI status with `gh pr checks <number> --watch` until all checks complete
3. If any check fails:
   - Read the failure output: `gh run view <run-id> --log-failed`
   - Fix the issue on the feature branch, commit, and push
   - CI re-runs automatically; return to step 1
4. Once all checks pass and the PR auto-merges, delete the branch:
   ```bash
   git branch -d feature/branch-name
   git push origin --delete feature/branch-name
   ```
5. If the PR does not auto-merge (repo has no auto-merge job), notify the user and wait for instructions

If the session ends before CI finishes, note the PR number and status in the conversation so the user can follow up.

### PR Review Gate

**Always run the `pr-review` skill before pushing any feature branch.** This applies
regardless of which workflow was used to create the branch — do not skip it even for
small changes, even if no explicit skill workflow was followed.

Only push when verdict is PASS. If HOLD:

1. Fix all CRITICAL findings
2. Run make test — confirm no regressions
3. Commit the fixes
4. Re-run pr-review
5. Repeat until PASS, or escalate to user after two failed fix attempts

WARNING and INFO findings are advisory — surface them but do not block the push.

This rule is a durable backup: if `claude plugins update superpowers` overwrites
the finishing-a-development-branch skill file, this rule still enforces the gate.

### Learning Analysis

**After every PR merge or direct master commit, always run a learning analysis before closing out.** Ask:

1. **What did I learn?** — Any non-obvious pattern, gotcha, constraint, or decision that came up.
2. **Where should I document it?** — Memory file, ADR, code comment, or CLAUDE.md update.

Write the documentation, commit it, then close out. If nothing new was learned, state that explicitly so the omission is intentional.

This rule is a durable backup: if `claude plugins update superpowers` overwrites the finishing-a-development-branch skill file, this rule still enforces the learning analysis step.

### Dispatching Subagents to Worktrees

When using `superpowers:subagent-driven-development` with a worktree, implementer
subagents must be told the working directory **prominently at the top** of the prompt,
not just buried in a "Work from:" line at the bottom. Without this, subagents
default to the parent repo and commit to the wrong directory.

Required pattern in every implementer prompt:

```
**IMPORTANT: All work must happen in `/path/to/worktree/`. Do not cd anywhere else.**
```

Also have the spec reviewer verify the commit landed on the correct branch:

```bash
git -C /path/to/worktree log --oneline -1
```
