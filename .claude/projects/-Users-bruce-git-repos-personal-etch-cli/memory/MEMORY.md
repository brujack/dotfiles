# Memory Index — etch-cli

- [pre-push hook runs from main repo in worktrees](project_prepush_worktree.md) — pre-push hook tests main, not the worktree branch; CI is the real gate
- [serial_test scope — all execute() callers need #[serial]](project_serial_test_scope.md) — PATH-mutating tests can race with any test that calls system commands; serialize both sides
- [tarpaulin coverage differs macOS vs Linux CI](project_coverage_linux_vs_macos.md) — local macOS is ~10pp higher than CI due to macos-gated tests; set gate from a Linux measurement
