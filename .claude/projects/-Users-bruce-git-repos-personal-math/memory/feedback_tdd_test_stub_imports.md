---
name: TDD test stub imports — only import what current test class uses
description: In TDD, test file stubs must import only what's already implemented; ruff fails on unused imports blocking make test
type: feedback
originSessionId: df750f48-8328-4b80-954d-8542bbff6916
---

When scaffolding a Python test file stub for TDD, only include imports for functions that already exist and are used by the current test classes. Do NOT pre-populate all future imports upfront.

**Why:** ruff flags unused imports as errors; `test: lint` dependency means `make test` immediately fails. Each TDD task should add imports incrementally as new test classes are written.

**How to apply:** In the scaffold task (Task 1), create `test_collatz.py` with only `import unittest` and `if __name__ == "__main__": unittest.main()`. In each subsequent TDD task, add the specific `from collatz import <function>` needed for that task's test class. This matches how other test files in this repo are structured (they import everything they use, no more).

Observed in PR #49 (collatz, 2026-05-12): scaffold stub had all imports listed upfront; subagent fixed by stripping to only `collatz_next` after Task 2 exposed the ruff failure.
