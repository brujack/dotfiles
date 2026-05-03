---
name: serial_test scope — all execute() callers need #[serial]
description: PATH-mutating tests (#[serial]) can race with any test that calls system commands via PATH, not just other PATH-mutating tests
type: project
---

When `#[serial]` is used to protect PATH-mutation in tests, the serialization only applies to tests that ALSO carry `#[serial]`. Any test that runs a real system command (echo, env, false, etc.) via `Exec::execute()` or `which::which()` can fail if a PATH-mutating serial test runs concurrently.

**Why:** `#[serial]` acquires a global lock among serial tests only. Parallel (non-serial) tests run freely alongside serial tests and can observe modified PATH.

**How to apply:** In any crate that has PATH-mutating tests, add `#[serial]` to EVERY test that invokes a real binary. Affected atoms: `atoms/command/exec.rs` (all `execute_*` tests). Affected providers: any that call `which::which()` in their test bodies.

Discovered during test coverage work (PR #4) — a flaky 2/5 failure rate in `execute_succeeds_for_echo` was traced to concurrent PATH restriction in linux provider tests.
