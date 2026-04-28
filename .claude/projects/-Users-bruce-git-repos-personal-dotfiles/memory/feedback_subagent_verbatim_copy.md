---
name: Subagent verbatim-copy must read source file
description: Implementer subagents doing verbatim extractions must read the actual source file, not rely on plan code examples which may be stale
type: feedback
originSessionId: 5df32ae8-b5d6-4a2f-91ba-7c1898f285c3
---

When dispatching a subagent to extract functions verbatim from an existing file, explicitly instruct the subagent to read the source file before writing — do not let them rely on code shown in the plan or spec.

**Why:** During linux-sh-split (PR #54), the Task 1 subagent wrote `install_zsh_linux` and `install_bats` from what appeared to be an older version in the plan rather than the actual current `lib/linux.sh`. The spec review caught the divergence, but it required a fix cycle. The plan's code examples are documentation aids, not authoritative source — the real file is.

**How to apply:** Implementer prompt for verbatim-extraction tasks must say something like: "Read `lib/linux.sh` in full before extracting — do not copy from the plan's code examples." Spec reviewer must diff extracted functions against the actual source file, not the plan.
