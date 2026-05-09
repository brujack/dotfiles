# Memory Index

## Project

- [project_pi_work.md](project_pi_work.md) — Work done on pi calculator (Python multithreading + Rust implementation) in math/pi via CLI session
- [project_coverage_gate.md](project_coverage_gate.md) — ≥90% coverage enforced via CI tarpaulin (not pre-push); Swatinem cache doesn't cover ~/.cargo/bin
- [project_cargo_fmt_tarpaulin.md](project_cargo_fmt_tarpaulin.md) — Three patterns: fn_call_width=60% threshold, captured-var format syntax, break; dead probe — for keeping Rust crates above 90% after cargo fmt changes
- [project_parallel_fallback_tests.md](project_parallel_fallback_tests.md) — ProcessPoolExecutor mock pattern and n_workers digit threshold for testing pi/e parallel fallback (PR #43, 2026-05-05)
- [project_bats_infrastructure.md](project_bats_infrastructure.md) — BATS test infrastructure for hook scripts: mock layout, PATH-stripping for absent-command tests, worktree-safety proof pattern, stderr capture without --separate-stderr (PR #44, 2026-05-05)
- [project_auto_merge_gate.md](project_auto_merge_gate.md) — gh pr checks --json unusable with GITHUB_TOKEN (GraphQL workflowRun); use REST check-runs API instead; polling gate must exclude self from non-terminal check (PR #45, 2026-05-06)
- [project_prepush_stdin_fix.md](project_prepush_stdin_fix.md) — pre-push hook deadlock: Python multiprocessing resource_tracker inherits git's open stdin pipe; fix is `make test < /dev/null` (PR #47, 2026-05-09)

## Feedback

- [feedback_github_actions_patterns.md](feedback_github_actions_patterns.md) — Three required GitHub Actions patterns: env vars for inputs in run: blocks, randomized GITHUB_OUTPUT delimiter, quoted body: in softprops/action-gh-release
- [feedback_pr_review_skill.md](feedback_pr_review_skill.md) — Must invoke `pr-review` skill via Skill tool before pushing any branch; running review inline is not acceptable
- [feedback_task_tracking.md](feedback_task_tracking.md) — Mark each task completed via TaskUpdate immediately after it finishes; never let the task list fall out of sync
- [feedback_rust_io_error_other.md](feedback_rust_io_error_other.md) — Use `io::Error::other()` not `io::Error::new(io::ErrorKind::Other, ...)` — clippy io_other_error lint in Rust 1.74+
- [feedback_injectable_io_pattern.md](feedback_injectable_io_pattern.md) — All CLI Rust crates use run<W,E>(dir) pattern; main() is a thin wrapper; tests inject Vec<u8> + tempdir
- [feedback_verify_hooks_installed.md](feedback_verify_hooks_installed.md) — Verify .git/hooks/pre-push exists at session start; run `make install-hooks` if missing (user requires local test gate)
