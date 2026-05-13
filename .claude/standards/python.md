## Python

### Linting

`ruff check .`

### CLI Entry-Point Guard

Every Python CLI script must have an explicit entry-point guard at the bottom:

```python
if __name__ == "__main__":
    main()
```

When TDD subagents test by importing the module and calling functions directly, the guard can be silently absent — all tests pass but `python3 script.py` does nothing. In any spec compliance review for a Python CLI task, explicitly read the last few lines of the source file and confirm the guard is present.

### Test File Stubs (TDD)

When scaffolding a Python test file stub for TDD, only include imports for functions that already exist and are used by the current test class. Do not pre-populate all future imports upfront.

`ruff check` treats unused imports as errors; the `test: lint` dependency means `make test` fails immediately. Add imports incrementally, one per TDD cycle, as new test classes are written:

```python
# Scaffold — Task 1
import unittest

if __name__ == "__main__":
    unittest.main()
```

Then in each subsequent task, add only the specific `from <module> import <function>` needed for that task's test class.

### ProcessPoolExecutor Fallback

Any Python code that uses `ProcessPoolExecutor` for parallel work must gracefully degrade in restricted environments (semaphore unavailable, permission errors):

```python
try:
    with concurrent.futures.ProcessPoolExecutor(max_workers=n) as pool:
        results = list(pool.map(fn, items))
except (PermissionError, OSError):
    print("Warning: parallel execution unavailable, falling back to serial mode.", flush=True)
    results = [fn(item) for item in items]
```

#### Testing the fallback

Patch at the module import site — not at the canonical path — following the "patch where used" rule:

```python
unittest.mock.patch(
    "<module>.concurrent.futures.ProcessPoolExecutor",
    side_effect=OSError("semaphore unavailable")
)
```

The parallel branch only activates above a certain worker/chunk threshold. Use a digit count or input size large enough to guarantee the `ProcessPoolExecutor` branch is actually entered; otherwise the mock never triggers and the test passes vacuously. Verify the threshold by reading the branching condition in the implementation before writing the test.
