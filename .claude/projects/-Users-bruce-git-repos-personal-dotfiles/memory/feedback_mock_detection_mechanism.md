---
name: mock-detection-mechanism
description: Shell functions should use package-manager queries (not command -v) for mockable package detection in BATS tests
type: feedback
---

Use the package manager's query command for detecting whether something is installed, not `command -v`.

**Why:** `command -v` checks the real PATH and finds the real binary if it's installed on the dev machine — PATH-based mocks can't intercept it. This caused test 104 (`check_and_install_nala`) to always take the "already installed" branch on machines where nala is present, regardless of mock setup.

**How to apply:** In shell functions that detect installed packages before conditionally installing them, prefer:

- Debian/Ubuntu: `dpkg -l pkg 2>/dev/null | grep -q '^ii'`
- RPM: `rpm -q pkg`
- Homebrew: `brew list pkg`

These route through the mock infrastructure (the mock intercepts `dpkg`, `rpm`, `brew`) and can be controlled via `MOCK_DPKG_EXIT`, `MOCK_BREW_LIST_FORMULA`, etc. Also update the mock script to output the expected listing format when a `MOCK_<CMD>_<CONTEXT>` variable is set, so tests can simulate both "installed" and "not installed" states.
