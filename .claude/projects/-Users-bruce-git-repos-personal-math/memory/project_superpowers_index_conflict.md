---
name: docs/superpowers/README.md merge conflict pattern
description: Feature branches that update superpowers README status cause predictable merge conflicts on pull to master
type: project
originSessionId: df750f48-8328-4b80-954d-8542bbff6916
---

After `git pull` post-merge on a feature that updated `docs/superpowers/README.md` (changing status from Pending → In Progress), a merge conflict occurs because master also had a prior commit touching that file.

**Why:** The superpowers README is updated both on master (when the spec is first committed with "Pending") and on the feature branch (when implementation sets status to "In Progress"). These diverge.

**How to apply:** After resolving, take the feature branch version of the table row and immediately set status to "Done" (not "In Progress" — the PR has already merged). Also add `> **Status: DONE**` banner to the plan file. Then commit and push the resolution directly to master.
