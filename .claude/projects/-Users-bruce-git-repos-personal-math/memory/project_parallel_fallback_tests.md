---
name: project_parallel_fallback_tests
description: Patterns for testing ProcessPoolExecutor fallback in pi/e calculators (PR #43, 2026-05-05)
type: project
originSessionId: f3e36aa9-ad21-40c4-9371-fd95942b6af6
---

# Parallel Fallback Consistency Tests (PR #43, 2026-05-05)

## ProcessPoolExecutor Mock Pattern

To test the `except (PermissionError, OSError)` fallback in functions that use
`with concurrent.futures.ProcessPoolExecutor(...) as pool:`, patch at the module
import site:

```python
unittest.mock.patch(
    "pi.concurrent.futures.ProcessPoolExecutor",
    side_effect=OSError("semaphore unavailable")
)
```

The key is patching `"<module>.concurrent.futures.ProcessPoolExecutor"` (where
`<module>` is the calculator's module name, e.g. `pi` or `e`), **not**
`"concurrent.futures.ProcessPoolExecutor"`. This is the standard "patch where used"
rule applied to the attribute chain.

## n_workers Threshold for pi/e Parallel Path

Both `_calculate_pi_gmpy2` and `_calculate_e_gmpy2` only enter the
`ProcessPoolExecutor` branch when `n_workers > 1`. The parallel path is not entered
for small digit counts:

- **pi.py**: `N = digits // 14 + 10`, `chunk_size = max(100, ...)`. Need N > 100,
  which requires ~1400+ digits. Use `digits=2000` (matches the existing parallel
  test) as the established safe threshold.
- **e.py**: Similar threshold; use the same `digits=2000` figure.

Do not use small digit counts (e.g. 20) for these fallback tests — the parallel
branch will not be exercised and the mock will never trigger, causing the test to
pass vacuously.
