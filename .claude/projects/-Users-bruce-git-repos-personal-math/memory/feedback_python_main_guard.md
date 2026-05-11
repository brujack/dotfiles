---
name: Python __main__ guard can be silently missing in TDD subagent implementations
description: Subagent TDD implementers test via import, not subprocess — the if __name__ == "__main__" guard can be absent without any test failure
type: feedback
originSessionId: dbf0123f-5acb-467e-b3fa-1e6a4315c531
---

Always explicitly verify `if __name__ == "__main__": main()` exists in new Python CLI scripts before marking work complete.

**Why:** TDD subagent implementers test by importing the module and calling functions directly. This means the entry-point guard can be silently absent — all tests pass, but running `python3 script.py` does nothing. Caught in PR #48 (perfect-numbers) by the final code reviewer, not the per-task spec reviewers.

**How to apply:** In any spec compliance review for a Python CLI task, explicitly read the last few lines of the source file and confirm `if __name__ == "__main__": main()` is present. Do not assume the implementer added it just because the task description included the full file content.
