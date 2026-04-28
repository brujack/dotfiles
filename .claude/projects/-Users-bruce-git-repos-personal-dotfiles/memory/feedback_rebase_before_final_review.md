---
name: Rebase feature branch before final code review
description: Rebase onto master before running the final code review so the reviewer only sees intentional changes, not stale-branch artifacts
type: feedback
originSessionId: 5df32ae8-b5d6-4a2f-91ba-7c1898f285c3
---

Rebase the feature branch onto `origin/master` before dispatching the final code reviewer. Do not rebase after review.

**Why:** During linux-sh-split (PR #54), the branch had drifted 6 commits behind master during the multi-hour implementation. The final code reviewer flagged changes from merged PRs #50–#53 (rosetta fix, cursor symlink) as issues. These were not intentional changes — they were stale-branch artifacts. Rebasing first would have given the reviewer a clean diff of only the linux-sh-split work.

**How to apply:** As part of subagent-driven-development wrap-up, run `git fetch origin && git rebase origin/master` on the feature branch before dispatching the final code reviewer. Confirm `make test` passes after the rebase, then review.
